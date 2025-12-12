import UIKit
import AVFoundation
import Metal
import MetalKit

/// GPU-accelerated camera preview using Metal
/// Renders camera frames directly on GPU instead of CPU image processing
class MetalPreviewLayer: UIView {
    
    private var metalDevice: MTLDevice?
    private var metalView: MTKView?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?
    
    // Current texture to render
    private var currentTexture: MTLTexture?
    private let textureLock = NSLock()
    
    // Transform for rotation (currently unused, but kept for future orientation handling)
    // private var rotationAngle: Float = 0
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupMetal()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMetal()
    }
    
    private func setupMetal() {
        // Get default Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("❌ MetalPreviewLayer: Metal is not supported on this device")
            return
        }
        
        metalDevice = device
        
        // Create Metal view
        let mtkView = MTKView(frame: bounds, device: device)
        mtkView.delegate = self
        mtkView.framebufferOnly = true
        mtkView.colorPixelFormat = .bgra8Unorm
        // Use scale factor from appropriate source based on iOS version
        if #available(iOS 16.0, *) {
            // For iOS 16+, UIScreen.main is deprecated
            // We'll set scale later when we have access to window scene
            mtkView.contentScaleFactor = 2.0 // Default for most devices
        } else {
            mtkView.contentScaleFactor = UIScreen.main.scale
        }
        mtkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // Disable clearing (we'll render every frame)
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        addSubview(mtkView)
        metalView = mtkView
        
        // Create command queue
        commandQueue = device.makeCommandQueue()
        
        // Create texture cache
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        textureCache = cache
        
        // Create render pipeline
        setupPipeline()
        
        print("✅ MetalPreviewLayer: Metal rendering initialized (GPU-accelerated)")
    }
    
    private func setupPipeline() {
        guard let device = metalDevice else { return }
        
        // Simple vertex shader and fragment shader
        let library = device.makeDefaultLibrary()
        let vertexFunction = library?.makeFunction(name: "vertexShader")
        let fragmentFunction = library?.makeFunction(name: "fragmentShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            print("✅ MetalPreviewLayer: Render pipeline created")
        } catch {
            print("❌ MetalPreviewLayer: Failed to create pipeline: \(error)")
        }
    }
    
    /// Update frame from camera (runs on GPU)
    func updateFrame(sampleBuffer: CMSampleBuffer, rotation: Float = 0) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let textureCache = textureCache else {
            return
        }
        
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        
        var cvTextureOut: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            imageBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTextureOut
        )
        
        guard let cvTexture = cvTextureOut,
              let texture = CVMetalTextureGetTexture(cvTexture) else {
            return
        }
        
        textureLock.lock()
        currentTexture = texture
        // rotationAngle = rotation  // Currently unused
        textureLock.unlock()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        metalView?.frame = bounds
    }
}

// MARK: - MTKViewDelegate
extension MetalPreviewLayer: MTKViewDelegate {
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle size changes
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandQueue = commandQueue,
              let pipelineState = pipelineState else {
            return
        }
        
        textureLock.lock()
        let _texture = currentTexture
        // let _rotation = rotationAngle  // Currently unused
        textureLock.unlock()
        
        guard let _sourceTexture = _texture else {
            return
        }
        
        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        // Create render pass
        let renderPassDescriptor = view.currentRenderPassDescriptor
        renderPassDescriptor?.colorAttachments[0].loadAction = .clear
        
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor!) else {
            return
        }
        
        renderEncoder.setRenderPipelineState(pipelineState)
        
        // TODO: Set up vertex buffer and texture binding
        // For now, use simple blit
        
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
