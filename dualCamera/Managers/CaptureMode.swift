import Foundation

/// Enum to represent the current capture mode
enum CaptureMode {
    case photo
    case video
    
    var displayName: String {
        switch self {
        case .photo: return "Photo"
        case .video: return "Video"
        }
    }
    
    var icon: String {
        switch self {
        case .photo: return "camera.fill"
        case .video: return "video.fill"
        }
    }
}
