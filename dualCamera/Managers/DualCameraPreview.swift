import SwiftUI
import AVFoundation
import Combine

struct DualCameraPreview: UIViewRepresentable {
    @ObservedObject var viewModel: CameraViewModel
    
    class Coordinator: NSObject {
        var parent: DualCameraPreview
        var backFrameSubscription: AnyCancellable?
        var frontFrameSubscription: AnyCancellable?
        
        init(_ parent: DualCameraPreview) {
            self.parent = parent
            print("👤 DualCameraPreview.Coordinator: Initialized")
        }
        
        deinit {
            print("👤 DualCameraPreview.Coordinator: Deinitialized")
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class PreviewView: UIView {
        var backImageView: UIImageView?
        var frontContainerView: UIView?
        var frontImageView: UIImageView?
        
        // Preview switcher to manage which camera is main
        let previewSwitcher = PreviewSwitcher()
        
        // Store latest frames for swapping
        private var latestBackImage: UIImage?
        private var latestFrontImage: UIImage?
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            setupViews()
        }
        
        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setupViews()
        }
        
        private func setupViews() {
            backgroundColor = .black
            
            // Back camera view (full screen) - with correct orientation
            let backView = UIImageView()
            backView.contentMode = .scaleAspectFill
            backView.clipsToBounds = true
            backView.backgroundColor = .black
            addSubview(backView)
            backImageView = backView
            
            // Front camera PIP container
            let pipContainer = UIView()
            pipContainer.layer.cornerRadius = 12
            pipContainer.layer.masksToBounds = true
            pipContainer.layer.borderWidth = 2
            pipContainer.layer.borderColor = UIColor.white.cgColor
            pipContainer.backgroundColor = .black
            
            let frontView = UIImageView()
            frontView.contentMode = .scaleAspectFill
            frontView.clipsToBounds = true
            frontView.backgroundColor = .black
            pipContainer.addSubview(frontView)
            frontImageView = frontView
            
            addSubview(pipContainer)
            frontContainerView = pipContainer
            
            // Add swap icon (hidden but tap gesture still works)
            let swapIcon = UIImageView(image: UIImage(systemName: "arrow.triangle.2.circlepath"))
            swapIcon.tintColor = .white.withAlphaComponent(0.8)
            swapIcon.contentMode = .scaleAspectFit
            swapIcon.backgroundColor = UIColor.black.withAlphaComponent(0.5)
            swapIcon.layer.cornerRadius = 12.5
            swapIcon.clipsToBounds = true
            swapIcon.isHidden = true  // Hide the icon but keep tap gesture working
            pipContainer.addSubview(swapIcon)
            swapIcon.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                swapIcon.trailingAnchor.constraint(equalTo: pipContainer.trailingAnchor, constant: -5),
                swapIcon.topAnchor.constraint(equalTo: pipContainer.topAnchor, constant: 5),
                swapIcon.widthAnchor.constraint(equalToConstant: 25),
                swapIcon.heightAnchor.constraint(equalToConstant: 25)
            ])
            
            // Add tap gesture
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(pipTapped))
            pipContainer.addGestureRecognizer(tapGesture)
            pipContainer.isUserInteractionEnabled = true
            
            print("✅ DualCameraPreview: Views set up")
        }
        
        var currentCameraMode: CameraMode = .dual  // Will be set externally
        var currentFilter: FilterStyle = .none  // Current filter style
        
        override func didMoveToWindow() {
            super.didMoveToWindow()
            
            // Connect to PreviewCaptureManager when view is added to window
            if window != nil {
                PreviewCaptureManager.shared.setPreviewView(self)
                print("✅ DualCameraPreview.PreviewView: Connected to PreviewCaptureManager")
                
                // Listen for preview toggle notification
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(pipTapped),
                    name: NSNotification.Name("TogglePreviewCamera"),
                    object: nil
                )
            } else {
                // Remove observer when view is removed
                NotificationCenter.default.removeObserver(self, name: NSNotification.Name("TogglePreviewCamera"), object: nil)
            }
        }
        
        override func layoutSubviews() {
            super.layoutSubviews()
            
            // Back camera always fills the screen
            backImageView?.frame = bounds
            
            // Show PIP in dual mode and picInPic mode
            if currentCameraMode == .dual || currentCameraMode == .picInPic {
                frontContainerView?.isHidden = false
            } else {
                frontContainerView?.isHidden = true
                return
            }
            
            // Get device orientation to adjust PIP position
            let isLandscape = bounds.width > bounds.height
            
            // PIP layout - changes based on orientation
            let pipWidth: CGFloat
            let pipHeight: CGFloat
            
            if isLandscape {
                // 横屏: 宽度 > 高度 (16:9 比例)
                pipWidth = 160
                pipHeight = 90
            } else {
                // 竖屏: 高度 > 宽度 (3:4 比例)
                pipWidth = 120
                pipHeight = 160
            }
            
            let pipPadding: CGFloat = 20
            let safeTop = window?.safeAreaInsets.top ?? 0
            
            if isLandscape {
                // 横屏: PIP 在右上角
                frontContainerView?.frame = CGRect(
                    x: bounds.width - pipWidth - pipPadding,
                    y: safeTop + pipPadding,
                    width: pipWidth,
                    height: pipHeight
                )
            } else {
                // 竖屏: PIP 在右上角
                frontContainerView?.frame = CGRect(
                    x: bounds.width - pipWidth - pipPadding,
                    y: safeTop + pipPadding,
                    width: pipWidth,
                    height: pipHeight
                )
            }
            
            frontImageView?.frame = frontContainerView?.bounds ?? .zero
        }
        
        func updateBackFrame(_ image: UIImage?) {
            guard let image = image else { return }
            
            // Filter is already applied in CameraManager.imageFromSampleBuffer
            // Store the latest frame WITHOUT rotation (save CPU!)
            latestBackImage = image
            
            DispatchQueue.main.async {
                // In single camera mode, always show in main view
                if self.currentCameraMode == .backOnly {
                    self.backImageView?.image = image
                    self.updateImageViewTransform(self.backImageView, isFrontCamera: false)
                    return
                }
                
                // In PIP mode, display based on switcher state (allow switching)
                if self.currentCameraMode == .picInPic {
                    if self.previewSwitcher.isBackCameraMain {
                        // Back camera is main (large preview)
                        self.backImageView?.image = image
                        self.updateImageViewTransform(self.backImageView, isFrontCamera: false)
                    } else {
                        // Back camera is PIP (small preview)
                        self.frontImageView?.image = image
                        self.updateImageViewTransform(self.frontImageView, isFrontCamera: false)
                    }
                    return
                }
                
                // Display based on switcher state in dual mode
                if self.previewSwitcher.isBackCameraMain {
                    // Back camera is main (large preview)
                    // Use layer transform instead of CPU image rotation
                    self.backImageView?.image = image
                    self.updateImageViewTransform(self.backImageView, isFrontCamera: false)
                } else {
                    // Back camera is PIP (small preview)
                    self.frontImageView?.image = image
                    self.updateImageViewTransform(self.frontImageView, isFrontCamera: false)
                }
            }
        }
        
        func updateFrontFrame(_ image: UIImage?) {
            guard let image = image else { 
                return 
            }
            
            // Filter is already applied in CameraManager.imageFromSampleBuffer
            // Store the latest frame WITHOUT rotation (save CPU!)
            latestFrontImage = image
            
            DispatchQueue.main.async {
                // In single camera mode, always show in main view
                if self.currentCameraMode == .frontOnly {
                    self.backImageView?.image = image  // Use backImageView as main view
                    self.updateImageViewTransform(self.backImageView, isFrontCamera: true)
                    return
                }
                
                // In PIP mode, display based on switcher state (allow switching)
                if self.currentCameraMode == .picInPic {
                    if self.previewSwitcher.isBackCameraMain {
                        // Front camera is PIP (small preview)
                        self.frontImageView?.image = image
                        self.updateImageViewTransform(self.frontImageView, isFrontCamera: true)
                    } else {
                        // Front camera is main (large preview)
                        self.backImageView?.image = image
                        self.updateImageViewTransform(self.backImageView, isFrontCamera: true)
                    }
                    return
                }
                
                // Display based on switcher state in dual mode
                if self.previewSwitcher.isBackCameraMain {
                    // Front camera is PIP (small preview)
                    self.frontImageView?.image = image
                    self.updateImageViewTransform(self.frontImageView, isFrontCamera: true)
                } else {
                    // Front camera is main (large preview)
                    self.backImageView?.image = image
                    self.updateImageViewTransform(self.backImageView, isFrontCamera: true)
                }
            }
        }
        
        // Use GPU-accelerated layer transform with shared utility method
        private func updateImageViewTransform(_ imageView: UIImageView?, isFrontCamera: Bool) {
            guard let imageView = imageView else { return }
            
            let orientation = UIDevice.current.orientation
            let rotationAngle = ImageUtils.rotationAngle(for: orientation, isFrontCamera: isFrontCamera)
            
            // GPU-accelerated transform (no CPU work!)
            imageView.transform = CGAffineTransform(rotationAngle: rotationAngle)
        }
        
        // 修复图像方向,使其与设备方向匹配 (使用共享工具类)
        private func fixImageOrientation(_ image: UIImage, isFrontCamera: Bool) -> UIImage {
            let orientation = UIDevice.current.orientation
            let rotationAngle = ImageUtils.rotationAngle(for: orientation, isFrontCamera: isFrontCamera)
            return rotateImage(image, by: rotationAngle)
        }
        
        private func rotateImage(_ image: UIImage, by radians: CGFloat) -> UIImage {
            let rotatedSize = CGRect(origin: .zero, size: image.size)
                .applying(CGAffineTransform(rotationAngle: radians))
                .integral.size
            
            UIGraphicsBeginImageContextWithOptions(rotatedSize, false, image.scale)
            defer { UIGraphicsEndImageContext() }
            
            guard let context = UIGraphicsGetCurrentContext() else { return image }
            
            let origin = CGPoint(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
            context.translateBy(x: origin.x, y: origin.y)
            context.rotate(by: radians)
            
            image.draw(in: CGRect(
                x: -image.size.width / 2,
                y: -image.size.height / 2,
                width: image.size.width,
                height: image.size.height
            ))
            
            return UIGraphicsGetImageFromCurrentImageContext() ?? image
        }
        
        @objc func pipTapped() {
            print("👆 DualCameraPreview: PIP tapped - swapping previews")
            
            // Toggle the switcher
            previewSwitcher.toggleMainCamera()
            
            // Swap the images with animation
            UIView.transition(with: self, duration: 0.3, options: .transitionCrossDissolve) {
                self.refreshImages()
            }
        }
        
        // Refresh displayed images based on current switcher state
        func refreshImages() {
            if previewSwitcher.isBackCameraMain {
                // Back camera is main (large), front camera is PIP (small)
                backImageView?.image = latestBackImage
                frontImageView?.image = latestFrontImage
            } else {
                // Front camera is main (large), back camera is PIP (small)
                backImageView?.image = latestFrontImage
                frontImageView?.image = latestBackImage
            }
        }
    }
    
    func makeUIView(context: Context) -> PreviewView {
        print("🖼️ DualCameraPreview: makeUIView called")
        let view = PreviewView(frame: .zero)
        
        // Connect PreviewSwitcher to CameraManager for PIP video recording
        viewModel.cameraManager.previewSwitcher = view.previewSwitcher
        print("✅ DualCameraPreview: Connected PreviewSwitcher to CameraManager")
        
        // Set current camera mode and filter
        view.currentCameraMode = viewModel.cameraManager.cameraMode
        view.currentFilter = viewModel.cameraManager.currentFilter
        print("🖼️ DualCameraPreview: Camera mode set to \(viewModel.cameraManager.cameraMode.displayName)")
        print("🖼️ DualCameraPreview: Filter set to \(viewModel.cameraManager.currentFilter.displayName)")
        
        // Subscribe to frame updates from CameraManager
        // Use 60fps refresh rate for smooth preview (independent of recording frame rate)
        let timer = Timer.publish(every: 1.0/60.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                // Get latest frames and display them
                self.viewModel.cameraManager.getLatestFrames { backImage, frontImage in
                    view.updateBackFrame(backImage)
                    view.updateFrontFrame(frontImage)
                }
            }
        
        context.coordinator.backFrameSubscription = timer
        
        print("🖼️ DualCameraPreview: makeUIView complete")
        return view
    }
    
    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Update camera mode if it changed
        if uiView.currentCameraMode != viewModel.cameraManager.cameraMode {
            uiView.currentCameraMode = viewModel.cameraManager.cameraMode
            uiView.setNeedsLayout()  // Force layout update to show/hide PIP
        }
        
        // Update filter if it changed - force immediate frame refresh
        if uiView.currentFilter != viewModel.cameraManager.currentFilter {
            uiView.currentFilter = viewModel.cameraManager.currentFilter
            print("🎨 DualCameraPreview: Filter updated to \(viewModel.cameraManager.currentFilter.displayName)")
            
            // Force immediate frame update with new filter
            viewModel.cameraManager.getLatestFrames { backImage, frontImage in
                uiView.updateBackFrame(backImage)
                uiView.updateFrontFrame(frontImage)
            }
        }
    }
    
    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        coordinator.backFrameSubscription?.cancel()
        coordinator.frontFrameSubscription?.cancel()
    }
}

#Preview {
    DualCameraPreview(viewModel: CameraViewModel())
}
