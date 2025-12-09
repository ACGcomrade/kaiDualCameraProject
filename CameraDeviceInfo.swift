import AVFoundation
import AVFoundation
import UIKit

/// Information about a camera device
struct CameraDeviceInfo: Identifiable, Hashable {
    let id: String
    let device: AVCaptureDevice
    let position: AVCaptureDevice.Position
    let deviceType: AVCaptureDevice.DeviceType
    let displayName: String
    let focalLength: String
    
    static func == (lhs: CameraDeviceInfo, rhs: CameraDeviceInfo) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    /// Get user-friendly name for camera type
    var typeName: String {
        switch deviceType {
        case .builtInWideAngleCamera:
            return "Wide"
        case .builtInUltraWideCamera:
            return "Ultra Wide"
        case .builtInTelephotoCamera:
            return "Telephoto"
        case .builtInDualCamera:
            return "Dual"
        case .builtInDualWideCamera:
            return "Dual Wide"
        case .builtInTripleCamera:
            return "Triple"
        case .builtInTrueDepthCamera:
            return "TrueDepth"
        default:
            return "Camera"
        }
    }
    
    /// Get position name
    var positionName: String {
        switch position {
        case .back:
            return "后摄"
        case .front:
            return "前摄"
        case .unspecified:
            return "未知"
        @unknown default:
            return "未知"
        }
    }
}

/// Detector for all available cameras on device
class CameraDeviceDetector {
    
    /// Get all available camera devices (properly deduplicated)
    static func getAllAvailableCameras() -> [CameraDeviceInfo] {
        print("📷 CameraDeviceDetector: Detecting all available cameras...")
        
        var cameras: [CameraDeviceInfo] = []
        var seenDeviceIDs = Set<String>()
        
        // Use discovery session - this is the most reliable way
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera,
            .builtInTrueDepthCamera
        ]
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )
        
        for device in discoverySession.devices {
            // Skip if already added (using uniqueID)
            if seenDeviceIDs.contains(device.uniqueID) {
                print("   ⏭️  Skipping duplicate: \(device.localizedName)")
                continue
            }
            
            let focalLength = getFocalLength(for: device)
            let displayName = getDisplayName(for: device, position: device.position, type: device.deviceType)
            
            let info = CameraDeviceInfo(
                id: device.uniqueID,
                device: device,
                position: device.position,
                deviceType: device.deviceType,
                displayName: displayName,
                focalLength: focalLength
            )
            
            cameras.append(info)
            seenDeviceIDs.insert(device.uniqueID)
            print("   ✅ Found: \(displayName) (\(focalLength)) - ID: \(device.uniqueID)")
        }
        
        // Sort: back cameras first, then front cameras
        // Within same position, sort by focal length (wide to tele)
        cameras.sort { (a, b) in
            if a.position != b.position {
                return a.position == .back
            }
            // Extract numeric value from focal length for sorting
            let aZoom = extractZoomFactor(from: a.focalLength)
            let bZoom = extractZoomFactor(from: b.focalLength)
            return aZoom < bZoom
        }
        
        print("📷 CameraDeviceDetector: Total unique cameras found: \(cameras.count)")
        return cameras
    }
    
    /// Extract zoom factor from focal length string for sorting
    private static func extractZoomFactor(from focalLength: String) -> Double {
        // Extract number before 'x' (e.g., "0.5x" -> 0.5, "2x" -> 2.0)
        let components = focalLength.components(separatedBy: "x")
        if let first = components.first, let value = Double(first) {
            return value
        }
        return 1.0  // Default to 1x if can't parse
    }
    
    /// Get focal length estimate for a device
    private static func getFocalLength(for device: AVCaptureDevice) -> String {
        // Try to get actual focal length from device format
        if let format = device.activeFormat.supportedMaxPhotoDimensions.first {
            // Estimate based on zoom factors
            let minZoom = device.minAvailableVideoZoomFactor
            
            if minZoom <= 0.6 {
                return "0.5x (13mm)"
            } else if minZoom <= 0.8 {
                return "0.7x (18mm)"
            } else if minZoom <= 1.2 {
                return "1x (26mm)"
            } else if minZoom <= 1.8 {
                return "1.5x (35mm)"
            } else if minZoom <= 2.5 {
                return "2x (52mm)"
            } else if minZoom <= 3.5 {
                return "3x (77mm)"
            } else {
                return "\(Int(minZoom))x"
            }
        }
        
        // Fallback: Estimate based on device type
        switch device.deviceType {
        case .builtInUltraWideCamera:
            return "0.5x (13mm)"
        case .builtInWideAngleCamera:
            return "1x (26mm)"
        case .builtInTelephotoCamera:
            return "2x (52mm)"
        case .builtInTrueDepthCamera:
            return "1x (前置)"
        default:
            return "1x"
        }
    }
    
    /// Get display name for a device
    private static func getDisplayName(for device: AVCaptureDevice, position: AVCaptureDevice.Position, type: AVCaptureDevice.DeviceType) -> String {
        let positionPrefix = position == .back ? "后置" : "前置"
        
        switch type {
        case .builtInUltraWideCamera:
            return "\(positionPrefix) 超广角"
        case .builtInWideAngleCamera:
            return "\(positionPrefix) 广角"
        case .builtInTelephotoCamera:
            return "\(positionPrefix) 长焦"
        case .builtInDualCamera:
            return "\(positionPrefix) 双摄"
        case .builtInDualWideCamera:
            return "\(positionPrefix) 双广角"
        case .builtInTripleCamera:
            return "\(positionPrefix) 三摄"
        case .builtInTrueDepthCamera:
            return "\(positionPrefix) 原深感"
        default:
            return "\(positionPrefix) 摄像头"
        }
    }
}
