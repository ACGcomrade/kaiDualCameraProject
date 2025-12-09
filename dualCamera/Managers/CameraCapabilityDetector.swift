import AVFoundation
import UIKit

/// Detects camera hardware capabilities (ultra-wide, telephoto, etc.)
class CameraCapabilityDetector {
    
    struct ZoomCapabilities {
        let minZoom: CGFloat
        let maxZoom: CGFloat
        let hasUltraWide: Bool  // 0.5x or wider
        let hasTelephoto: Bool  // 2x or more
        let defaultZoom: CGFloat
        
        var description: String {
            var features: [String] = []
            if hasUltraWide { features.append("Ultra-wide (0.5x)") }
            if hasTelephoto { features.append("Telephoto (2x+)") }
            return "Zoom: \(minZoom)x - \(maxZoom)x" + (features.isEmpty ? "" : " | \(features.joined(separator: ", "))")
        }
    }
    
    /// Detect zoom capabilities for back camera
    static func detectBackCameraZoomCapabilities() -> ZoomCapabilities {
        print("🔍 CameraCapabilityDetector: Detecting back camera capabilities...")
        
        // Use ONLY wide angle camera for multi-cam compatibility with front camera
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("❌ CameraCapabilityDetector: No back camera found")
            return ZoomCapabilities(minZoom: 1.0, maxZoom: 5.0, hasUltraWide: false, hasTelephoto: false, defaultZoom: 1.0)
        }
        
        let minZoom = device.minAvailableVideoZoomFactor
        let maxZoom = min(device.maxAvailableVideoZoomFactor, 10.0) // Cap at 10x for usability
        
        print("   Device: \(device.localizedName)")
        print("   Device type: \(device.deviceType.rawValue)")
        print("   Min zoom: \(minZoom)x")
        print("   Max zoom: \(maxZoom)x")
        
        // Check for ultra-wide (typically 0.5x on iPhone 11+)
        let hasUltraWide = minZoom <= 0.6
        
        // Check for telephoto (typically 2x or more)
        let hasTelephoto = maxZoom >= 2.0
        
        // Default zoom is 1.0x (standard wide angle view)
        let defaultZoom: CGFloat = 1.0
        
        if hasUltraWide {
            print("   ✅ Ultra-wide zoom available (0.5x)")
        }
        if hasTelephoto {
            print("   ✅ Telephoto capability detected")
        }
        
        let capabilities = ZoomCapabilities(
            minZoom: minZoom,
            maxZoom: maxZoom,
            hasUltraWide: hasUltraWide,
            hasTelephoto: hasTelephoto,
            defaultZoom: defaultZoom
        )
        
        print("   Summary: \(capabilities.description)")
        
        return capabilities
    }
    
    /// Detect if device supports dual/multi-cam
    static func supportsMultiCam() -> Bool {
        if #available(iOS 13.0, *) {
            let supported = AVCaptureMultiCamSession.isMultiCamSupported
            print("🔍 CameraCapabilityDetector: Multi-cam support: \(supported ? "✅ Yes" : "❌ No")")
            return supported
        }
        return false
    }
    
    /// Get all available camera types
    static func getAvailableCameraTypes() -> [AVCaptureDevice.DeviceType] {
        var types: [AVCaptureDevice.DeviceType] = []
        
        // Check each camera type
        let allTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera,
            .builtInDualCamera,
            .builtInDualWideCamera,
            .builtInTripleCamera
        ]
        
        for type in allTypes {
            if let _ = AVCaptureDevice.default(type, for: .video, position: .back) {
                types.append(type)
                print("   ✅ Available: \(type.rawValue)")
            }
        }
        
        return types
    }
}
