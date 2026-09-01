import ARKit
import AVFoundation
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class ARPermissionStore {
    private(set) var cameraStatus: AVAuthorizationStatus

    var isARSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    init() {
        self.cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    func refreshCameraStatus() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    func requestCameraAccess() async -> Bool {
        guard isARSupported else {
            refreshCameraStatus()
            return false
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraStatus = .authorized
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            refreshCameraStatus()
            return granted
        case .denied, .restricted:
            refreshCameraStatus()
            return false
        @unknown default:
            refreshCameraStatus()
            return false
        }
    }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
