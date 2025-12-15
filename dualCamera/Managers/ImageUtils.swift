import UIKit
import AVFoundation
import CoreImage

/// Utility class for common image operations
/// Consolidates redundant code across the project for better performance and maintainability
class ImageUtils {
    
    // MARK: - Shared Resources
    
    /// Shared CIContext for optimal performance (expensive to create)
    static let sharedCIContext = CIContext(options: [
        .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
        .useSoftwareRenderer: false
    ])
    
    // MARK: - Pixel Buffer Operations
    
    /// Convert UIImage to CVPixelBuffer efficiently
    /// - Parameter image: Source image
    /// - Returns: CVPixelBuffer or nil if conversion fails
    static func pixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            return nil
        }
        
        // Flip coordinate system
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1.0, y: -1.0)
        
        if let cgImage = image.cgImage {
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        
        return buffer
    }
    
    // MARK: - Orientation Calculations
    
    /// Calculate rotation angle for camera based on device orientation
    /// - Parameters:
    ///   - orientation: Device orientation
    ///   - isFrontCamera: Whether this is for front camera
    /// - Returns: Rotation angle in radians
    static func rotationAngle(for orientation: UIDeviceOrientation, isFrontCamera: Bool) -> CGFloat {
        if isFrontCamera {
            switch orientation {
            case .portrait:
                return .pi / 2
            case .portraitUpsideDown:
                return -.pi / 2
            case .landscapeLeft:
                return .pi
            case .landscapeRight:
                return 0
            default:
                return .pi / 2
            }
        } else {
            switch orientation {
            case .portrait:
                return .pi / 2
            case .portraitUpsideDown:
                return -.pi / 2
            case .landscapeLeft:
                return 0
            case .landscapeRight:
                return .pi
            default:
                return .pi / 2
            }
        }
    }
    
    /// Get video transform for AVAssetWriter
    /// - Parameters:
    ///   - orientation: Recording orientation
    ///   - isFrontCamera: Whether this is for front camera
    /// - Returns: CGAffineTransform for video track
    static func videoTransform(for orientation: UIDeviceOrientation, isFrontCamera: Bool) -> CGAffineTransform {
        var transform = CGAffineTransform.identity
        
        if isFrontCamera {
            switch orientation {
            case .portrait:
                transform = CGAffineTransform(scaleX: -1, y: 1)
                transform = transform.rotated(by: .pi / 2)
            case .portraitUpsideDown:
                transform = CGAffineTransform(scaleX: -1, y: 1)
                transform = transform.rotated(by: -.pi / 2)
            case .landscapeLeft:
                transform = CGAffineTransform(scaleX: -1, y: 1)
            case .landscapeRight:
                transform = CGAffineTransform(scaleX: -1, y: 1)
                transform = transform.rotated(by: .pi)
            default:
                transform = CGAffineTransform(scaleX: -1, y: 1)
                transform = transform.rotated(by: .pi / 2)
            }
        } else {
            switch orientation {
            case .portrait:
                transform = CGAffineTransform(rotationAngle: .pi / 2)
            case .portraitUpsideDown:
                transform = CGAffineTransform(rotationAngle: -.pi / 2)
            case .landscapeLeft:
                transform = CGAffineTransform.identity
            case .landscapeRight:
                transform = CGAffineTransform(rotationAngle: .pi)
            default:
                transform = CGAffineTransform(rotationAngle: .pi / 2)
            }
        }
        
        return transform
    }
    
    // MARK: - Sample Buffer Operations
    
    /// Create a new sample buffer with transformed pixel buffer
    /// - Parameters:
    ///   - pixelBuffer: Transformed pixel buffer
    ///   - originalSampleBuffer: Original sample buffer for timing info
    /// - Returns: New sample buffer or nil
    static func createSampleBuffer(from pixelBuffer: CVPixelBuffer, 
                                   copying originalSampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        var newSampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo()
        timingInfo.presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(originalSampleBuffer)
        timingInfo.duration = CMSampleBufferGetDuration(originalSampleBuffer)
        timingInfo.decodeTimeStamp = CMSampleBufferGetDecodeTimeStamp(originalSampleBuffer)
        
        var formatDescription: CMFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        
        guard formatStatus == noErr, let format = formatDescription else {
            return nil
        }
        
        let sampleBufferStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: format,
            sampleTiming: &timingInfo,
            sampleBufferOut: &newSampleBuffer
        )
        
        guard sampleBufferStatus == noErr else {
            return nil
        }
        
        return newSampleBuffer
    }
}
