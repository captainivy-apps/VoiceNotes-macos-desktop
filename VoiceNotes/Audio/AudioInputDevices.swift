import AVFoundation
import Foundation

/// A selectable audio input device.
struct AudioInputDevice: Identifiable, Equatable {
    /// `AVCaptureDevice.uniqueID`, stable across reboots and re-plugs.
    let id: String
    let name: String
}

/// Enumerates audio input devices through AVFoundation.
enum AudioInputDevices {
    static func all() -> [AudioInputDevice] {
        discoveryDevices().map { AudioInputDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    static func captureDevice(forUID uid: String) -> AVCaptureDevice? {
        if let device = AVCaptureDevice(uniqueID: uid) {
            return device
        }
        return discoveryDevices().first { $0.uniqueID == uid }
    }

    static func defaultDevice() -> AVCaptureDevice? {
        AVCaptureDevice.default(for: .audio)
    }

    /// Human-readable name of the device that will actually be used, given a
    /// saved preference UID (empty means system default).
    static func currentInputName(selectedUID: String) -> String {
        if !selectedUID.isEmpty {
            if let match = captureDevice(forUID: selectedUID) {
                return match.localizedName
            }
            if let def = defaultDevice() {
                return "系统默认（\(def.localizedName)）· 已选设备不可用"
            }
            return "系统默认 · 已选设备不可用"
        }
        if let def = defaultDevice() {
            return "系统默认（\(def.localizedName)）"
        }
        return "系统默认"
    }

    private static func discoveryDevices() -> [AVCaptureDevice] {
        var types: [AVCaptureDevice.DeviceType] = [.builtInMicrophone, .externalUnknown]
        if #available(macOS 14.0, *) {
            types.insert(.microphone, at: 0)
        }
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .audio,
            position: .unspecified
        )
        var seen = Set<String>()
        return session.devices.filter { seen.insert($0.uniqueID).inserted }
    }
}
