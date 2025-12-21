import Foundation
import SwiftUI
import AVFoundation
import Combine
import Photos
import UIKit

enum FlashMode {
    case off      // 关闭
    case on       // 常亮(torch)
    case auto     // 拍照时屏幕闪光
    
    var displayName: String {
        switch self {
        case .off: return "Off"
        case .on: return "On"
        case .auto: return "Auto"
        }
    }
    
    var iconName: String {
        switch self {
        case .off: return "bolt.slash.fill"
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.automatic.fill"
        }
    }
    
    mutating func next() {
        switch self {
        case .off: self = .on
        case .on: self = .auto
        case .auto: self = .off
        }
    }
}

class CameraViewModel: ObservableObject {
    @Published var isPermissionGranted = false
    @Published var showSettingAlert = false
    @Published var capturedBackImage: UIImage? = nil
    @Published var capturedFrontImage: UIImage? = nil
    @Published var lastCapturedImage: UIImage? = nil  // For gallery button thumbnail
    @Published var flashMode: FlashMode = .off
    @Published var showScreenFlash = false  // For screen flash effect
    @Published var saveStatus: String? = nil
    @Published var showSaveAlert = false
    @Published var captureMode: CaptureMode = .photo
    @Published var isRecording = false
    @Published var zoomFactor: CGFloat = 1.0
    @Published var recordingDuration: TimeInterval = 0  // Track locally
    
    let cameraManager = CameraManager.shared
    let uiVisibilityManager = UIVisibilityManager()
    let performanceMonitor = PerformanceMonitor()
    let notificationManager = NotificationManager()  // Enabled for file save notifications
    private var cancellables = Set<AnyCancellable>()
    private var recordingTimer: Timer?
    
    // TEST MODE: Set to true to bypass camera and use fake frames
    private let enableTestMode = false
    
    init() {
        print("🔵 CameraViewModel: Initializing...")
        setupRecordingObserver()
        
        if enableTestMode {
            print("🧪 CameraViewModel: TEST MODE ENABLED")
            cameraManager.startTestMode()
            isPermissionGranted = true
        } else {
            print("🔵 CameraViewModel: Checking permissions...")
            Task { @MainActor in
                checkPermission()
            }
        }
        
        print("🔵 CameraViewModel: Initialization complete")
    }
    
    /// User touched screen - show UI and restart preview timer
    func handleUserInteraction() {
        print("📱 CameraViewModel: handleUserInteraction() called")
        
        // If camera preview is hidden, show it and restart session
        if !uiVisibilityManager.isPreviewVisible {
            print("📱 CameraViewModel: Camera preview was hidden, restoring...")
            uiVisibilityManager.isPreviewVisible = true
            cameraManager.setupSession()
        }
        
        // Show UI and restart timer (UI auto-hides after 3 seconds)
        uiVisibilityManager.userDidInteract()
    }
    
    /// Ensure camera is active and then execute the given action
    /// 这个方法会在执行任何需要camera的操作前先确保camera已启动
    func ensureCameraActiveAndExecute(action: @escaping () -> Void) {
        print("🔄 CameraViewModel: ensureCameraActiveAndExecute() called")
        print("🔄 CameraViewModel: isPreviewVisible = \(uiVisibilityManager.isPreviewVisible)")
        
        // If camera preview is hidden, restore it first
        if !uiVisibilityManager.isPreviewVisible {
            print("🔄 CameraViewModel: Camera preview hidden, restoring...")
            
            // 1. 恢复 preview 可见性和 camera 会话
            uiVisibilityManager.isPreviewVisible = true
            cameraManager.setupSession()
            
            // 2. 给 camera 一点时间启动，然后执行 action
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                print("🔄 CameraViewModel: Camera session restored, executing action now")
                action()
            }
        } else {
            // Camera is already running, execute action immediately
            print("🔄 CameraViewModel: Camera already active, executing action")
            action()
        }
    }
    
    /// Toggle camera session (called on double-tap) - Stop/Start camera feed
    func toggleCameraSession() {
        print("📱 CameraViewModel: toggleCameraSession() called")
        
        // Toggle the visibility state
        uiVisibilityManager.isPreviewVisible.toggle()
        
        // Actually stop/start the camera session
        if uiVisibilityManager.isPreviewVisible {
            // Start camera session
            print("📱 CameraViewModel: Starting camera session...")
            cameraManager.setupSession()
        } else {
            // Stop camera session
            print("📱 CameraViewModel: Stopping camera session...")
            cameraManager.stopSession()
        }
    }
    
    /// Resume camera session (force start without toggling UI state)
    func resumeCameraSession() {
        print("📱 CameraViewModel: resumeCameraSession() called")
        
        // Ensure preview is visible
        if !uiVisibilityManager.isPreviewVisible {
            uiVisibilityManager.isPreviewVisible = true
        }
        
        // Force start the camera session
        print("📱 CameraViewModel: Force starting camera session...")
        cameraManager.setupSession()
    }
    
    private func setupRecordingObserver() {
        // Observe recording duration from camera manager
        cameraManager.$recordingDuration
            .assign(to: &$recordingDuration)
        
        // Observe recording state
        cameraManager.$isRecording
            .assign(to: &$isRecording)
        
        // REMOVED: Preview visibility observer that auto-controlled session
        // This caused conflicts with manual session control during menu navigation
        // Session is now controlled explicitly by toggleCameraSession() and menu lifecycle
        print("📱 CameraViewModel: Recording observers setup (preview auto-control disabled)")
    }
    
    func checkPermission() {
        print("🔐 CameraViewModel: checkPermission called")
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        print("🔐 CameraViewModel: Current status: \(status.rawValue)")
        print("   0=notDetermined, 1=restricted, 2=denied, 3=authorized")
        
        switch status {
        case .authorized:
            print("✅ CameraViewModel: Camera authorized")
            DispatchQueue.main.async {
                self.isPermissionGranted = true
            }
            print("🎥 CameraViewModel: Setting up camera session...")
            cameraManager.setupSession()
            checkMicrophonePermissionAsync()
            
        case .notDetermined:
            print("⚠️ CameraViewModel: Permission not determined, requesting...")
            print("🚨 IMPORTANT: Permission dialog should appear NOW!")
            print("🚨 If no dialog appears, check Info.plist for NSCameraUsageDescription")
            
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                print("🔐 CameraViewModel: Permission request result: \(granted)")
                
                DispatchQueue.main.async {
                    self?.isPermissionGranted = granted
                    
                    if granted {
                        print("✅ CameraViewModel: Permission granted, setting up camera...")
                        self?.cameraManager.setupSession()
                        self?.checkMicrophonePermissionAsync()
                    } else {
                        print("❌ CameraViewModel: User denied camera permission")
                        print("❌ To fix: Settings → Privacy → Camera → Enable")
                        self?.showSettingAlert = true
                    }
                }
            }
            
        case .denied:
            print("❌ CameraViewModel: Camera access DENIED by user")
            print("❌ To fix: Settings → Privacy & Security → Camera → Enable your app")
            DispatchQueue.main.async {
                self.isPermissionGranted = false
                self.showSettingAlert = true
            }
            
        case .restricted:
            print("❌ CameraViewModel: Camera access RESTRICTED (parental controls?)")
            DispatchQueue.main.async {
                self.isPermissionGranted = false
                self.showSettingAlert = true
            }
            
        @unknown default:
            print("❓ CameraViewModel: Unknown permission status")
            DispatchQueue.main.async {
                self.isPermissionGranted = false
            }
        }
    }
    
    private func checkMicrophonePermissionAsync() {
        // Request microphone permission asynchronously without blocking
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if granted {
                    print("✅ Microphone permission granted")
                } else {
                    print("⚠️ Microphone permission denied - videos will be silent")
                }
            }
        } else if AVCaptureDevice.authorizationStatus(for: .audio) == .denied {
            print("⚠️ Microphone permission denied - videos will be silent")
        }
    }
    
    func capturePhoto() {
        print("📸 ViewModel: Capturing photo (capture mode: \(captureMode.displayName), camera mode: \(cameraManager.cameraMode.displayName))...")
        
        // Smart flash: only trigger appropriate flash based on camera mode
        let shouldFlash = flashMode == .auto
        if shouldFlash {
            triggerSmartFlash()
            // Wait longer for flash to reach peak brightness (0.15s)
            // This ensures both screen and hardware flash are at maximum intensity
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.performPhotoCapture()
            }
        } else {
            performPhotoCapture()
        }
    }
    
    private func performPhotoCapture() {
        // Check if PIP camera mode
        if cameraManager.cameraMode == .picInPic {
            // Capture PIP composed photo
            cameraManager.capturePIPPhoto(withFlash: false) { [weak self] pipImage in
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    print("📸 ViewModel: Received PIP image: \(pipImage != nil)")
                    
                    self.lastCapturedImage = pipImage
                    
                    // Save PIP image using unified save method
                    if let pipImage = pipImage {
                        print("📸 ViewModel: Saving PIP image using unified method...")
                        self.savePhotosToLibrary(backImage: pipImage, frontImage: nil)
                    } else {
                        print("❌ ViewModel: No PIP image captured!")
                    }
                }
            }
        } else {
            // Capture based on camera mode (CameraManager now returns correct images based on mode)
            cameraManager.captureDualPhotos(withFlash: false) { [weak self] backImage, frontImage in
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    print("📸 ViewModel: Received back image: \(backImage != nil)")
                    print("📸 ViewModel: Received front image: \(frontImage != nil)")
                    
                    // Store captured images (CameraManager already filtered based on mode)
                    self.capturedBackImage = backImage
                    self.capturedFrontImage = frontImage
                    
                    // Update last captured image for gallery button
                    self.lastCapturedImage = backImage ?? frontImage
                    
                    // Automatically save images to photo library
                    if backImage != nil || frontImage != nil {
                        print("📸 ViewModel: Starting save process...")
                        self.savePhotosToLibrary(backImage: backImage, frontImage: frontImage)
                    } else {
                        print("❌ ViewModel: No images captured!")
                    }
                }
            }
        }
    }
    
    /// Smart flash: trigger appropriate flash based on camera mode
    private func triggerSmartFlash() {
        switch cameraManager.cameraMode {
        case .frontOnly:
            // Front camera only - use screen flash
            print("⚡️ ViewModel: Front camera mode - using screen flash")
            triggerScreenFlash()
            
        case .backOnly:
            // Back camera only - use hardware flash
            print("⚡️ ViewModel: Back camera mode - using hardware flash")
            cameraManager.triggerFlashForCapture()
            
        case .dual, .picInPic:
            // Dual/PIP mode - use both flashes for best results
            print("⚡️ ViewModel: Dual/PIP mode - using both screen and hardware flash")
            triggerScreenFlash()
            cameraManager.triggerFlashForCapture()
        }
    }
    
    /// Trigger screen flash effect (white screen + max brightness)
    private func triggerScreenFlash() {
        print("📱 ViewModel: Triggering screen flash")
        
        // Store original brightness
        let originalBrightness = UIScreen.main.brightness
        
        // Show white screen and max brightness
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            UIScreen.main.brightness = 1.0
            self.showScreenFlash = true
            
            // Keep flash on longer (0.5s total) to ensure photo capture happens during flash peak
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showScreenFlash = false
                UIScreen.main.brightness = originalBrightness
            }
        }
    }
    
    func captureOrRecord() {
        switch captureMode {
        case .photo:
            capturePhoto()
        case .video:
            toggleVideoRecording()
        }
    }
    
    func toggleVideoRecording() {
        if isRecording {
            stopVideoRecording()
        } else {
            startVideoRecording()
        }
    }
    
    private func startVideoRecording() {
        print("🎥 ViewModel: startVideoRecording called (capture: \(captureMode.displayName), camera: \(cameraManager.cameraMode.displayName))")
        isRecording = true
        
        // Check if PIP camera mode
        if cameraManager.cameraMode == .picInPic {
            // Start PIP recording
            cameraManager.startPIPVideoRecording { [weak self] pipURL, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ ViewModel: PIP recording start error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.isRecording = false
                    }
                    return
                }
                
                print("✅ ViewModel: PIP recording started successfully")
            }
        } else {
            // Normal dual recording
            cameraManager.startVideoRecording { [weak self] backURL, frontURL, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ ViewModel: Video recording start error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.isRecording = false
                    }
                    return
                }
                
                print("✅ ViewModel: Video recording started successfully")
                // Do NOT save videos here - they are not finished yet!
            }
        }
    }
    
    private func stopVideoRecording() {
        print("🎥 ViewModel: stopVideoRecording called")
        cameraManager.stopVideoRecording { [weak self] backURL, frontURL, audioURL in
            guard let self = self else { return }
            
            print("🎥 ViewModel: Received URLs from CameraManager")
            print("   Back URL: \(backURL?.path ?? "nil")")
            print("   Front URL: \(frontURL?.path ?? "nil")")
            print("   Audio URL: \(audioURL?.path ?? "nil")")
            
            // Merge audio into videos, then save
            self.mergeAudioAndSaveVideos(backURL: backURL, frontURL: frontURL, audioURL: audioURL)
        }
    }
    
    private func mergeAudioAndSaveVideos(backURL: URL?, frontURL: URL?, audioURL: URL?) {
        print("🎬 ViewModel: Adding videos to save queue")

        let videoCount = (backURL != nil ? 1 : 0) + (frontURL != nil ? 1 : 0)

        // 将视频添加到保存队列（队列会自动处理音频合并）
        if let backURL = backURL {
            SaveQueueManager.shared.addVideoTask(videoURL: backURL, audioURL: audioURL)
        }

        if let frontURL = frontURL {
            SaveQueueManager.shared.addVideoTask(videoURL: frontURL, audioURL: audioURL)
        }

        // 立即更新UI并显示通知
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.isRecording = false

            let message = videoCount == 1 ? "视频已加入保存队列" : "\(videoCount)个视频已加入保存队列"
            self.notificationManager.show(.info(message), duration: 2.0)
        }
    }
    
    private func saveVideosToLibrary(backURL: URL?, frontURL: URL?) {
        print("🎥 ViewModel: saveVideosToLibrary called")
        print("🎥 ViewModel: Has back video: \(backURL != nil)")
        print("🎥 ViewModel: Has front video: \(frontURL != nil)")

        // Generate thumbnail for gallery button from back video (or front if back is nil)
        if let videoURL = backURL ?? frontURL {
            generateVideoThumbnail(from: videoURL) { [weak self] thumbnail in
                if let thumbnail = thumbnail {
                    DispatchQueue.main.async {
                        self?.lastCapturedImage = thumbnail
                        print("✅ ViewModel: Video thumbnail generated and set")
                    }
                }
            }
        }

        guard backURL != nil || frontURL != nil else {
            DispatchQueue.main.async {
                self.isRecording = false
            }
            return
        }

        let videoCount = (backURL != nil ? 1 : 0) + (frontURL != nil ? 1 : 0)
        print("✅ ViewModel: Saving \(videoCount) video(s)")

        var failedCount = 0
        let group = DispatchGroup()

        // Save back camera video
        if let backURL = backURL {
            group.enter()
            print("🎥 ViewModel: Saving back camera video...")
            self.saveVideoToLibrary(backURL) { success in
                if !success {
                    print("❌ ViewModel: Back camera video failed")
                    failedCount += 1
                } else {
                    print("✅ ViewModel: Back camera video saved")
                }
                group.leave()
            }
        }

        // Save front camera video
        if let frontURL = frontURL {
            group.enter()
            print("🎥 ViewModel: Saving front camera video...")
            self.saveVideoToLibrary(frontURL) { success in
                if !success {
                    print("❌ ViewModel: Front camera video failed")
                    failedCount += 1
                } else {
                    print("✅ ViewModel: Front camera video saved")
                }
                group.leave()
            }
        }

        // Show notification when all saves complete
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }

            print("🎥 ViewModel: All video saves complete. Failed: \(failedCount)")

            if failedCount > 0 {
                self.notificationManager.show(.error("视频保存失败"), duration: 2.5)
            } else {
                let message = videoCount == 1 ? "视频已保存" : "\(videoCount)个视频已保存"
                self.notificationManager.show(.success(message), duration: 2.0)
            }

            self.isRecording = false
        }
    }
    
    private func saveVideoToLibrary(_ videoURL: URL, completion: @escaping (Bool) -> Void) {
        print("🎥 ViewModel: saveVideoToLibrary called for: \(videoURL.lastPathComponent)")
        print("🎥 ViewModel: Full path: \(videoURL.path)")
        
        // Check if file exists
        let fileExists = FileManager.default.fileExists(atPath: videoURL.path)
        print("🎥 ViewModel: File exists: \(fileExists)")
        
        if fileExists {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: videoURL.path),
               let fileSize = attributes[.size] as? Int {
                print("🎥 ViewModel: File size: \(fileSize) bytes (\(Double(fileSize) / 1024.0 / 1024.0) MB)")
            }
        } else {
            print("❌ ViewModel: Video file does not exist at path!")
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }
        
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            print("🎥 ViewModel: Photo library authorization status: \(status.rawValue)")
            
            guard status == .authorized || status == .limited else {
                print("❌ ViewModel: Photo library permission denied - status: \(status.rawValue)")
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }
            
            print("🎥 ViewModel: Permission granted, saving video...")
            
            PHPhotoLibrary.shared().performChanges({
                print("🎥 ViewModel: Creating asset from video file...")
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        print("✅ ViewModel: Video saved successfully!")
                        
                        // Clean up temporary file
                        try? FileManager.default.removeItem(at: videoURL)
                        print("✅ ViewModel: Temporary video file deleted")
                        
                        completion(true)
                    } else {
                        print("❌ ViewModel: Failed to save video: \(error?.localizedDescription ?? "unknown")")
                        if let error = error {
                            print("❌ ViewModel: Error details: \(error)")
                        }
                        completion(false)
                    }
                }
            }
        }
    }
    
    // Generate video thumbnail for preview
    private func generateVideoThumbnail(from videoURL: URL, completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVURLAsset(url: videoURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 300, height: 300)
            
            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                let thumbnail = UIImage(cgImage: cgImage)
                completion(thumbnail)
            } catch {
                print("❌ ViewModel: Failed to generate video thumbnail: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }
    
    func switchMode() {
        // Prevent mode switching while recording
        guard !isRecording else {
            print("⚠️ ViewModel: Cannot switch mode while recording")
            return
        }
        
        // Toggle between photo and video
        captureMode = captureMode == .photo ? .video : .photo
        
        print("📸 ViewModel: Switched to \(captureMode.fullDisplayName)")
    }
    
    // Show a notification when mode changes
    func switchCameraMode() {
        // Cycle through camera modes: frontOnly -> backOnly -> dual -> picInPic -> frontOnly
        let modes = CameraMode.allCases
        if let currentIndex = modes.firstIndex(of: cameraManager.cameraMode) {
            let nextIndex = (currentIndex + 1) % modes.count
            let nextMode = modes[nextIndex]
            cameraManager.cameraMode = nextMode
            
            print("📷 ViewModel: Switched to camera mode: \(nextMode.displayName)")
            
            // Reconfigure session for new camera mode
            cameraManager.setupSession(forceReconfigure: true)
        }
    }
    
    func setZoom(_ factor: CGFloat) {
        zoomFactor = factor
        cameraManager.setZoom(factor)
    }
    
    func toggleFlash() {
        flashMode.next()
        print("📸 ViewModel: Flash mode changed to \(flashMode.displayName)")
        
        // Update hardware torch based on mode
        switch flashMode {
        case .off:
            cameraManager.setFlashMode(.off)
        case .on:
            cameraManager.setFlashMode(.on)
        case .auto:
            // Auto mode uses screen flash, turn off torch
            cameraManager.setFlashMode(.off)
        }
    }
    
    func openSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else { return }
        if UIApplication.shared.canOpenURL(settingsUrl) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    func savePhotosToLibrary(backImage: UIImage?, frontImage: UIImage?) {
        print("📸 ViewModel: savePhotosToLibrary called")
        print("📸 ViewModel: Has back image: \(backImage != nil)")
        print("📸 ViewModel: Has front image: \(frontImage != nil)")

        guard backImage != nil || frontImage != nil else {
            print("❌ ViewModel: No photos to save!")
            return
        }

        let photoCount = (backImage != nil ? 1 : 0) + (frontImage != nil ? 1 : 0)
        print("✅ ViewModel: Adding \(photoCount) photo(s) to save queue")

        // 使用保存队列系统
        if let backImage = backImage {
            SaveQueueManager.shared.addPhotoTask(image: backImage, isFrontCamera: false)
        }

        if let frontImage = frontImage {
            SaveQueueManager.shared.addPhotoTask(image: frontImage, isFrontCamera: true)
        }

        // 立即显示通知
        DispatchQueue.main.async { [weak self] in
            let message = photoCount == 1 ? "照片已加入保存队列" : "\(photoCount)张照片已加入保存队列"
            self?.notificationManager.show(.info(message), duration: 2.0)
        }
    }
    
    func startCameraIfNeeded() {
        // Camera now starts in init, this is kept for compatibility
        print("📸 ViewModel: startCameraIfNeeded called")
        print("📸 ViewModel: isSessionRunning = \(cameraManager.isSessionRunning)")
        print("📸 ViewModel: isPermissionGranted = \(isPermissionGranted)")
        
        if !cameraManager.isSessionRunning && isPermissionGranted {
            print("📸 ViewModel: Conditions met, restarting camera session")
            cameraManager.setupSession()
        } else {
            print("📸 ViewModel: Camera already running or permission not granted, skipping setup")
        }
    }
    
    // MARK: - Testing Methods
    
    /// Test notification system with simulated data (DISABLED - notifications removed)
    func testNotificationSystem() {
        print("\n🧪 ===== TESTING NOTIFICATION SYSTEM (DISABLED) =====")
        print("🧪 Notification system has been removed")
    }
    
    /// Test rapid photo capture simulation (DISABLED - notifications removed)
    func testRapidPhotos() {
        print("\n🧪 ===== TESTING RAPID PHOTO CAPTURE (DISABLED) =====")
        print("🧪 Notification system has been removed")
    }
    
    /// Test PIP composition with colored test images
    /// Creates a test image with RED background and GREEN PIP at top-right
    func testPIPComposition() {
        print("\n🧪 ===== TESTING PIP COMPOSITION =====")
        
        guard let testImage = PIPComposer.createTestPIPImage(isLandscape: false) else {
            print("❌ Failed to create test PIP image")
            return
        }
        
        print("✅ Test PIP image created")
        print("   Size: \(testImage.size)")
        print("   Saving to photo library...")
        
        // Save test image to verify positioning
        cameraManager.savePhotoToLibrary(testImage, isFrontCamera: false) { success, error in
            DispatchQueue.main.async {
                if success {
                    print("✅ Test image saved! Check Photos app:")
                    print("   - Should see RED background")
                    print("   - GREEN square at TOP-RIGHT corner")
                    print("   - White border around green square")
                    self.lastCapturedImage = testImage
                } else {
                    print("❌ Failed to save test image: \(error?.localizedDescription ?? "unknown")")
                }
            }
        }
        
        print("🧪 ===== TEST COMPLETE =====\n")
    }
    
    /// Test camera mode filtering
    func testCameraModeFiltering() {
        print("\n🧪 ===== TESTING CAMERA MODE FILTERING =====")
        print("🧪 Current camera mode: \(cameraManager.cameraMode.displayName)")
        
        // Simulate different modes
        let modes: [CameraMode] = [.backOnly, .frontOnly, .dual]
        
        for (index, mode) in modes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 2.0) {
                print("🧪 Testing mode: \(mode.displayName)")
                self.cameraManager.cameraMode = mode
                
                // Simulate capture
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("🧪 Simulating capture in \(mode.displayName) mode")
                }
            }
        }
        
        print("🧪 ===== CAMERA MODE TEST STARTED =====\n")
    }
}
