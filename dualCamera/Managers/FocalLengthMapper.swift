import AVFoundation
import UIKit

/// Zoom factor display mapper
/// Since iOS doesn't provide actual focal length, we use zoom ratios relative to main camera (1x)
class FocalLengthMapper {
    
    struct CameraInfo {
        let device: AVCaptureDevice
        let baseZoomFactor: CGFloat  // What hardware zoom = "1x" display
        let minZoom: CGFloat
        let maxZoom: CGFloat
        
        // Convert hardware zoom to display zoom
        func displayZoom(for hardwareZoom: CGFloat) -> CGFloat {
            return hardwareZoom / baseZoomFactor
        }
    }
    
    /// Detect camera hardware and build zoom mapping
    static func detectCameraInfo(for device: AVCaptureDevice) -> CameraInfo {
        let deviceType = device.deviceType
        let minZoom = device.minAvailableVideoZoomFactor
        let maxZoom = min(device.maxAvailableVideoZoomFactor, 10.0)
        
        // Determine base zoom factor (what hardware zoom = "1x" display)
        var baseZoomFactor: CGFloat = 1.0
        
        print("📐 FocalLengthMapper: Analyzing camera")
        print("   Device type: \(deviceType.rawValue)")
        print("   Hardware zoom range: \(minZoom)x - \(maxZoom)x")
        
        switch deviceType {
        case .builtInUltraWideCamera:
            // Ultra-wide camera: hardware 1.0x = display 0.5x
            // So hardware 2.0x = display 1.0x (main camera equivalent)
            baseZoomFactor = 2.0
            print("   📐 Ultra-wide camera detected")
            print("   📐 Mapping: hardware 1.0x → display 0.5x")
            print("   📐 Mapping: hardware 2.0x → display 1.0x")
            
        case .builtInWideAngleCamera:
            // Wide angle is the reference: hardware 1.0x = display 1.0x
            baseZoomFactor = 1.0
            print("   📐 Wide angle camera (reference)")
            print("   📐 Mapping: hardware 1.0x → display 1.0x")
            
        case .builtInTelephotoCamera:
            // Telephoto: hardware 1.0x = display 2.0x or 3.0x
            // This is approximate, actual ratio depends on model
            baseZoomFactor = 0.5  // hardware 1.0x → display 2.0x
            print("   📐 Telephoto camera detected")
            print("   📐 Mapping: hardware 1.0x → display 2.0x (approximate)")
            
        default:
            // Unknown or virtual device
            baseZoomFactor = 1.0
            print("   📐 Unknown/Virtual device - using 1:1 mapping")
        }
        
        // Calculate display zoom range
        let minDisplayZoom = minZoom / baseZoomFactor
        let maxDisplayZoom = maxZoom / baseZoomFactor
        
        print("   Display zoom range: \(String(format: "%.1fx", minDisplayZoom)) - \(String(format: "%.1fx", maxDisplayZoom))")
        
        return CameraInfo(
            device: device,
            baseZoomFactor: baseZoomFactor,
            minZoom: minZoom,
            maxZoom: maxZoom
        )
    }
    
    /// Format zoom factor for display (relative to main camera = 1x)
    static func formatAsEquivalent(zoom: CGFloat, baseZoomFactor: CGFloat) -> String {
        // Convert hardware zoom to display zoom
        let displayZoom = zoom / baseZoomFactor
        
        // Format common zoom levels
        if abs(displayZoom - 0.5) < 0.05 {
            return "0.5x"
        } else if abs(displayZoom - 1.0) < 0.05 {
            return "1x"
        } else if abs(displayZoom - 2.0) < 0.05 {
            return "2x"
        } else if abs(displayZoom - 3.0) < 0.05 {
            return "3x"
        } else {
            return String(format: "%.1fx", displayZoom)
        }
    }
}
