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
            
            // Add swap icon
            let swapIcon = UIImageView(image: UIImage(systemName: "arrow.triangle.2.circlepath"))
            swapIcon.tintColor = .white.withAlphaComponent(0.8)
            swapIcon.contentMode = .scaleAspectFit
            swapIcon.backgroundColor = UIColor.black.withAlphaComponent(0.5)
            swapIcon.layer.cornerRadius = 12.5
            swapIcon.clipsToBounds = true
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
        
        override func layoutSubviews() {
            super.layoutSubviews()
            
            // Back camera always fills the screen
            backImageView?.frame = bounds
            
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
            
            // Store the latest frame WITHOUT rotation (save CPU!)
            latestBackImage = image
            
            DispatchQueue.main.async {
                // Display based on switcher state
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
            
            // Store the latest frame WITHOUT rotation (save CPU!)
            latestFrontImage = image
            
            DispatchQueue.main.async {
                // Display based on switcher state
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
        
        // Use GPU-accelerated layer transform instead of CPU image rotation
        private func updateImageViewTransform(_ imageView: UIImageView?, isFrontCamera: Bool) {
            guard let imageView = imageView else { return }
            
            let orientation = UIDevice.current.orientation
            var rotationAngle: CGFloat = 0
            
            if isFrontCamera {
                switch orientation {
                case .portrait:
                    rotationAngle = .pi / 2
                case .portraitUpsideDown:
                    rotationAngle = -.pi / 2
                case .landscapeLeft:
                    rotationAngle = .pi
                case .landscapeRight:
                    rotationAngle = 0
                default:
                    rotationAngle = .pi / 2
                }
            } else {
                switch orientation {
                case .portrait:
                    rotationAngle = .pi / 2
                case .portraitUpsideDown:
                    rotationAngle = -.pi / 2
                case .landscapeLeft:
                    rotationAngle = 0
                case .landscapeRight:
                    rotationAngle = .pi
                default:
                    rotationAngle = .pi / 2
                }
            }
            
            // GPU-accelerated transform (no CPU work!)
            imageView.transform = CGAffineTransform(rotationAngle: rotationAngle)
        }
        
        // 修复图像方向,使其与设备方向匹配
        private func fixImageOrientation(_ image: UIImage, isFrontCamera: Bool) -> UIImage {
            // 获取设备方向
            let orientation = UIDevice.current.orientation
            
            // 根据设备方向旋转图像
            var rotationAngle: CGFloat = 0
            
            if isFrontCamera {
                // 前置摄像头在横屏时保持原来的角度(不需要反转)
                switch orientation {
                case .portrait:
                    rotationAngle = .pi / 2  // 90度 - 竖屏
                case .portraitUpsideDown:
                    rotationAngle = -.pi / 2  // -90度 - 倒置
                case .landscapeLeft:
                    rotationAngle = .pi  // 180度
                case .landscapeRight:
                    rotationAngle = 0  // 0度
                default:
                    rotationAngle = .pi / 2  // 默认竖屏
                }
            } else {
                // 后置摄像头使用现有角度
                switch orientation {
                case .portrait:
                    rotationAngle = .pi / 2  // 90度 - 竖屏
                case .portraitUpsideDown:
                    rotationAngle = -.pi / 2  // -90度 - 倒置
                case .landscapeLeft:
                    rotationAngle = 0  // 0度
                case .landscapeRight:
                    rotationAngle = .pi  // 180度
                default:
                    rotationAngle = .pi / 2  // 默认竖屏
                }
            }
            
            // 旋转图像
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
        
        // Subscribe to frame updates from CameraManager
        let timer = Timer.publish(every: 1.0/30.0, on: .main, in: .common)
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
    }
    
    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        coordinator.backFrameSubscription?.cancel()
        coordinator.frontFrameSubscription?.cancel()
    }
}

#Preview {
    DualCameraPreview(viewModel: CameraViewModel())
}
