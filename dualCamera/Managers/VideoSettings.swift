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

/// Frame rate with dynamic value support
struct FrameRate: Hashable, Identifiable {
    let rawValue: Int
    var id: Int { rawValue }
    
    var displayName: String {
        return "\(rawValue) FPS"
    }
    
    init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    // Common presets
    static let fps_24 = FrameRate(rawValue: 24)
    static let fps_30 = FrameRate(rawValue: 30)
    static let fps_60 = FrameRate(rawValue: 60)
    static let fps_120 = FrameRate(rawValue: 120)
    
    /// Get frame rates supported by all cameras in multi-cam mode (dynamically generated)
    static func getSupportedFrameRates() -> [FrameRate] {
        // Get back and front cameras
        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("⚠️ Could not get cameras, using fallback 30 FPS")
            return [FrameRate(rawValue: 30)]
        }
        
        // Get the actual supported frame rate range from CURRENT active formats
        // This is more accurate than checking all formats
        let backFormat = backCamera.activeFormat
        let frontFormat = frontCamera.activeFormat
        
        var backMinFPS: Double = 1000
        var backMaxFPS: Double = 0
        for range in backFormat.videoSupportedFrameRateRanges {
            backMaxFPS = max(backMaxFPS, range.maxFrameRate)
            backMinFPS = min(backMinFPS, range.minFrameRate)
        }
        
        var frontMinFPS: Double = 1000
        var frontMaxFPS: Double = 0
        for range in frontFormat.videoSupportedFrameRateRanges {
            frontMaxFPS = max(frontMaxFPS, range.maxFrameRate)
            frontMinFPS = min(frontMinFPS, range.minFrameRate)
        }
        
        // Common range is the intersection
        let minCommonFPS = max(backMinFPS, frontMinFPS)
        let maxCommonFPS = min(backMaxFPS, frontMaxFPS)
        
        print("🎬 Back camera active format FPS range: \(backMinFPS) - \(backMaxFPS)")
        print("🎬 Front camera active format FPS range: \(frontMinFPS) - \(frontMaxFPS)")
        print("🎬 Detected common FPS range: \(minCommonFPS) - \(maxCommonFPS)")
        
        // Generate frame rate options
        var fpsValues: [Int] = []
        let minFPS = max(Int(ceil(minCommonFPS)), 15) // At least 15 FPS
        let maxFPS = Int(floor(maxCommonFPS))
        
        // Calculate interval based on range
        let range = maxFPS - minFPS
        let estimatedOptions = range / 5 + 1
        let interval = estimatedOptions > 10 ? 10 : 5
        
        print("🎬 FPS range: \(minFPS)-\(maxFPS), using interval: \(interval)")
        
        // Generate options with the calculated interval
        var currentFPS = minFPS
        while currentFPS <= maxFPS {
            fpsValues.append(currentFPS)
            currentFPS += interval
        }
        
        // Always ensure we have the max value
        if let last = fpsValues.last, last < maxFPS {
            fpsValues.append(maxFPS)
        }
        
        // Ensure common standard values are included
        for standardFPS in [24, 30] {
            if standardFPS >= minFPS && standardFPS <= maxFPS && !fpsValues.contains(standardFPS) {
                fpsValues.append(standardFPS)
            }
        }
        
        fpsValues.sort()
        
        print("🎬 Available FPS options: \(fpsValues)")
        
        return fpsValues.map { FrameRate(rawValue: $0) }
    }
}

extension VideoResolution {
    /// Get resolutions supported by all cameras in multi-cam mode
    static func getSupportedResolutions() -> [VideoResolution] {
        var supported: [VideoResolution] = []
        
        // Get back and front cameras
        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            return [.resolution_1080p] // Fallback
        }
        
        // Check each resolution
        for resolution in VideoResolution.allCases {
            let targetDimensions = resolution.dimensions
            var backSupports = false
            var frontSupports = false
            
            // Check back camera
            for format in backCamera.formats where format.isMultiCamSupported {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                if dimensions.width == targetDimensions.width && dimensions.height == targetDimensions.height {
                    backSupports = true
                    break
                }
            }
            
            // Check front camera  
            for format in frontCamera.formats where format.isMultiCamSupported {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                if dimensions.width == targetDimensions.width && dimensions.height == targetDimensions.height {
                    frontSupports = true
                    break
                }
            }
            
            // Only add if both cameras support it
            if backSupports && frontSupports {
                supported.append(resolution)
            }
        }
        
        return supported.isEmpty ? [.resolution_1080p] : supported
    }
}
