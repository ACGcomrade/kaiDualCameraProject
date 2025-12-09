import SwiftUI

struct CameraSettingsView: View {
    @ObservedObject var settings: CameraSettings
    @Environment(\.dismiss) var dismiss
    @Binding var needsRestart: Bool
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 30) {
                        backCameraSection
                        
                        Divider()
                            .background(Color.white.opacity(0.3))
                            .padding(.horizontal)
                        
                        frontCameraSection
                        
                        restartNotice
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("相机设置 / Camera Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消 / Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("应用 / Apply") {
                        needsRestart = true
                        dismiss()
                    }
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
    
    private var backCameraSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "camera.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("后置摄像头")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Back Camera")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 15) {
                Text("帧率 / Frame Rate")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal)
                
                ForEach(VideoFrameRate.allCases) { frameRate in
                    SettingOptionRow(
                        title: frameRate.displayName,
                        isSelected: settings.backCameraFrameRate == frameRate
                    ) {
                        settings.backCameraFrameRate = frameRate
                    }
                }
            }
        }
    }
    
    private var frontCameraSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "camera.front.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("前置摄像头")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Front Camera")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 15) {
                Text("帧率 / Frame Rate")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal)
                
                ForEach(VideoFrameRate.allCases) { frameRate in
                    SettingOptionRow(
                        title: frameRate.displayName,
                        isSelected: settings.frontCameraFrameRate == frameRate
                    ) {
                        settings.frontCameraFrameRate = frameRate
                    }
                }
            }
        }
    }
    
    private var restartNotice: some View {
        VStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.title3)
                .foregroundColor(.yellow)
            
            Text("应用设置后相机将重新启动")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
            
            Text("Camera will restart after applying settings")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.top, 20)
    }
}

struct SettingOptionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundColor(.white)
                    .font(.body)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.blue.opacity(0.2) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
            .padding(.horizontal)
        }
    }
}

#Preview {
    CameraSettingsView(settings: CameraSettings.shared, needsRestart: .constant(false))
}
