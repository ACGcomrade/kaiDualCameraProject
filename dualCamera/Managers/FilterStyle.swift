import UIKit
import CoreImage

/// Filter style for camera preview
enum FilterStyle: Int, CaseIterable {
    case none = 0
    case blackAndWhite = 1
    case vintage = 2
    case neon = 3
    
    var displayName: String {
        switch self {
        case .none:
            return "原始"
        case .blackAndWhite:
            return "黑白"
        case .vintage:
            return "复古"
        case .neon:
            return "霓虹"
        }
    }
    
    // Shared CIContext for better performance (expensive to create)
    private static let sharedContext = CIContext(options: [
        .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
        .useSoftwareRenderer: false
    ])
    
    // Pre-cached filters for instant switching
    private static var cachedFilters: [FilterStyle: CIFilter] = [:]
    private static let cacheLock = NSLock() // Thread safety for cache access
    
    /// Apply filter to image using Core Image with optimized caching
    func apply(to image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else {
            return image
        }
        
        var outputImage: CIImage?
        
        switch self {
        case .none:
            return image
            
        case .blackAndWhite:
            // Complete black and white conversion
            let filter = CIFilter(name: "CIColorControls")!
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            filter.setValue(0.0, forKey: kCIInputSaturationKey) // Complete desaturation
            filter.setValue(1.1, forKey: kCIInputContrastKey)
            outputImage = filter.outputImage
            
        case .vintage:
            // More intense vintage effect
            let filter = CIFilter(name: "CISepiaTone")!
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            filter.setValue(1.0, forKey: kCIInputIntensityKey) // Maximum intensity
            outputImage = filter.outputImage
            
        case .neon:
            // White dreamy glow effect
            let filter = CIFilter(name: "CIBloom")!
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            filter.setValue(10.0, forKey: kCIInputRadiusKey)
            filter.setValue(0.8, forKey: kCIInputIntensityKey)
            outputImage = filter.outputImage
        }
        
        guard let finalOutputImage = outputImage,
              let cgImage = Self.sharedContext.createCGImage(finalOutputImage, from: finalOutputImage.extent) else {
            return image
        }
        
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    /// Apply filter to CIImage directly (more efficient for video preview)
    /// This is the MAIN method used during live preview - heavily optimized
    func apply(to ciImage: CIImage) -> CIImage {
        // Store original extent to ensure output has same dimensions
        let originalExtent = ciImage.extent
        
        switch self {
        case .none:
            return ciImage
            
        case .blackAndWhite:
            // Use CIColorControls to ensure complete black and white conversion
            Self.cacheLock.lock()
            let cachedFilter = Self.cachedFilters[.blackAndWhite]
            Self.cacheLock.unlock()
            
            if let cachedFilter = cachedFilter {
                cachedFilter.setValue(ciImage, forKey: kCIInputImageKey)
                if let output = cachedFilter.outputImage {
                    // Crop to original extent to prevent size changes
                    return output.cropped(to: originalExtent)
                }
                return ciImage
            } else {
                // First desaturate completely
                let filter = CIFilter(name: "CIColorControls")!
                filter.setValue(0.0, forKey: kCIInputSaturationKey) // Complete desaturation
                filter.setValue(1.1, forKey: kCIInputContrastKey) // Slightly increase contrast
                
                Self.cacheLock.lock()
                Self.cachedFilters[.blackAndWhite] = filter
                Self.cacheLock.unlock()
                
                filter.setValue(ciImage, forKey: kCIInputImageKey)
                if let output = filter.outputImage {
                    return output.cropped(to: originalExtent)
                }
                return ciImage
            }
            
        case .vintage:
            // More intense vintage effect with stronger sepia
            Self.cacheLock.lock()
            let cachedFilter = Self.cachedFilters[.vintage]
            Self.cacheLock.unlock()
            
            if let cachedFilter = cachedFilter {
                cachedFilter.setValue(ciImage, forKey: kCIInputImageKey)
                if let output = cachedFilter.outputImage {
                    return output.cropped(to: originalExtent)
                }
                return ciImage
            } else {
                let filter = CIFilter(name: "CISepiaTone")!
                filter.setValue(1.0, forKey: kCIInputIntensityKey) // Maximum intensity
                
                Self.cacheLock.lock()
                Self.cachedFilters[.vintage] = filter
                Self.cacheLock.unlock()
                
                filter.setValue(ciImage, forKey: kCIInputImageKey)
                if let output = filter.outputImage {
                    return output.cropped(to: originalExtent)
                }
                return ciImage
            }
            
        case .neon:
            // White dreamy glow effect - bloom filter for ethereal look
            Self.cacheLock.lock()
            let cachedFilter = Self.cachedFilters[.neon]
            Self.cacheLock.unlock()
            
            if let cachedFilter = cachedFilter {
                cachedFilter.setValue(ciImage, forKey: kCIInputImageKey)
                if let output = cachedFilter.outputImage {
                    return output.cropped(to: originalExtent)
                }
                return ciImage
            } else {
                // Use Bloom filter for white glowing bubbles effect
                let filter = CIFilter(name: "CIBloom")!
                filter.setValue(10.0, forKey: kCIInputRadiusKey) // Glow radius
                filter.setValue(0.8, forKey: kCIInputIntensityKey) // Strong glow
                
                Self.cacheLock.lock()
                Self.cachedFilters[.neon] = filter
                Self.cacheLock.unlock()
                
                filter.setValue(ciImage, forKey: kCIInputImageKey)
                if let output = filter.outputImage {
                    return output.cropped(to: originalExtent)
                }
                return ciImage
            }
        }
    }
}
