// ============================================
// 备份：工作正常的画中画视频录制代码
// 日期：2025年12月14日
// 说明：这是基于合并两个摄像头pixel buffer的实现
// ============================================

/*
 画中画视频录制流程（当前能用的版本）
 
 1. 开始录制：
    - 创建 pipVideoWriter (AVAssetWriter) 用于合成后的视频
    - 创建 audioWriter 用于音频
    - 设置视频参数：分辨率、帧率、编码
 
 2. 录制过程（实时合成每一帧）：
    - 每当后置摄像头有新帧 → captureOutput 回调
    - 获取当前前置摄像头帧
    - 旋转两个帧（rotateSampleBufferIfNeeded）
    - 调用 PIPComposer.composePIPVideoFrame() 实时合成
    - 将合成帧写入视频文件
 
 3. 停止录制：
    - 完成视频写入
    - 合并视频和音频（VideoAudioMerger）
 
 关键方法：
 - startPIPVideoRecording()
 - stopPIPVideoRecording() / stopVideoRecording()
 - captureOutput() 中的 isPIPRecordingMode 分支
 - PIPComposer.composePIPVideoFrame()
*/

// ============================================
// CameraManager.swift 中的关键代码
// ============================================

// MARK: - PIP Video Recording Setup
func startPIPVideoRecording(completion: @escaping (URL?, Error?) -> Void) {
    print("🎥 CameraManager: startPIPVideoRecording called")
    
    guard !isRecording else {
        print("⚠️ CameraManager: Already recording")
        return
    }
    
    // Update UI immediately
    isRecording = true
    isPIPRecordingMode = true
    recordingDuration = 0
    recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
        self?.recordingDuration += 0.2
    }
    
    sessionQueue.async { [weak self] in
        guard let self = self else { return }
        
        // Create output URLs
        let pipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pip_\(UUID().uuidString)")
            .appendingPathExtension("mov")
        
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio_\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        
        self.pipOutputURL = pipURL
        self.audioOutputURL = audioURL
        
        do {
            var deviceOrientation = UIDevice.current.orientation
            if !deviceOrientation.isValidInterfaceOrientation {
                deviceOrientation = .portrait
            }
            
            // Create PIP video writer
            let pipWriter = try AVAssetWriter(url: pipURL, fileType: .mov)
            let dimensions = self.currentResolution.dimensions
            let fps = self.currentFrameRate.rawValue
            
            let isPortrait = deviceOrientation == .portrait || deviceOrientation == .portraitUpsideDown
            let videoWidth = isPortrait ? Int(dimensions.height) : Int(dimensions.width)
            let videoHeight = isPortrait ? Int(dimensions.width) : Int(dimensions.height)
            
            let pipVideoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: videoWidth,
                AVVideoHeightKey: videoHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: videoWidth * videoHeight * 8,
                    AVVideoExpectedSourceFrameRateKey: fps,
                    AVVideoMaxKeyFrameIntervalKey: fps * 2,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel
                ]
            ]
            
            let pipVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: pipVideoSettings)
            pipVideoInput.expectsMediaDataInRealTime = true
            pipVideoInput.transform = CGAffineTransform.identity
            
            if pipWriter.canAdd(pipVideoInput) {
                pipWriter.add(pipVideoInput)
                self.pipVideoWriter = pipWriter
                self.pipVideoWriterInput = pipVideoInput
            }
            
            // Create audio writer
            let audioWriter = try AVAssetWriter(url: audioURL, fileType: .m4a)
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = true
            
            if audioWriter.canAdd(audioInput) {
                audioWriter.add(audioInput)
                self.audioWriter = audioWriter
                self.audioWriterInput = audioInput
            }
            
            // Start writing
            pipWriter.startWriting()
            audioWriter.startWriting()
            
            // Reset flags
            self.recordingStartTime = nil
            self.pipWriterSessionStarted = false
            self.audioWriterSessionStarted = false
            self.recordingOrientation = deviceOrientation
            
            DispatchQueue.main.async {
                completion(pipURL, nil)
            }
            
        } catch {
            DispatchQueue.main.async {
                self.isRecording = false
                self.isPIPRecordingMode = false
                completion(nil, error)
            }
        }
    }
}

// MARK: - PIP Frame Composition (in captureOutput callback)
/*
在 captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) 中：

if isPIPRecordingMode {
    if let videoInput = pipVideoWriterInput,
       let writer = pipVideoWriter,
       writer.status == .writing,
       videoInput.isReadyForMoreMediaData,
       frontFrameCount >= 3 {
        
        // Start writer session
        if !pipWriterSessionStarted {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if writer.status == .writing {
                writer.startSession(atSourceTime: timestamp)
                recordingStartTime = timestamp
                pipWriterSessionStarted = true
            }
        }
        
        // Compose and append PIP frame
        if pipWriterSessionStarted && isRecording && writer.status == .writing {
            frameLock.lock()
            let frontFrame = lastFrontFrame
            frameLock.unlock()
            
            if let frontFrame = frontFrame,
               let backPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
               let frontPixelBuffer = CMSampleBufferGetImageBuffer(frontFrame) {
                
                // Rotate both buffers
                let rotatedBackBuffer = self.rotateSampleBufferIfNeeded(sampleBuffer, orientation: self.recordingOrientation, isFrontCamera: false)
                let rotatedFrontBuffer = self.rotateSampleBufferIfNeeded(frontFrame, orientation: self.recordingOrientation, isFrontCamera: true)
                
                if let rotatedBackPixel = CMSampleBufferGetImageBuffer(rotatedBackBuffer),
                   let rotatedFrontPixel = CMSampleBufferGetImageBuffer(rotatedFrontBuffer) {
                    
                    let isLandscape = self.recordingOrientation == .landscapeLeft || self.recordingOrientation == .landscapeRight
                    
                    // 核心：合成PIP帧
                    if let composedBuffer = PIPComposer.composePIPVideoFrame(
                        backBuffer: rotatedBackPixel,
                        frontBuffer: rotatedFrontPixel,
                        isLandscape: isLandscape,
                        ciContext: self.ciContext
                    ) {
                        // Create new sample buffer with composed pixel buffer
                        var timingInfo = CMSampleTimingInfo()
                        timingInfo.presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        timingInfo.duration = CMSampleBufferGetDuration(sampleBuffer)
                        timingInfo.decodeTimeStamp = CMSampleBufferGetDecodeTimeStamp(sampleBuffer)
                        
                        var formatDescription: CMFormatDescription?
                        CMVideoFormatDescriptionCreateForImageBuffer(
                            allocator: kCFAllocatorDefault,
                            imageBuffer: composedBuffer,
                            formatDescriptionOut: &formatDescription
                        )
                        
                        if let format = formatDescription {
                            var newSampleBuffer: CMSampleBuffer?
                            CMSampleBufferCreateReadyWithImageBuffer(
                                allocator: kCFAllocatorDefault,
                                imageBuffer: composedBuffer,
                                formatDescription: format,
                                sampleTiming: &timingInfo,
                                sampleBufferOut: &newSampleBuffer
                            )
                            
                            if let pipSample = newSampleBuffer,
                               videoInput.isReadyForMoreMediaData && writer.status == .writing {
                                let success = videoInput.append(pipSample)
                            }
                        }
                    }
                }
            }
        }
    }
}
*/

// ============================================
// PIPComposer.swift 中的关键方法
// ============================================

/*
static func composePIPVideoFrame(
    backBuffer: CVPixelBuffer,
    frontBuffer: CVPixelBuffer,
    isLandscape: Bool,
    ciContext: CIContext
) -> CVPixelBuffer? {
    
    let backImage = CIImage(cvPixelBuffer: backBuffer)
    let frontImage = CIImage(cvPixelBuffer: frontBuffer)
    
    let mainSize = backImage.extent.size
    
    // Calculate PIP rect (Core Image coordinate system - bottom-left origin)
    let pipRect = calculatePIPRect(
        mainSize: mainSize,
        isLandscape: isLandscape,
        forCoreImage: true  // 关键：使用Core Image坐标系
    )
    
    // Scale and position front camera image
    let scaleX = pipRect.width / frontImage.extent.width
    let scaleY = pipRect.height / frontImage.extent.height
    let scale = min(scaleX, scaleY)
    
    let scaledWidth = frontImage.extent.width * scale
    let scaledHeight = frontImage.extent.height * scale
    let offsetX = pipRect.minX + (pipRect.width - scaledWidth) / 2
    let offsetY = pipRect.minY + (pipRect.height - scaledHeight) / 2
    
    let scaledFrontImage = frontImage
        .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        .transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
    
    // Composite: front over back (no border for performance)
    let compositedImage = scaledFrontImage.composited(over: backImage)
    
    // Render to new pixel buffer
    var outputBuffer: CVPixelBuffer?
    let width = CVPixelBufferGetWidth(backBuffer)
    let height = CVPixelBufferGetHeight(backBuffer)
    
    let attributes: [CFString: Any] = [
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
    ]
    
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        attributes as CFDictionary,
        &outputBuffer
    )
    
    guard status == kCVReturnSuccess, let buffer = outputBuffer else {
        return nil
    }
    
    ciContext.render(compositedImage, to: buffer)
    return buffer
}

private static func calculatePIPRect(mainSize: CGSize, isLandscape: Bool, forCoreImage: Bool = false) -> CGRect {
    let pipSizeRatio: CGFloat = 0.25
    let pipPadding: CGFloat = 20
    
    let pipWidth: CGFloat
    let pipHeight: CGFloat
    
    if isLandscape {
        pipWidth = mainSize.width * pipSizeRatio
        pipHeight = pipWidth * 9 / 16
    } else {
        pipWidth = mainSize.width * pipSizeRatio
        pipHeight = pipWidth * 4 / 3
    }
    
    // Position: top-right corner
    let x = mainSize.width - pipWidth - pipPadding
    // Core Image: bottom-left origin, so high Y = top
    let y = forCoreImage ? (mainSize.height - pipHeight - pipPadding) : pipPadding
    
    return CGRect(x: x, y: y, width: pipWidth, height: pipHeight)
}
*/

// ============================================
// 停止录制和音频合并
// ============================================

/*
func stopPIPVideoRecording(completion: @escaping (URL?, URL?, URL?) -> Void) {
    // Finish writers
    // Get pipOutputURL and audioOutputURL
    // Call VideoAudioMerger.mergeVideoWithAudio()
    // Return merged video URL
}
*/
