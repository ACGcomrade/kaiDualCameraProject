import Foundation
import UIKit

/// Manages switching between front and back camera previews
/// Handles tap gesture on PIP (small preview) to swap with main preview
class PreviewSwitcher {
    
    // Tracks which camera is currently in the main (large) preview
    private(set) var isBackCameraMain: Bool = true
    
    // Callback when preview positions are swapped
    var onSwap: ((Bool) -> Void)?
    
    init() {
        print("🔄 PreviewSwitcher: Initialized - back camera is main by default")
    }
    
    /// Toggle which camera is shown in the main preview
    func toggleMainCamera() {
        isBackCameraMain.toggle()
        print("🔄 PreviewSwitcher: Toggled - back camera is main: \(isBackCameraMain)")
        onSwap?(isBackCameraMain)
    }
    
    /// Reset to default (back camera as main)
    func reset() {
        isBackCameraMain = true
        print("🔄 PreviewSwitcher: Reset to default")
    }
    
    /// Get current main camera position
    func getMainCameraPosition() -> CameraPosition {
        return isBackCameraMain ? .back : .front
    }
    
    /// Get current PIP (small preview) camera position
    func getPIPCameraPosition() -> CameraPosition {
        return isBackCameraMain ? .front : .back
    }
}

enum CameraPosition {
    case back
    case front
    
    var displayName: String {
        switch self {
        case .back: return "Back Camera"
        case .front: return "Front Camera"
        }
    }
}
