import Foundation
import AVFoundation

/// Video resolution presets
enum VideoResolution: String, CaseIterable {
    case resolution_4K = "4K (3840×2160)"
    case resolution_1080p = "1080p (1920×1080)"
    case resolution_720p = "720p (1280×720)"
    case resolution_480p = "480p (854×480)"
    
    var dimensions: CMVideoDimensions {
        switch self {
        case .resolution_4K:
            return CMVideoDimensions(width: 3840, height: 2160)
        case .resolution_1080p:
            return CMVideoDimensions(width: 1920, height: 1080)
        case .resolution_720p:
            return CMVideoDimensions(width: 1280, height: 720)
        case .resolution_480p:
            return CMVideoDimensions(width: 854, height: 480)
        }
    }
    
    var displayName: String {
        return self.rawValue
    }
}

/// Frame rate presets
enum FrameRate: Int, CaseIterable {
    case fps_24 = 24
    case fps_30 = 30
    case fps_60 = 60
    case fps_120 = 120
    
    var displayName: String {
        return "\(self.rawValue) FPS"
    }
}
