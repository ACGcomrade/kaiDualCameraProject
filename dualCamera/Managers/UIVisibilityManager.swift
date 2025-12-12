import SwiftUI
import Combine

/// Simple visibility manager - everything always visible
/// Only used to track state, no auto-hide functionality
class UIVisibilityManager: ObservableObject {
    
    @Published var isUIVisible: Bool = true {
        didSet {
            print("👁️ UIVisibilityManager: isUIVisible = \(isUIVisible)")
        }
    }
    
    @Published var isPreviewVisible: Bool = true {
        didSet {
            print("👁️ UIVisibilityManager: isPreviewVisible = \(isPreviewVisible)")
        }
    }
    
    init() {
        print("👁️ UIVisibilityManager: Initialized (always visible mode)")
    }
    
    /// Called when user interacts with the screen
    /// Shows UI (and would restart auto-hide timer if implemented)
    func userDidInteract() {
        print("👁️ UIVisibilityManager: userDidInteract() called")
        isUIVisible = true
        // Note: Auto-hide timer functionality is not implemented in current version
    }
    
}
