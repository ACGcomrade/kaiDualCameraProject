import SwiftUI

/// Alert view for camera permission
struct CameraPermissionAlert: View {
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("相机权限未授权")
                .font(.headline)
            
            Text("请在设置中允许访问相机")
                .font(.subheadline)
                .multilineTextAlignment(.center)
            
            Button("打开设置") {
                onOpenSettings()
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            
            Button("取消") {
                onDismiss()
            }
            .foregroundColor(.gray)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(15)
        .shadow(radius: 10)
    }
}

/// Top banner notification (auto-dismiss after 1 second)
struct SaveStatusAlert: View {
    let status: String
    let onDismiss: () -> Void
    
    var isSuccess: Bool {
        status.contains("success")
    }
    
    @State private var offset: CGFloat = -200
    
    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(isSuccess ? .green : .orange)
                
                Text(status)
                    .font(.body)
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.85))
            .cornerRadius(12)
            .shadow(radius: 10)
            .padding(.horizontal, 20)
            .offset(y: offset)
            .onAppear {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    offset = 0
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        offset = -200
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onDismiss()
                    }
                }
            }
            
            Spacer()
        }
    }
}

#Preview("Permission Alert") {
    ZStack {
        Color.black.opacity(0.3)
        CameraPermissionAlert(
            onOpenSettings: {},
            onDismiss: {}
        )
    }
}

#Preview("Save Status Alert") {
    ZStack {
        Color.black.opacity(0.3)
        SaveStatusAlert(
            status: "2 photo(s) saved successfully!",
            onDismiss: {}
        )
    }
}
