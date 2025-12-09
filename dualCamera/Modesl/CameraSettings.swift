import Foundation
import AVFoundation
import Combine

enum VideoFrameRate: Int, CaseIterable, Identifiable {
    case fps24 = 24
    case fps30 = 30
    case fps60 = 60
    case fps120 = 120
    case fps240 = 240
    
    var id: Int { rawValue }
    
    var displayName: String {
        "\(rawValue) FPS"
    }
}

class CameraSettings: ObservableObject {
    @Published var backCameraFrameRate: VideoFrameRate = .fps30
    @Published var frontCameraFrameRate: VideoFrameRate = .fps30
    
    static let shared = CameraSettings()
    
    private init() {}
}
