import SwiftUI

/// Zoom slider control for back camera (no labels, clean design)
struct ZoomSlider: View {
    @Binding var zoomFactor: CGFloat
    let minZoom: CGFloat
    let maxZoom: CGFloat
    let isHorizontal: Bool
    
    var body: some View {
        if isHorizontal {
            // Horizontal layout for landscape mode - minimal design
            HStack {
                Slider(
                    value: $zoomFactor,
                    in: minZoom...maxZoom,
                    step: 0.1
                )
                .frame(width: 250)
                .accentColor(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        } else {
            // Vertical layout for portrait mode - minimal design
            VStack {
                Slider(
                    value: $zoomFactor,
                    in: minZoom...maxZoom,
                    step: 0.1
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 200, height: 40)
                .accentColor(.white)
            }
            .frame(height: 240)
            .padding(.vertical, 20)
            .padding(.horizontal, 12)
        }
    }
}

#Preview {
    ZStack {
        Color.black
        ZoomSlider(
            zoomFactor: .constant(2.0),
            minZoom: 0.5,
            maxZoom: 10.0,
            isHorizontal: false
        )
    }
}
