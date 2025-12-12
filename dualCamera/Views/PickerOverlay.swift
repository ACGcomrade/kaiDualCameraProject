import SwiftUI

/// Compact picker overlay for resolution and frame rate selection
struct PickerOverlay<T: Hashable & CaseIterable>: View where T: RawRepresentable, T.RawValue == String {
    let title: String
    let options: [T]
    @Binding var selection: T
    let onDismiss: () -> Void
    let displayName: (T) -> String
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            // Picker card
            VStack(spacing: 0) {
                // Title
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.8))
                
                // Picker
                Picker(title, selection: $selection) {
                    ForEach(options, id: \.self) { option in
                        Text(displayName(option))
                            .foregroundColor(.white)
                            .tag(option)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 180)
                .background(Color.black.opacity(0.9))
                
                // Confirm button
                Button(action: onDismiss) {
                    Text("确定")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                }
            }
            .frame(width: 280)
            .cornerRadius(16)
            .shadow(radius: 20)
        }
    }
}

/// Frame rate picker overlay
struct FrameRatePickerOverlay: View {
    let title: String
    let options: [FrameRate]
    @Binding var selection: FrameRate
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            // Picker card
            VStack(spacing: 0) {
                // Title
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.8))
                
                // Picker
                Picker(title, selection: $selection) {
                    ForEach(options, id: \.self) { option in
                        Text(option.displayName)
                            .foregroundColor(.white)
                            .tag(option)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 180)
                .background(Color.black.opacity(0.9))
                
                // Confirm button
                Button(action: onDismiss) {
                    Text("确定")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                }
            }
            .frame(width: 280)
            .cornerRadius(16)
            .shadow(radius: 20)
        }
    }
}

#Preview("Resolution Picker") {
    struct PreviewWrapper: View {
        @State private var selection = VideoResolution.resolution_1080p
        
        var body: some View {
            ZStack {
                Color.gray
                PickerOverlay(
                    title: "选择分辨率",
                    options: VideoResolution.allCases,
                    selection: $selection,
                    onDismiss: {},
                    displayName: { $0.displayName }
                )
            }
        }
    }
    
    return PreviewWrapper()
}

#Preview("Frame Rate Picker") {
    struct PreviewWrapper: View {
        @State private var selection = FrameRate.fps_30
        
        var body: some View {
            ZStack {
                Color.gray
                FrameRatePickerOverlay(
                    title: "选择帧率",
                    options: FrameRate.allCases,
                    selection: $selection,
                    onDismiss: {}
                )
            }
        }
    }
    
    return PreviewWrapper()
}
