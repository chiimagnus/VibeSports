//
//  CameraSession.swift
//  VibeSports
//
//  Created by chii_magnus on 2026/2/5.
//

import AVFoundation
import Combine
import Foundation

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

            captureSession.startRunning()
            state = .running
        } catch {
            state = .failed(message: String(describing: error))
        }
    }

    func stop() {
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
    }
}

enum CameraSessionError: Error {
    case noCameraDevice
    case cannotAddInput
}
