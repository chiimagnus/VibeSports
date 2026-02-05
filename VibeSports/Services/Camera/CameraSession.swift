import AVFoundation
import Combine
import Foundation
import QuartzCore
import os

@MainActor
final class CameraSession: NSObject, ObservableObject {
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

    private let outputQueue = DispatchQueue(label: "com.chiimagnus.vibesports.camera.output")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let outputHandler = OutputHandler()

    private var isConfigured = false

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
            captureSession.startRunning()
            state = .running
        } catch {
            state = .failed(message: String(describing: error))
        }
    }

    func stop() {
        outputHandler.isEnabled = false
        captureSession.stopRunning()
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
            }
        }
    }
}

enum CameraSessionError: Error {
    case noCameraDevice
    case cannotAddInput
    case cannotAddVideoOutput
}

private final class OutputHandler: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onPose: ((Pose?) -> Void)?
    var processingInterval: CFTimeInterval = 1.0 / 20.0

    private let poseDetector = PoseDetector()
    private struct State {
        var isEnabled = false
        var lastProcessTime: CFTimeInterval = 0
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    var isEnabled: Bool {
        get { lock.withLock { $0.isEnabled } }
        set { lock.withLock { $0.isEnabled = newValue } }
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
        let pose = try? poseDetector.detect(in: pixelBuffer)
        onPose?(pose)
    }
}
