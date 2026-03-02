@preconcurrency import AVFoundation
import Combine
import Foundation
import QuartzCore
import os

@MainActor
protocol CameraSessionProtocol: AnyObject, ObservableObject {
    associatedtype SessionState: Equatable

    var state: SessionState { get }
    var statePublisher: AnyPublisher<SessionState, Never> { get }

    var captureSession: AVCaptureSession { get }
    var posePublisher: AnyPublisher<Pose?, Never> { get }
    var runningHeadPublisher: AnyPublisher<RunningHeadObservation?, Never> { get }

    func start() async
    func stop()
}

@MainActor
final class CameraSession: NSObject, ObservableObject {
    enum AnalysisMode: Sendable, Equatable {
        case runningHeadOnly
        case boxingPose
    }

    enum State: Equatable {
        case idle
        case requestingAuthorization
        case unauthorized
        case running
        case failed(message: String)
    }

    @Published private(set) var state: State = .idle

    let captureSession = AVCaptureSession()

    var onPose: ((Pose?) -> Void)?
    var onRunningHead: ((RunningHeadObservation?) -> Void)?

    private let poseSubject = PassthroughSubject<Pose?, Never>()
    private let runningHeadSubject = PassthroughSubject<RunningHeadObservation?, Never>()

    private let outputQueue = DispatchQueue(label: "com.chiimagnus.vibesports.camera.output")
    private let sessionQueue = DispatchQueue(label: "com.chiimagnus.vibesports.camera.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let outputHandler: OutputHandler

    private var isConfigured = false

    init(
        poseDetector: any PoseDetecting = PoseDetector(),
        runningHeadDetector: any RunningHeadDetecting = RunningHeadDetector()
    ) {
        self.outputHandler = OutputHandler(
            poseDetector: poseDetector,
            runningHeadDetector: runningHeadDetector
        )
        super.init()
    }

    func start() async {
        guard state != .running else { return }

        state = .requestingAuthorization
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard granted else {
            state = .unauthorized
            return
        }

        do {
            if !isConfigured {
                try configure()
                isConfigured = true
            }

            outputHandler.isEnabled = true
            let session = captureSession
            await withCheckedContinuation { continuation in
                sessionQueue.async {
                    session.startRunning()
                    continuation.resume()
                }
            }
            state = .running
        } catch {
            state = .failed(message: String(describing: error))
        }
    }

    func stop() {
        outputHandler.isEnabled = false
        outputHandler.setAnalysisMode(.boxingPose)
        let session = captureSession
        sessionQueue.async {
            session.stopRunning()
        }
        state = .idle
    }

    private func configure() throws {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        defer {
            captureSession.commitConfiguration()
        }

        guard let device = AVCaptureDevice.default(for: .video) else {
            throw CameraSessionError.noCameraDevice
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else {
            throw CameraSessionError.cannotAddInput
        }
        captureSession.addInput(input)

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(outputHandler, queue: outputQueue)
        guard captureSession.canAddOutput(videoOutput) else {
            throw CameraSessionError.cannotAddVideoOutput
        }
        captureSession.addOutput(videoOutput)

        outputHandler.onPose = { [weak self] pose in
            guard let self else { return }
            Task { @MainActor in
                self.onPose?(pose)
                self.poseSubject.send(pose)
            }
        }

        outputHandler.onRunningHead = { [weak self] observation in
            guard let self else { return }
            Task { @MainActor in
                self.onRunningHead?(observation)
                self.runningHeadSubject.send(observation)
            }
        }
    }

    func setAnalysisMode(_ mode: AnalysisMode) {
        outputHandler.setAnalysisMode(mode)
    }
}

extension CameraSession: CameraSessionProtocol {
    typealias SessionState = State

    var statePublisher: AnyPublisher<State, Never> {
        $state.eraseToAnyPublisher()
    }

    var posePublisher: AnyPublisher<Pose?, Never> {
        poseSubject.eraseToAnyPublisher()
    }

    var runningHeadPublisher: AnyPublisher<RunningHeadObservation?, Never> {
        runningHeadSubject.eraseToAnyPublisher()
    }
}

enum CameraSessionError: Error {
    case noCameraDevice
    case cannotAddInput
    case cannotAddVideoOutput
}

private final class OutputHandler: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onPose: ((Pose?) -> Void)?
    var onRunningHead: ((RunningHeadObservation?) -> Void)?
    var processingInterval: CFTimeInterval = 1.0 / 20.0

    private let poseDetector: any PoseDetecting
    private let runningHeadDetector: any RunningHeadDetecting
    private struct State {
        var isEnabled = false
        var lastProcessTime: CFTimeInterval = 0
        var analysisMode: CameraSession.AnalysisMode = .boxingPose
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    init(poseDetector: any PoseDetecting, runningHeadDetector: any RunningHeadDetecting) {
        self.poseDetector = poseDetector
        self.runningHeadDetector = runningHeadDetector
        super.init()
    }

    var isEnabled: Bool {
        get { lock.withLock { $0.isEnabled } }
        set { lock.withLock { $0.isEnabled = newValue } }
    }

    func setAnalysisMode(_ mode: CameraSession.AnalysisMode) {
        lock.withLock { state in
            state.analysisMode = mode
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = CACurrentMediaTime()
        let interval = processingInterval
        let shouldProcess = lock.withLock { state -> Bool in
            guard state.isEnabled else { return false }
            guard now - state.lastProcessTime >= interval else { return false }
            state.lastProcessTime = now
            return true
        }
        guard shouldProcess else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let mode = lock.withLock { $0.analysisMode }
        switch mode {
        case .boxingPose:
            let pose = try? poseDetector.detect(in: pixelBuffer)
            onPose?(pose)

        case .runningHeadOnly:
            let observation = try? runningHeadDetector.detect(in: pixelBuffer)
            onRunningHead?(observation)
        }
    }
}
