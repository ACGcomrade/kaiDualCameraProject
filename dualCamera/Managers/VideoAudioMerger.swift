import AVFoundation
import UIKit

/// Utility class to merge audio track into video files
class VideoAudioMerger {
    
    /// Merge audio file into video file
    /// - Parameters:
    ///   - videoURL: Source video file URL
    ///   - audioURL: Source audio file URL
    ///   - completion: Callback with merged video URL or error
    static func mergeAudioIntoVideo(
        videoURL: URL,
        audioURL: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        print("🎬 VideoAudioMerger: Starting merge")
        print("   Video: \(videoURL.lastPathComponent)")
        print("   Audio: \(audioURL.lastPathComponent)")
        
        // Check if files exist
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            print("❌ VideoAudioMerger: Video file not found")
            completion(.failure(MergerError.videoNotFound))
            return
        }
        
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            print("❌ VideoAudioMerger: Audio file not found")
            completion(.failure(MergerError.audioNotFound))
            return
        }
        
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        
        let composition = AVMutableComposition()
        
        // Add video track
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            print("❌ VideoAudioMerger: Failed to create video track")
            completion(.failure(MergerError.trackCreationFailed))
            return
        }
        
        // Add audio track
        guard let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            print("❌ VideoAudioMerger: Failed to create audio track")
            completion(.failure(MergerError.trackCreationFailed))
            return
        }
        
        // Use async API for iOS 15+, fallback for older versions
        if #available(iOS 15.0, *) {
            Task {
                await mergeTracksAsync(
                    videoAsset: videoAsset,
                    audioAsset: audioAsset,
                    videoTrack: videoTrack,
                    audioTrack: audioTrack,
                    composition: composition,
                    completion: completion
                )
            }
        } else {
            mergeTracksSync(
                videoAsset: videoAsset,
                audioAsset: audioAsset,
                videoTrack: videoTrack,
                audioTrack: audioTrack,
                composition: composition,
                completion: completion
            )
        }
    }
    
    // MARK: - iOS 15+ Async Implementation
    @available(iOS 15.0, *)
    private static func mergeTracksAsync(
        videoAsset: AVURLAsset,
        audioAsset: AVURLAsset,
        videoTrack: AVMutableCompositionTrack,
        audioTrack: AVMutableCompositionTrack,
        composition: AVMutableComposition,
        completion: @escaping (Result<URL, Error>) -> Void
    ) async {
        do {
            // Load tracks asynchronously
            let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
            let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
            let videoDuration = try await videoAsset.load(.duration)
            let audioDuration = try await audioAsset.load(.duration)
            
            // Insert video
            if let sourceVideoTrack = videoTracks.first {
                try videoTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: videoDuration),
                    of: sourceVideoTrack,
                    at: .zero
                )
                print("✅ VideoAudioMerger: Video track inserted")
            }
            
            // Insert audio
            if let sourceAudioTrack = audioTracks.first {
                try audioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: audioDuration),
                    of: sourceAudioTrack,
                    at: .zero
                )
                print("✅ VideoAudioMerger: Audio track inserted")
            }
            
            // Export
            await exportComposition(composition: composition, completion: completion)
            
        } catch {
            print("❌ VideoAudioMerger: Error loading/inserting tracks: \(error)")
            completion(.failure(error))
        }
    }
    
    // MARK: - iOS 14 and below Sync Implementation
    private static func mergeTracksSync(
        videoAsset: AVURLAsset,
        audioAsset: AVURLAsset,
        videoTrack: AVMutableCompositionTrack,
        audioTrack: AVMutableCompositionTrack,
        composition: AVMutableComposition,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        do {
            // Insert video (sync API - suppress deprecation for iOS 14 support)
            if #available(iOS 16.0, *) {
                // For iOS 16+, we should use async API but we're in sync context
                // Use old API with warning suppression
                #if compiler(>=5.7)
                #warning("Consider migrating to async loadTracks API for iOS 16+")
                #endif
            }
            if let sourceVideoTrack = videoAsset.tracks(withMediaType: .video).first {
                try videoTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: videoAsset.duration),
                    of: sourceVideoTrack,
                    at: .zero
                )
                print("✅ VideoAudioMerger: Video track inserted")
            }
            
            // Insert audio (sync API - suppress deprecation for iOS 14 support)
            if let sourceAudioTrack = audioAsset.tracks(withMediaType: .audio).first {
                try audioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: audioAsset.duration),
                    of: sourceAudioTrack,
                    at: .zero
                )
                print("✅ VideoAudioMerger: Audio track inserted")
            }
            
            // Export
            exportCompositionSync(composition: composition, completion: completion)
            
        } catch {
            print("❌ VideoAudioMerger: Error inserting tracks: \(error)")
            completion(.failure(error))
        }
    }
    
    // MARK: - Export (iOS 15+)
    @available(iOS 15.0, *)
    private static func exportComposition(
        composition: AVMutableComposition,
        completion: @escaping (Result<URL, Error>) -> Void
    ) async {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("merged_\(UUID().uuidString)")
            .appendingPathExtension("mov")
        
        // Remove existing file if any
        try? FileManager.default.removeItem(at: outputURL)
        
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            print("❌ VideoAudioMerger: Failed to create export session")
            completion(.failure(MergerError.exportSessionFailed))
            return
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.shouldOptimizeForNetworkUse = false
        
        print("🎬 VideoAudioMerger: Starting export...")
        
        do {
            // Use new async export API
            try await exportSession.export(to: outputURL, as: .mov)
            
            print("✅ VideoAudioMerger: Export completed")
            print("   Output: \(outputURL.lastPathComponent)")
            if let fileSize = try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int {
                print("   Size: \(fileSize) bytes (\(Double(fileSize) / 1024.0 / 1024.0) MB)")
            }
            completion(.success(outputURL))
        } catch {
            print("❌ VideoAudioMerger: Export failed: \(error.localizedDescription)")
            completion(.failure(error))
        }
    }
    
    // MARK: - Export (iOS 14 and below)
    private static func exportCompositionSync(
        composition: AVMutableComposition,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("merged_\(UUID().uuidString)")
            .appendingPathExtension("mov")
        
        // Remove existing file if any
        try? FileManager.default.removeItem(at: outputURL)
        
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            print("❌ VideoAudioMerger: Failed to create export session")
            completion(.failure(MergerError.exportSessionFailed))
            return
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.shouldOptimizeForNetworkUse = false
        
        print("🎬 VideoAudioMerger: Starting export...")
        
        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                print("✅ VideoAudioMerger: Export completed")
                print("   Output: \(outputURL.lastPathComponent)")
                if let fileSize = try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int {
                    print("   Size: \(fileSize) bytes (\(Double(fileSize) / 1024.0 / 1024.0) MB)")
                }
                completion(.success(outputURL))
                
            case .failed:
                print("❌ VideoAudioMerger: Export failed: \(exportSession.error?.localizedDescription ?? "unknown")")
                completion(.failure(exportSession.error ?? MergerError.exportFailed))
                
            case .cancelled:
                print("⚠️ VideoAudioMerger: Export cancelled")
                completion(.failure(MergerError.exportCancelled))
                
            default:
                print("⚠️ VideoAudioMerger: Export status: \(exportSession.status.rawValue)")
                completion(.failure(MergerError.exportFailed))
            }
        }
    }
    
    enum MergerError: LocalizedError {
        case videoNotFound
        case audioNotFound
        case trackCreationFailed
        case exportSessionFailed
        case exportFailed
        case exportCancelled
        
        var errorDescription: String? {
            switch self {
            case .videoNotFound: return "Video file not found"
            case .audioNotFound: return "Audio file not found"
            case .trackCreationFailed: return "Failed to create media track"
            case .exportSessionFailed: return "Failed to create export session"
            case .exportFailed: return "Export failed"
            case .exportCancelled: return "Export cancelled"
            }
        }
    }
}
