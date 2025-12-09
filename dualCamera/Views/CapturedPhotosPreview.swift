import SwiftUI

/// View that displays captured photo thumbnails
struct CapturedPhotosPreview: View {
    let backImage: UIImage?
    let frontImage: UIImage?
    
    var body: some View {
        HStack(spacing: 15) {
            // Back camera image
            if let backImage = backImage {
                VStack(spacing: 5) {
                    Image(uiImage: backImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white, lineWidth: 2)
                        )
                    Text("Back")
                        .font(.caption2)
                        .foregroundColor(.white)
                }
                .transition(.scale)
            }
            
            // Front camera image
            if let frontImage = frontImage {
                VStack(spacing: 5) {
                    Image(uiImage: frontImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white, lineWidth: 2)
                        )
                    Text("Front")
                        .font(.caption2)
                        .foregroundColor(.white)
                }
                .transition(.scale)
            }
        }
        .padding()
        .background(Color.black.opacity(0.5))
        .cornerRadius(15)
    }
}

#Preview {
    ZStack {
        Color.black
        CapturedPhotosPreview(
            backImage: UIImage(systemName: "photo"),
            frontImage: UIImage(systemName: "photo")
        )
    }
}
