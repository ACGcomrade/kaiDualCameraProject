import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    @ObservedObject var viewModel: CameraViewModel
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Remove existing sublayers
        uiView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        
        guard let session = viewModel.cameraManager.session else { return }
        
        // Create preview layer for the back camera
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = uiView.bounds
        
        // Add the layer
        uiView.layer.addSublayer(previewLayer)
        
        // Layout sublayers when bounds change
        DispatchQueue.main.async {
            previewLayer.frame = uiView.bounds
        }
    }
    
    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        uiView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
    }
}

// MARK: - 预览视图的占位符
struct CameraPreview_Previews: PreviewProvider {
    static var previews: some View {
        CameraPreview(viewModel: CameraViewModel())
            .previewLayout(.sizeThatFits)
    }
}
