import UIKit
import CoreImage
import AVFoundation

/// Utility class to compose Picture-in-Picture images and video frames
class PIPComposer {
    
    // PIP configuration (matching preview layout)
    private static let pipSizeRatio: CGFloat = 0.25  // PIP is 25% of main view width
    private static let pipPadding: CGFloat = 20
    private static let pipCornerRadius: CGFloat = 16  // Larger corner radius for better look
    private static let pipBorderWidth: CGFloat = 1  // Very thin border (1 pixel)
    private static let pipShadowBlur: CGFloat = 8  // Softer shadow
    
    /// Compose a PIP image from back (main) and front (pip) camera images
    /// - Parameters:
    ///   - backImage: Main background image (back camera)
    ///   - frontImage: Small PIP overlay image (front camera)
    ///   - isLandscape: Whether the device is in landscape orientation
    ///   - ciContext: Reusable CIContext for performance
    /// - Returns: Composed UIImage with PIP overlay
    static func composePIPImage(
        backImage: UIImage,
        frontImage: UIImage,
        isLandscape: Bool,
        ciContext: CIContext
    ) -> UIImage? {
        
        print("📐 PIPComposer: Composing PIP photo (matching video method)")
        print("   Main image (back): \(backImage.size)")
        print("   PIP image (front): \(frontImage.size)")
        print("   Landscape: \(isLandscape)")
        
        // Convert UIImages to CIImages (same as video)
        guard let backCGImage = backImage.cgImage,
              let frontCGImage = frontImage.cgImage else {
            print("❌ Failed to get CGImage")
            return nil
        }
        
        let backCIImage = CIImage(cgImage: backCGImage)
        let frontCIImage = CIImage(cgImage: frontCGImage)
        
        let mainSize = backCIImage.extent.size
        
        // Calculate PIP rect (SAME as video - use Core Image coordinate system)
        let pipRect = calculatePIPRect(
            mainSize: mainSize,
            isLandscape: isLandscape,
            forCoreImage: true  // CRITICAL: Same as video
        )
        
        print("📐 PIP rect (Core Image coords): \(pipRect)")
        
        // Scale and position front camera image (SAME as video)
        let scaleX = pipRect.width / frontCIImage.extent.width
        let scaleY = pipRect.height / frontCIImage.extent.height
        let scale = min(scaleX, scaleY)  // Maintain aspect ratio
        
        // Calculate centered position within pipRect
        let scaledWidth = frontCIImage.extent.width * scale
        let scaledHeight = frontCIImage.extent.height * scale
        let offsetX = pipRect.minX + (pipRect.width - scaledWidth) / 2
        let offsetY = pipRect.minY + (pipRect.height - scaledHeight) / 2
        
        // Transform front image (SAME as video)
        let scaledFrontImage = frontCIImage
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
        
        // Create white border based on ACTUAL scaled image size (matching video implementation)
        let actualPipRect = CGRect(
            x: offsetX,
            y: offsetY,
            width: scaledWidth,
            height: scaledHeight
        )
        let borderRect = actualPipRect.insetBy(dx: -pipBorderWidth, dy: -pipBorderWidth)
        let whiteBorder = CIImage(color: CIColor.white).cropped(to: borderRect)
        
        // Composite layers: main → white border → scaled PIP (SAME as video)
        var compositedImage = whiteBorder.composited(over: backCIImage)
        compositedImage = scaledFrontImage.composited(over: compositedImage)
        
        // Render to CGImage (convert from Core Image to UIImage)
        guard let cgImage = ciContext.createCGImage(compositedImage, from: backCIImage.extent) else {
            print("❌ Failed to create CGImage")
            return nil
        }
        
        // Create UIImage - use .up orientation to avoid coordinate flipping
        let composedImage = UIImage(cgImage: cgImage, scale: backImage.scale, orientation: .up)
        
        print("✅ PIP photo composed successfully (using same method as video)")
        print("   Output size: \(composedImage.size)")
        print("   PIP should be at TOP-RIGHT (Core Image coords converted to UIImage)")
        
        return composedImage
    }
    
    /// Compose a PIP video frame from back and front camera pixel buffers
    /// - Parameters:
    ///   - backBuffer: Back camera pixel buffer
    ///   - frontBuffer: Front camera pixel buffer
    ///   - isLandscape: Whether the device is in landscape orientation
    ///   - isBackCameraMain: Whether back camera should be the main view (true) or PIP (false)
    ///   - ciContext: Reusable CIContext for performance
    ///   - filter: Optional filter to apply to the video
    /// - Returns: Composed CVPixelBuffer with PIP overlay
    static func composePIPVideoFrame(
        backBuffer: CVPixelBuffer,
        frontBuffer: CVPixelBuffer,
        isLandscape: Bool,
        isBackCameraMain: Bool,
        ciContext: CIContext,
        filter: FilterStyle = .none
    ) -> CVPixelBuffer? {
        
        var backImage = CIImage(cvPixelBuffer: backBuffer)
        var frontImage = CIImage(cvPixelBuffer: frontBuffer)
        
        // Apply filter to both camera feeds if not .none
        if filter != .none {
            backImage = filter.apply(to: backImage)
            frontImage = filter.apply(to: frontImage)
        }
        
        // Validate image extents
        guard !backImage.extent.isEmpty, !frontImage.extent.isEmpty else {
            print("❌ PIPComposer: Invalid image extent")
            return nil
        }
        
        // Determine which camera is main and which is PIP based on switch state
        let mainImage = isBackCameraMain ? backImage : frontImage
        let pipImage = isBackCameraMain ? frontImage : backImage
        
        let mainSize = mainImage.extent.size
        
        // Calculate PIP rect (use Core Image coordinate system)
        let pipRect = calculatePIPRect(
            mainSize: mainSize,
            isLandscape: isLandscape,
            forCoreImage: true
        )
        
        // Scale and position PIP camera image
        let scaleX = pipRect.width / pipImage.extent.width
        let scaleY = pipRect.height / pipImage.extent.height
        let scale = min(scaleX, scaleY)  // Maintain aspect ratio
        
        // Calculate centered position within pipRect
        let scaledWidth = pipImage.extent.width * scale
        let scaledHeight = pipImage.extent.height * scale
        let offsetX = pipRect.minX + (pipRect.width - scaledWidth) / 2
        let offsetY = pipRect.minY + (pipRect.height - scaledHeight) / 2
        
        // Transform and position PIP image
        var scaledPipImage = pipImage
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
        
        // Crop PIP image to PIP rect to ensure it doesn't overflow
        let pipCropRect = CGRect(
            x: max(pipRect.minX, scaledPipImage.extent.minX),
            y: max(pipRect.minY, scaledPipImage.extent.minY),
            width: min(pipRect.width, scaledPipImage.extent.width),
            height: min(pipRect.height, scaledPipImage.extent.height)
        )
        scaledPipImage = scaledPipImage.cropped(to: pipCropRect)
        
        // PERFORMANCE OPTIMIZED: Simple composition with minimal overhead
        // Use GPU-accelerated operations only
        
        // Create white background/border based on ACTUAL scaled PIP image size (not pipRect)
        // This ensures the border fits tightly around the actual image without extra white space
        let actualPipRect = CGRect(
            x: offsetX,
            y: offsetY,
            width: scaledWidth,
            height: scaledHeight
        )
        let borderRect = actualPipRect.insetBy(dx: -pipBorderWidth, dy: -pipBorderWidth)
        let whiteBorder = CIImage(color: CIColor.white).cropped(to: borderRect)
        
        // Composite layers: main → white border → scaled PIP
        var compositedImage = whiteBorder.composited(over: mainImage)
        compositedImage = scaledPipImage.composited(over: compositedImage)
        
        // Validate composited image
        guard !compositedImage.extent.isEmpty else {
            print("❌ PIPComposer: Composited image has invalid extent")
            return nil
        }
        
        // Render to new pixel buffer
        var outputBuffer: CVPixelBuffer?
        let width = CVPixelBufferGetWidth(backBuffer)
        let height = CVPixelBufferGetHeight(backBuffer)
        
        guard width > 0, height > 0 else {
            print("❌ PIPComposer: Invalid buffer dimensions: \(width)x\(height)")
            return nil
        }
        
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &outputBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = outputBuffer else {
            print("❌ PIPComposer: Failed to create output buffer, status: \(status)")
            return nil
        }
        
        // Render with error handling
        do {
            ciContext.render(compositedImage, to: buffer)
        } catch {
            print("❌ PIPComposer: Failed to render composited image: \(error)")
            return nil
        }
        
        return buffer
    }
    
    /// Calculate PIP rectangle position and size
    private static func calculatePIPRect(mainSize: CGSize, isLandscape: Bool, forCoreImage: Bool = false) -> CGRect {
        let pipWidth: CGFloat
        let pipHeight: CGFloat
        
        if isLandscape {
            // Landscape: 16:9 aspect ratio
            pipWidth = mainSize.width * pipSizeRatio
            pipHeight = pipWidth * 9 / 16
        } else {
            // Portrait: 3:4 aspect ratio (match preview)
            pipWidth = mainSize.width * pipSizeRatio
            pipHeight = pipWidth * 4 / 3
        }
        
        // Position: top-right corner with padding
        let x = mainSize.width - pipWidth - pipPadding
        // Core Image uses bottom-left origin, UIKit uses top-left
        let y = forCoreImage ? (mainSize.height - pipHeight - pipPadding) : pipPadding
        
        let rect = CGRect(x: x, y: y, width: pipWidth, height: pipHeight)
        
        print("📐 PIPComposer.calculatePIPRect:")
        print("   Main size: \(mainSize)")
        print("   PIP size: \(pipWidth) x \(pipHeight)")
        print("   Position: (\(x), \(y))")
        print("   Landscape: \(isLandscape), Core Image coords: \(forCoreImage)")
        print("   Result rect: \(rect)")
        
        return rect
    }
    
    /// Create a white border image
    private static func createBorderImage(rect: CGRect, cornerRadius: CGFloat) -> CIImage {
        // Create a white rounded rectangle
        UIGraphicsBeginImageContextWithOptions(rect.size, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else {
            return CIImage(color: .white).cropped(to: rect)
        }
        
        context.setFillColor(UIColor.white.cgColor)
        let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: rect.size), cornerRadius: cornerRadius)
        path.fill()
        
        if let cgImage = UIGraphicsGetImageFromCurrentImageContext()?.cgImage {
            return CIImage(cgImage: cgImage).transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
        }
        
        return CIImage(color: .white).cropped(to: rect)
    }
    
    /// Create a rounded mask image for clipping
    private static func createRoundedMaskImage(rect: CGRect, cornerRadius: CGFloat) -> CIImage {
        UIGraphicsBeginImageContextWithOptions(rect.size, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else {
            return CIImage(color: .white).cropped(to: rect)
        }
        
        context.setFillColor(UIColor.white.cgColor)
        let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: rect.size), cornerRadius: cornerRadius)
        path.fill()
        
        if let cgImage = UIGraphicsGetImageFromCurrentImageContext()?.cgImage {
            return CIImage(cgImage: cgImage).transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
        }
        
        return CIImage(color: .white).cropped(to: rect)
    }
    
    // MARK: - Testing
    
    /// Create a test PIP image with colored backgrounds to verify positioning
    /// RED background (main) with GREEN square (PIP) at top-right
    static func createTestPIPImage(isLandscape: Bool = false) -> UIImage? {
        print("\n🧪 === CREATING TEST PIP IMAGE ===")
        
        // Create test images with distinct colors
        let mainSize = CGSize(width: 1920, height: 1440)  // Portrait-like dimensions
        let pipTestSize = CGSize(width: 640, height: 480)
        
        // Create RED background image (main camera)
        let mainRenderer = UIGraphicsImageRenderer(size: mainSize)
        let mainImage = mainRenderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: mainSize))
            
            // Add text to identify
            let text = "MAIN (BACK)"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 60),
                .foregroundColor: UIColor.white
            ]
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (mainSize.width - textSize.width) / 2,
                y: (mainSize.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attributes)
        }
        
        // Create GREEN image (PIP camera)
        let pipRenderer = UIGraphicsImageRenderer(size: pipTestSize)
        let pipImage = pipRenderer.image { context in
            UIColor.green.setFill()
            context.fill(CGRect(origin: .zero, size: pipTestSize))
            
            // Add text to identify
            let text = "PIP (FRONT)"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 40),
                .foregroundColor: UIColor.white
            ]
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (pipTestSize.width - textSize.width) / 2,
                y: (pipTestSize.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attributes)
        }
        
        print("🧪 Test images created:")
        print("   Main (RED): \(mainImage.size)")
        print("   PIP (GREEN): \(pipImage.size)")
        print("   Expected: GREEN square at TOP-RIGHT corner with white border")
        
        // Compose using the actual PIP composer
        let ciContext = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        let composedImage = composePIPImage(
            backImage: mainImage,
            frontImage: pipImage,
            isLandscape: isLandscape,
            ciContext: ciContext
        )
        
        print("🧪 === TEST IMAGE COMPLETE ===\n")
        return composedImage
    }
    
    // MARK: - Helper Functions for Rounded Corners
    
    /// Creates a rounded rectangle CIImage with the specified color
    private static func createRoundedRectImage(rect: CGRect, cornerRadius: CGFloat, color: CIColor, ciContext: CIContext) -> CIImage {
        UIGraphicsBeginImageContextWithOptions(rect.size, false, 1.0)
        guard let context = UIGraphicsGetCurrentContext() else {
            return CIImage(color: color).cropped(to: rect)
        }
        
        // Flip coordinate system to match Core Image (Y-axis up)
        context.translateBy(x: 0, y: rect.size.height)
        context.scaleBy(x: 1.0, y: -1.0)
        
        context.setFillColor(UIColor(ciColor: color).cgColor)
        let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: rect.size), cornerRadius: cornerRadius)
        path.fill()
        
        guard let cgImage = context.makeImage() else {
            UIGraphicsEndImageContext()
            return CIImage(color: color).cropped(to: rect)
        }
        
        UIGraphicsEndImageContext()
        
        let ciImage = CIImage(cgImage: cgImage)
        return ciImage.transformed(by: CGAffineTransform(translationX: rect.origin.x, y: rect.origin.y))
    }
    
    /// Applies rounded corners to a CIImage by masking it with a rounded rectangle
    private static func applyRoundedCorners(to image: CIImage, rect: CGRect, cornerRadius: CGFloat, ciContext: CIContext) -> CIImage {
        // Crop the image to the target rect first to ensure we're working with the right portion
        let croppedImage = image.cropped(to: rect)
        
        // Translate the cropped image to origin for rendering
        let translatedImage = croppedImage.transformed(by: CGAffineTransform(translationX: -rect.origin.x, y: -rect.origin.y))
        
        // Render the input image to a CGImage
        guard let cgImage = ciContext.createCGImage(translatedImage, from: CGRect(origin: .zero, size: rect.size)) else {
            return croppedImage
        }
        
        // Create a new context with alpha channel
        UIGraphicsBeginImageContextWithOptions(rect.size, false, 1.0)
        guard let context = UIGraphicsGetCurrentContext() else {
            return croppedImage
        }
        
        // Flip coordinate system to match Core Image (Y-axis up)
        context.translateBy(x: 0, y: rect.size.height)
        context.scaleBy(x: 1.0, y: -1.0)
        
        // Create rounded rectangle path and clip
        let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: rect.size), cornerRadius: cornerRadius)
        path.addClip()
        
        // Draw the image within the clipped rounded rectangle
        context.draw(cgImage, in: CGRect(origin: .zero, size: rect.size))
        
        guard let roundedCGImage = context.makeImage() else {
            UIGraphicsEndImageContext()
            return croppedImage
        }
        
        UIGraphicsEndImageContext()
        
        let roundedCIImage = CIImage(cgImage: roundedCGImage)
        return roundedCIImage.transformed(by: CGAffineTransform(translationX: rect.origin.x, y: rect.origin.y))
    }
}
