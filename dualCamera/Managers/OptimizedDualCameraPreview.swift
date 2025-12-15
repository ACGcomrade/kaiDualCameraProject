import UIKit
import AVFoundation

/// GPU-accelerated dual camera preview using native AVCaptureVideoPreviewLayer
/// This eliminates CPU-intensive image rotation and uses GPU rendering
class OptimizedDualCameraPreview: UIView {
    
    // Preview layers (GPU-accelerated by AVFoundation)
    private var backPreviewLayer: AVCaptureVideoPreviewLayer?
    private var frontPreviewLayer: AVCaptureVideoPreviewLayer?
    private var frontContainerView: UIView?
    
    // Preview switcher
    let previewSwitcher = PreviewSwitcher()
    
    // Tap gesture for PIP
    private var tapGesture: UITapGestureRecognizer?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }
    
    private func setupLayers() {
        backgroundColor = .black
        
        // Setup front camera container (PIP)
        let frontContainer = UIView()
        frontContainer.layer.borderColor = UIColor.white.cgColor
        frontContainer.layer.borderWidth = 2
        frontContainer.layer.cornerRadius = 10
        frontContainer.clipsToBounds = true
        addSubview(frontContainer)
        frontContainerView = frontContainer
        
        // Add tap gesture for switching
        let tap = UITapGestureRecognizer(target: self, action: #selector(pipTapped))
        frontContainer.addGestureRecognizer(tap)
        frontContainer.isUserInteractionEnabled = true
        tapGesture = tap
        
        print("✅ OptimizedDualCameraPreview: Setup complete (GPU-accelerated)")
    }
    
    /// Connect to camera session (called once)
    func connectToSession(backSession: AVCaptureSession, frontSession: AVCaptureSession? = nil) {
        // Create back camera preview layer
        let backLayer = AVCaptureVideoPreviewLayer(session: backSession)
        backLayer.videoGravity = .resizeAspectFill
        backLayer.frame = bounds
        layer.insertSublayer(backLayer, at: 0)
        backPreviewLayer = backLayer
        
        print("✅ OptimizedDualCameraPreview: Back camera preview connected")
        
        // Note: For dual camera, we use single session with multiple outputs
        // Front camera frames are rendered separately
    }
    
    /// Update front camera preview frame (still uses image for PIP)
    func updateFrontFrame(_ image: UIImage?) {
        guard let image = image,
              let frontContainer = frontContainerView else {
            return
        }
        
        // Create image view if needed
        if frontContainer.subviews.isEmpty {
            let imageView = UIImageView(frame: frontContainer.bounds)
            imageView.contentMode = .scaleAspectFill
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            frontContainer.addSubview(imageView)
        }
        
        if let imageView = frontContainer.subviews.first as? UIImageView {
            DispatchQueue.main.async {
                imageView.image = image
            }
        }
    }
    
    @objc func pipTapped() {
        print("👆 OptimizedDualCameraPreview: PIP tapped - swapping previews")
        previewSwitcher.toggleMainCamera()
        
        // TODO: Implement preview swap with animation
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Update back preview layer
        backPreviewLayer?.frame = bounds
        
        // PIP layout
        let isLandscape = bounds.width > bounds.height
        
        let pipWidth: CGFloat = isLandscape ? 160 : 120
        let pipHeight: CGFloat = isLandscape ? 90 : 160
        let pipPadding: CGFloat = 20
        let safeTop = window?.safeAreaInsets.top ?? 0
        
        if isLandscape {
            frontContainerView?.frame = CGRect(
                x: bounds.width - pipWidth - pipPadding,
                y: safeTop + pipPadding,
                width: pipWidth,
                height: pipHeight
            )
        } else {
            frontContainerView?.frame = CGRect(
                x: bounds.width - pipWidth - pipPadding,
                y: safeTop + pipPadding,
                width: pipWidth,
                height: pipHeight
            )
        }
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        
        // Connect to PreviewCaptureManager when view is added to window
        if window != nil {
            PreviewCaptureManager.shared.setPreviewView(self)
            print("✅ OptimizedDualCameraPreview: Connected to PreviewCaptureManager")
        }
    }
}
