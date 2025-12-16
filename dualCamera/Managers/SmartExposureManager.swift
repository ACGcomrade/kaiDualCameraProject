import AVFoundation
import Vision
import UIKit

/// Smart exposure and focus manager with face detection and scene analysis
class SmartExposureManager {
    
    // MARK: - Properties
    private var faceDetectionRequest: VNDetectFaceRectanglesRequest?
    private var sequenceHandler = VNSequenceRequestHandler()
    
    // Exposure compensation values - start neutral, adjust dynamically
    private let frontCameraExposureBias: Float = 0.5  // Moderate brightness for front camera
    private let backCameraExposureBias: Float = 0.1   // Minimal initial boost for back camera
    
    // ISO ranges - prioritize image quality over extreme low-light
    private let minISO: Float = 50
    private let maxBackISO: Float = 600   // Lower max ISO for back camera (better lens)
    private let maxFrontISO: Float = 900  // Slightly higher for front (smaller sensor)
    
    // Adjustment thresholds
    private let brightnessChangeThreshold: Float = 0.08  // Only adjust if brightness changes >8%
    
    // Frame counter for timing
    private var lastAdjustmentFrame: [String: Int] = [:]
    
    init() {
        setupFaceDetection()
    }
    
    // MARK: - Setup
    private func setupFaceDetection() {
        faceDetectionRequest = VNDetectFaceRectanglesRequest()
        faceDetectionRequest?.revision = VNDetectFaceRectanglesRequestRevision3
    }
    
    // MARK: - Smart Camera Configuration
    /// Configure camera with intelligent exposure and focus settings
    func configureCamera(_ device: AVCaptureDevice, isFrontCamera: Bool) {
        do {
            try device.lockForConfiguration()
            
            // Enable continuous auto focus for better tracking
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
                print("✅ SmartExposure: Continuous auto focus enabled")
            }
            
            // Enable continuous auto exposure - this is key for automatic adjustment
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
                print("✅ SmartExposure: Continuous auto exposure enabled")
            }
            
            // Start with minimal exposure bias, let camera auto-adjust for best quality
            let initialBias: Float = isFrontCamera ? 0.3 : 0.0
            if device.minExposureTargetBias...device.maxExposureTargetBias ~= initialBias {
                device.setExposureTargetBias(initialBias, completionHandler: nil)
                print("✅ SmartExposure: Initial exposure bias set to \(initialBias) for \(isFrontCamera ? "front" : "back") camera")
            }
            
            // Enable subject area change monitoring for auto focus/exposure
            if device.isSubjectAreaChangeMonitoringEnabled != true {
                device.isSubjectAreaChangeMonitoringEnabled = true
                print("✅ SmartExposure: Subject area monitoring enabled")
            }
            
            // Use automatic ISO adjustment - let system handle it initially
            if device.isExposureModeSupported(.continuousAutoExposure) {
                // System will auto-adjust ISO
                print("✅ SmartExposure: Using automatic ISO adjustment")
            }
            
            // Enable auto white balance
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
                print("✅ SmartExposure: Continuous auto white balance enabled")
            }
            
            device.unlockForConfiguration()
            
        } catch {
            print("❌ SmartExposure: Failed to configure camera: \(error)")
        }
    }
    
    // MARK: - ISO Configuration
    // Note: Now using automatic ISO via continuousAutoExposure mode
    // Camera system will automatically manage ISO within device limits
    // This preserves image quality better than manual ISO adjustment
    // Removed manual ISO setting to avoid high ISO noise and quality degradation
    
    // MARK: - Face Detection
    /// Detect faces in sample buffer and return the best focus point
    func detectFaces(in sampleBuffer: CMSampleBuffer) -> CGPoint? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let request = faceDetectionRequest else {
            return nil
        }
        
        do {
            try sequenceHandler.perform([request], on: pixelBuffer, orientation: .up)
            
            guard let results = request.results, !results.isEmpty else {
                return nil
            }
            
            // Get the largest face (closest/most prominent)
            let sortedFaces = results.sorted { face1, face2 in
                let area1 = face1.boundingBox.width * face1.boundingBox.height
                let area2 = face2.boundingBox.width * face2.boundingBox.height
                return area1 > area2
            }
            
            if let primaryFace = sortedFaces.first {
                // Convert Vision coordinates (bottom-left origin) to AVFoundation (top-left)
                let visionRect = primaryFace.boundingBox
                let centerX = visionRect.midX
                let centerY = 1.0 - visionRect.midY  // Flip Y coordinate
                
                print("👤 SmartExposure: Face detected at (\(centerX), \(centerY))")
                return CGPoint(x: centerX, y: centerY)
            }
        } catch {
            print("⚠️ SmartExposure: Face detection error: \(error)")
        }
        
        return nil
    }
    
    // MARK: - Smart Focus and Exposure
    /// Apply smart focus and exposure to device based on scene analysis
    func applySmartFocusAndExposure(
        to device: AVCaptureDevice,
        sampleBuffer: CMSampleBuffer,
        isFrontCamera: Bool
    ) {
        // Priority 1: Detect faces
        if let faceFocusPoint = detectFaces(in: sampleBuffer) {
            setFocusAndExposure(on: device, at: faceFocusPoint, isFrontCamera: isFrontCamera, reason: "face detection")
            
            // Also adjust exposure for face
            adjustExposureForFace(device: device, isFrontCamera: isFrontCamera)
            return
        }
        
        // Priority 2: Analyze scene and adjust exposure dynamically
        analyzeSceneBrightness(sampleBuffer: sampleBuffer) { [weak self] brightness in
            guard let self = self else { return }
            
            // Adjust exposure based on comprehensive scene analysis
            self.adjustExposureForScene(
                device: device,
                brightness: brightness,
                isFrontCamera: isFrontCamera,
                sampleBuffer: sampleBuffer
            )
        }
    }
    
    // MARK: - Face Exposure Adjustment
    private func adjustExposureForFace(device: AVCaptureDevice, isFrontCamera: Bool) {
        do {
            try device.lockForConfiguration()
            
            // When face is detected, use gentle exposure to preserve detail
            let faceBias: Float = isFrontCamera ? 0.5 : 0.2
            if device.minExposureTargetBias...device.maxExposureTargetBias ~= faceBias {
                device.setExposureTargetBias(faceBias, completionHandler: nil)
                print("👤 SmartExposure: Face detected, adjusting exposure bias to \(faceBias)")
            }
            
            device.unlockForConfiguration()
        } catch {
            print("❌ SmartExposure: Failed to adjust face exposure: \(error)")
        }
    }
    
    // MARK: - Scene Exposure Adjustment
    private func adjustExposureForScene(
        device: AVCaptureDevice,
        brightness: Float,
        isFrontCamera: Bool,
        sampleBuffer: CMSampleBuffer
    ) {
        do {
            try device.lockForConfiguration()
            
            // Conservative brightness analysis - prioritize image quality
            let bias: Float
            
            if brightness < 0.15 {
                // Extremely dark scene - moderate boost (quality priority)
                bias = isFrontCamera ? 0.9 : 0.7
                print("🌑 SmartExposure: Very dark scene (\(String(format: "%.1f%%", brightness * 100))), boosting exposure to \(bias)")
            } else if brightness < 0.3 {
                // Dark scene - gentle increase
                bias = isFrontCamera ? 0.6 : 0.4
                print("🌙 SmartExposure: Dark scene (\(String(format: "%.1f%%", brightness * 100))), increasing exposure to \(bias)")
            } else if brightness < 0.45 {
                // Slightly dark - minimal boost
                bias = isFrontCamera ? 0.4 : 0.2
                print("🌥️ SmartExposure: Slightly dark scene (\(String(format: "%.1f%%", brightness * 100))), adjusting exposure to \(bias)")
            } else if brightness < 0.65 {
                // Optimal brightness range - minimal adjustment
                bias = isFrontCamera ? 0.2 : 0.0
                print("☁️ SmartExposure: Normal scene (\(String(format: "%.1f%%", brightness * 100))), maintaining exposure at \(bias)")
            } else if brightness < 0.8 {
                // Bright scene - slight reduction
                bias = isFrontCamera ? 0.0 : -0.2
                print("🌤️ SmartExposure: Bright scene (\(String(format: "%.1f%%", brightness * 100))), reducing exposure to \(bias)")
            } else {
                // Very bright - prevent overexposure
                bias = isFrontCamera ? -0.3 : -0.7
                print("☀️ SmartExposure: Very bright scene (\(String(format: "%.1f%%", brightness * 100))), reducing exposure to \(bias)")
            }
            
            // Apply exposure bias with bounds checking
            let clampedBias = max(device.minExposureTargetBias, min(bias, device.maxExposureTargetBias))
            device.setExposureTargetBias(clampedBias, completionHandler: nil)
            
            device.unlockForConfiguration()
            
        } catch {
            print("❌ SmartExposure: Failed to adjust scene exposure: \(error)")
        }
    }
    
    // MARK: - Focus and Exposure Point Setting
    private func setFocusAndExposure(
        on device: AVCaptureDevice,
        at point: CGPoint,
        isFrontCamera: Bool,
        reason: String
    ) {
        do {
            try device.lockForConfiguration()
            
            // Set focus point
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                print("🎯 SmartExposure: Focus point set to \(point) (\(reason))")
            }
            
            // Set exposure point
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                print("💡 SmartExposure: Exposure point set to \(point) (\(reason))")
            }
            
            device.unlockForConfiguration()
            
        } catch {
            print("❌ SmartExposure: Failed to set focus/exposure: \(error)")
        }
    }
    
    // MARK: - Scene Brightness Analysis
    private func analyzeSceneBrightness(
        sampleBuffer: CMSampleBuffer,
        completion: @escaping (Float) -> Void
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            completion(0.5)  // Default to mid-brightness
            return
        }
        
        // Lock pixel buffer
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        // Get buffer info
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            completion(0.5)
            return
        }
        
        // Sample center region (avoid edges which may have UI elements)
        let sampleWidth = width / 4
        let sampleHeight = height / 4
        let startX = (width - sampleWidth) / 2
        let startY = (height - sampleHeight) / 2
        
        var totalBrightness: Int64 = 0
        var sampleCount: Int64 = 0
        
        // Sample pixels (BGRA format)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        for y in stride(from: startY, to: startY + sampleHeight, by: 8) {
            for x in stride(from: startX, to: startX + sampleWidth, by: 8) {
                let offset = y * bytesPerRow + x * 4
                let b = Int64(buffer[offset])
                let g = Int64(buffer[offset + 1])
                let r = Int64(buffer[offset + 2])
                
                // Calculate luminance
                let luminance = (r * 299 + g * 587 + b * 114) / 1000
                totalBrightness += luminance
                sampleCount += 1
            }
        }
        
        // Calculate average brightness (0.0 to 1.0)
        let averageBrightness = Float(totalBrightness) / Float(sampleCount) / 255.0
        
        DispatchQueue.main.async {
            completion(averageBrightness)
        }
    }
    
    // MARK: - Manual Focus and Exposure
    /// Set manual focus and exposure at a specific point (for tap-to-focus)
    func setManualFocusAndExposure(
        on device: AVCaptureDevice,
        at point: CGPoint,
        isFrontCamera: Bool
    ) {
        setFocusAndExposure(on: device, at: point, isFrontCamera: isFrontCamera, reason: "manual tap")
    }
}
