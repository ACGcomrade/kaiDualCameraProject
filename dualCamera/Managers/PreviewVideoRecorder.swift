import UIKit
import AVFoundation
import Photos

/// Manages frame-by-frame preview capture for PIP video recording
/// Directly writes preview frames to video without saving temporary files
class PreviewVideoRecorder {
    
    static let shared = PreviewVideoRecorder()
    
    private init() {}
    
    // Recording state
    private var isRecording = false
    private var captureTimer: Timer?
    private let lock = NSLock() // Thread safety
    
    // Recording settings
    private var targetFPS: Int = 30
    private var targetResolution: CGSize = .zero
    
    // Video writer
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputURL: URL?
    private var frameCount: Int = 0
    private var sessionStarted = false
    
    /// Start recording preview frames directly to video
    func startRecording(fps: Int, resolution: CGSize) {
        guard !isRecording else {
            print("⚠️ PreviewVideoRecorder: Already recording")
            return
        }
        
        print("🎬 PreviewVideoRecorder: Starting direct video recording at \(fps)fps")
        
        targetFPS = fps
        targetResolution = resolution
        frameCount = 0
        sessionStarted = false
        
        // Create output URL
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview_video_\(UUID().uuidString).mov")
        self.outputURL = outputURL
        
        do {
            // Create video writer
            let writer = try AVAssetWriter(url: outputURL, fileType: .mov)
            
            let videoWidth = Int(resolution.width)
            let videoHeight = Int(resolution.height)
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: videoWidth,
                AVVideoHeightKey: videoHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: videoWidth * videoHeight * 10,
                    AVVideoExpectedSourceFrameRateKey: fps,
                    AVVideoMaxKeyFrameIntervalKey: fps * 2,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel
                ]
            ]
            
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true
            
            let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: videoWidth,
                    kCVPixelBufferHeightKey as String: videoHeight
                ]
            )
            
            guard writer.canAdd(videoInput) else {
                throw NSError(domain: "PreviewVideoRecorder", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"])
            }
            
            writer.add(videoInput)
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)
            
            self.videoWriter = writer
            self.videoWriterInput = videoInput
            self.pixelBufferAdaptor = pixelBufferAdaptor
            
            isRecording = true
            print("✅ PreviewVideoRecorder: Video writer initialized")
            
            // Start capture timer on main thread
            let frameInterval = 1.0 / Double(fps)
            DispatchQueue.main.async { [weak self] in
                self?.captureTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
                    self?.captureFrame()
                }
            }
            
            print("✅ PreviewVideoRecorder: Recording started (interval: \(frameInterval)s)")
            
        } catch {
            print("❌ PreviewVideoRecorder: Failed to start recording: \(error)")
            isRecording = false
        }
    }
    
    /// Stop recording and return video URL
    func stopRecording(completion: @escaping (URL?, Error?) -> Void) {
        // Ensure we stop on main thread since timer is scheduled on main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.stopRecording(completion: completion)
            }
            return
        }
        
        guard isRecording else {
            print("⚠️ PreviewVideoRecorder: Not recording")
            completion(nil, NSError(domain: "PreviewVideoRecorder", code: 2,
                                    userInfo: [NSLocalizedDescriptionKey: "Not recording"]))
            return
        }
        
        print("🎬 PreviewVideoRecorder: Stopping recording...")
        
        isRecording = false
        captureTimer?.invalidate()
        captureTimer = nil
        
        let capturedFrames = self.frameCount
        print("✅ PreviewVideoRecorder: Stopped. Captured \(capturedFrames) frames")
        
        // Finish writing on background queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self,
                  let videoInput = self.videoWriterInput,
                  let writer = self.videoWriter,
                  let outputURL = self.outputURL else {
                DispatchQueue.main.async {
                    completion(nil, NSError(domain: "PreviewVideoRecorder", code: 3,
                                            userInfo: [NSLocalizedDescriptionKey: "Writer not initialized"]))
                }
                return
            }
            
            videoInput.markAsFinished()
            writer.finishWriting {
                if writer.status == .completed {
                    print("✅ PreviewVideoRecorder: Video writing completed")
                    print("   Output: \(outputURL.path)")
                    
                    DispatchQueue.main.async {
                        completion(outputURL, nil)
                    }
                } else {
                    let error = writer.error ?? NSError(domain: "PreviewVideoRecorder", code: 4,
                                                         userInfo: [NSLocalizedDescriptionKey: "Video writing failed"])
                    print("❌ PreviewVideoRecorder: Video writing failed: \(error)")
                    DispatchQueue.main.async {
                        completion(nil, error)
                    }
                }
                
                // Clean up
                self.videoWriter = nil
                self.videoWriterInput = nil
                self.pixelBufferAdaptor = nil
            }
        }
    }
    
    /// Capture single frame from preview and write directly to video
    private func captureFrame() {
        guard isRecording else { return }
        
        // Ensure we're on main thread for view capture
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.captureFrame()
            }
            return
        }
        
        // Check if writer is ready
        guard let videoInput = videoWriterInput,
              let adaptor = pixelBufferAdaptor,
              let writer = videoWriter,
              writer.status == .writing,
              videoInput.isReadyForMoreMediaData else {
            return
        }
        
        // Capture preview screen
        guard let previewImage = PreviewCaptureManager.shared.capturePreviewFrame() else {
            print("⚠️ PreviewVideoRecorder: Failed to capture frame")
            return
        }
        
        // Resize to target resolution if needed
        let resizedImage = resizeImage(previewImage, to: targetResolution)
        
        // Convert to pixel buffer and write (on background queue)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self,
                  self.isRecording,
                  let pixelBuffer = self.pixelBuffer(from: resizedImage, size: self.targetResolution) else {
                return
            }
            
            // Get current frame index
            self.lock.lock()
            let currentFrame = self.frameCount
            self.frameCount += 1
            self.lock.unlock()
            
            // Calculate presentation time
            let presentationTime = CMTime(value: Int64(currentFrame), timescale: Int32(self.targetFPS))
            
            // Append pixel buffer
            if adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                if currentFrame % 30 == 0 {
                    print("📸 PreviewVideoRecorder: Wrote frame \(currentFrame)")
                }
            } else {
                print("⚠️ PreviewVideoRecorder: Failed to append frame \(currentFrame)")
            }
        }
    }
    
    /// Resize image to target resolution
    private func resizeImage(_ image: UIImage, to targetSize: CGSize) -> UIImage {
        guard targetSize.width > 0 && targetSize.height > 0 else {
            return image
        }
        
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    /// Convert UIImage to CVPixelBuffer using shared utility method
    private func pixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        // Resize image if needed
        let resizedImage = image.size == size ? image : resizeImage(image, to: size)
        return ImageUtils.pixelBuffer(from: resizedImage)
    }
    
    /// Clean up resources
    func cleanup() {
        lock.lock()
        defer { lock.unlock() }
        
        videoWriter = nil
        videoWriterInput = nil
        pixelBufferAdaptor = nil
        frameCount = 0
    }
}
