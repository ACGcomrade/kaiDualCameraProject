import Foundation

/// Camera mode for switching between different camera configurations
enum CameraMode: String, CaseIterable {
    case frontOnly = "前置摄像头"
    case backOnly = "后置摄像头"
    case dual = "双摄像头"
    case picInPic = "画中画"
    
    var iconName: String {
        switch self {
        case .frontOnly:
            return "camera.fill"
        case .backOnly:
            return "camera"
        case .dual:
            return "camera.metering.multispot"
        case .picInPic:
            return "rectangle.inset.filled.and.person.filled"
        }
    }
    
    var displayName: String {
        return self.rawValue
    }
}
