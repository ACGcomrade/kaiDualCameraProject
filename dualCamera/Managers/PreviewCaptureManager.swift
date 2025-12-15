import UIKit
import AVFoundation
import CoreImage

/// Manages capturing preview frames for PIP photo and video recording
/// This captures what the user sees on screen instead of raw camera output
class PreviewCaptureManager {
    
    // Singleton
    static let shared = PreviewCaptureManager()
    
    private init() {
        self.targetFrameRate = 30
    }
    
    // Reference to the preview view that displays camera output
    weak var previewView: UIView?
    
    // Frame rate control
    private var targetFrameRate: Int
    private var lastCaptureTime: CFTimeInterval = 0
    
    /// Frame interval calculated from target frame rate
    private var frameInterval: CFTimeInterval {
        return 1.0 / Double(targetFrameRate)
    }
    
    /// Set the preview view to capture from
    func setPreviewView(_ view: UIView) {
        self.previewView = view
        print("📸 PreviewCaptureManager: Preview view set, size: \(view.bounds.size)")
    }
    
    /// Update target frame rate for video recording
    func setTargetFrameRate(_ fps: Int) {
        self.targetFrameRate = fps
        print("📸 PreviewCaptureManager: Target frame rate set to \(fps) fps")
    }
    
    /// Capture current preview frame as UIImage
    /// This captures exactly what the user sees on screen (without UI overlays)
    func capturePreviewFrame() -> UIImage? {
        guard let view = previewView else {
            print("❌ PreviewCaptureManager: Preview view not set")
            return nil
        }
        
        print("📸 PreviewCaptureManager: Capturing preview frame from view with bounds: \(view.bounds)")
        
        // Ensure we're on main thread
        guard Thread.isMainThread else {
            print("⚠️ PreviewCaptureManager: Capture called off main thread, synchronizing...")
            var result: UIImage?
            DispatchQueue.main.sync {
                result = self.capturePreviewFrame()
            }
            return result
        }
        
        // Use UIGraphicsImageRenderer for high quality capture
        let renderer = UIGraphicsImageRenderer(size: view.bounds.size)
        let image = renderer.image { context in
            view.layer.render(in: context.cgContext)
        }
        
        print("✅ PreviewCaptureManager: Captured image size: \(image.size)")
        return image
    }
    
    /// Check if enough time has passed to capture next frame (for frame rate control)
    func shouldCaptureFrame() -> Bool {
        let currentTime = CACurrentMediaTime()
        let timeSinceLastCapture = currentTime - lastCaptureTime
        
        if timeSinceLastCapture >= frameInterval {
            lastCaptureTime = currentTime
            return true
        }
        return false
    }
    
    /// Reset frame timing
    func resetFrameTiming() {
        lastCaptureTime = 0
    }
    
    /// Capture preview as CVPixelBuffer for video recording
    func capturePreviewAsPixelBuffer() -> CVPixelBuffer? {
        guard let image = capturePreviewFrame() else {
            return nil
        }
        
        return pixelBuffer(from: image)
    }
    
    /// Convert UIImage to CVPixelBuffer using shared utility method
    private func pixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        return ImageUtils.pixelBuffer(from: image)
    }
}
