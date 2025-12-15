import Foundation

/// Enum to represent the current capture mode (photo or video)
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
    
    var fullDisplayName: String {
        switch self {
        case .photo: return "Photo Mode"
        case .video: return "Video Mode"
        }
    }
}
