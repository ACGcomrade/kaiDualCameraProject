import SwiftUI
import Photos
import PhotosUI
import AVKit

/// View that displays the user's photo library (photos AND videos)
struct PhotoGalleryView: View {
    @Environment(\.dismiss) var dismiss
    @State private var fetchedAssets: [(image: UIImage?, asset: PHAsset)] = []
    @State private var isLoading = true
    @State private var selectedAsset: PHAsset?
    @State private var showingVideoPlayer = false
    @State private var videoURL: URL?
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading {
                    ProgressView("Loading media...")
                        .foregroundColor(.white)
                } else if fetchedAssets.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No media yet")
                            .font(.title3)
                            .foregroundColor(.gray)
                        Text("Capture photos or videos to see them here")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 2) {
                            ForEach(fetchedAssets.indices, id: \.self) { index in
                                let item = fetchedAssets[index]
                                AssetThumbnail(asset: item.asset, thumbnail: item.image)
                                    .onTapGesture {
                                        handleAssetTap(item.asset)
                                    }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Recent Media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .sheet(isPresented: $showingVideoPlayer) {
            if let videoURL = videoURL {
                VideoPlayer(player: AVPlayer(url: videoURL))
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            fetchRecentMedia()
        }
    }
    
    private func handleAssetTap(_ asset: PHAsset) {
        if asset.mediaType == .video {
            // Play video
            loadVideo(asset)
        }
        // For photos, could show full screen view
    }
    
    private func loadVideo(_ asset: PHAsset) {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            guard let urlAsset = avAsset as? AVURLAsset else { return }
            DispatchQueue.main.async {
                self.videoURL = urlAsset.url
                self.showingVideoPlayer = true
            }
        }
    }
    
    private func fetchRecentMedia() {
        // Request photo library permission
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    isLoading = false
                }
                return
            }
            
            // Fetch recent photos AND videos
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = 50 // Fetch last 50 items
            
            // Fetch both photos and videos
            let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
            
            let imageManager = PHImageManager.default()
            let requestOptions = PHImageRequestOptions()
            requestOptions.isSynchronous = false
            requestOptions.deliveryMode = .highQualityFormat
            requestOptions.isNetworkAccessAllowed = true
            
            var assets: [(image: UIImage?, asset: PHAsset)] = []
            let group = DispatchGroup()
            
            fetchResult.enumerateObjects { asset, _, _ in
                group.enter()
                // Reduced thumbnail size for better performance and regular display
                let targetSize = CGSize(width: 150, height: 150)
                imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: requestOptions) { image, info in
                    assets.append((image: image, asset: asset))
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                self.fetchedAssets = assets
                self.isLoading = false
            }
        }
    }
}

/// Thumbnail view for an asset (photo or video)
struct AssetThumbnail: View {
    let asset: PHAsset
    let thumbnail: UIImage?
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image = thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
            } else {
                Color.gray
                    .aspectRatio(1, contentMode: .fill)
            }
            
            // Video indicator
            if asset.mediaType == .video {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                    Text(formatDuration(asset.duration))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.7))
                .cornerRadius(4)
                .padding(4)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    PhotoGalleryView()
}
