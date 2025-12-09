import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()
    
    var body: some View {
        ZStack {
            // Full screen dual camera preview
            DualCameraPreview(viewModel: viewModel)
                .ignoresSafeArea()
            
            // Zoom slider
            if viewModel.captureMode == .photo || viewModel.captureMode == .video {
                VStack {
                    Spacer()
                    
                    HStack {
                        ZoomSlider(
                            zoomFactor: $viewModel.zoomFactor,
                            minZoom: viewModel.cameraManager.minZoomFactor,
                            maxZoom: viewModel.cameraManager.maxZoomFactor
                        )
                        .onChange(of: viewModel.zoomFactor) { _, newValue in
                            viewModel.setZoom(newValue)
                        }
                        .padding(.leading, 20)
                        
                        Spacer()
                    }
                    .padding(.bottom, 150)
                }
            }
            
            // Recording indicator - FIXED to update properly
            if viewModel.isRecording {
                VStack {
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 20, height: 20)
                        
                        Text(timeString(from: viewModel.recordingDuration))
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(20)
                    .padding(.top, 60)
                    
                    Spacer()
                }
            }
            
            VStack {
                Spacer()
                
                // Captured images preview
                if viewModel.capturedBackImage != nil || viewModel.capturedFrontImage != nil {
                    CapturedPhotosPreview(
                        backImage: viewModel.capturedBackImage,
                        frontImage: viewModel.capturedFrontImage
                    )
                }
                
                // Camera control buttons (no icon rotation)
                CameraControlButtons(
                    captureMode: viewModel.captureMode,
                    isFlashOn: viewModel.isFlashOn,
                    isRecording: viewModel.isRecording,
                    lastCapturedImage: viewModel.lastCapturedImage,
                    onFlashToggle: { viewModel.toggleFlash() },
                    onCapture: { viewModel.captureOrRecord() },
                    onModeSwitch: { viewModel.switchMode() },
                    onOpenGallery: { viewModel.openGallery() }
                )
            }
            
            // Camera permission alert
            if viewModel.showSettingAlert {
                CameraPermissionAlert(
                    onOpenSettings: {
                        viewModel.openSettings()
                        viewModel.showSettingAlert = false
                    },
                    onDismiss: {
                        viewModel.showSettingAlert = false
                    }
                )
            }
            
            // Save status alert
            if viewModel.showSaveAlert, let status = viewModel.saveStatus {
                SaveStatusAlert(
                    status: status,
                    onDismiss: {
                        viewModel.showSaveAlert = false
                        viewModel.saveStatus = nil
                    }
                )
            }
        }
        .sheet(isPresented: $viewModel.showGallery) {
            PhotoGalleryView()
        }
    }
    
    // Helper function to format time
    private func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        let milliseconds = Int((timeInterval.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%01d", minutes, seconds, milliseconds)
    }
}

#Preview {
    ContentView()
}
