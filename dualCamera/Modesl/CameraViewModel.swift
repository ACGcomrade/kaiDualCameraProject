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
        print("📸 ViewModel: Capturing dual photos...")
        
        // Trigger screen flash and hardware flash if in auto mode
        let shouldFlash = flashMode == .auto
        if shouldFlash {
            triggerScreenFlash()
        }
        
        cameraManager.captureDualPhotos(withFlash: shouldFlash) { [weak self] backImage, frontImage in
            DispatchQueue.main.async {
                print("📸 ViewModel: Received back image: \(backImage != nil)")
                print("📸 ViewModel: Received front image: \(frontImage != nil)")
                
                self?.capturedBackImage = backImage
                self?.capturedFrontImage = frontImage
                
                // Update last captured image for gallery button (prefer back camera)
                self?.lastCapturedImage = backImage ?? frontImage
                
                // Automatically save both images to photo library
                if backImage != nil || frontImage != nil {
                    print("📸 ViewModel: Starting save process...")
                    self?.savePhotosToLibrary()
                } else {
                    print("❌ ViewModel: No images captured!")
                }
            }
        }
    }
    
    /// Trigger screen flash effect (white screen + max brightness)
    private func triggerScreenFlash() {
        print("⚡️ ViewModel: Triggering screen flash")
        
        // Store original brightness
        let originalBrightness = UIScreen.main.brightness
        
        // Show white screen and max brightness
        DispatchQueue.main.async {
            UIScreen.main.brightness = 1.0
            self.showScreenFlash = true
            
            // Hide after 0.15 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.showScreenFlash = false
                
                // Restore original brightness after 0.3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    UIScreen.main.brightness = originalBrightness
                }
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
        print("🎥 ViewModel: startVideoRecording called")
        isRecording = true
        
        cameraManager.startVideoRecording { [weak self] backURL, frontURL, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ ViewModel: Video recording start error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.saveStatus = "Video recording failed to start"
                    self.showSaveAlert = true
                    self.isRecording = false
                }
                return
            }
            
            print("✅ ViewModel: Video recording started successfully")
            // Do NOT save videos here - they are not finished yet!
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
        print("🎬 ViewModel: Starting audio merge process")
        
        guard let audioURL = audioURL else {
            print("⚠️ ViewModel: No audio file, saving videos without audio")
            saveVideosToLibrary(backURL: backURL, frontURL: frontURL)
            return
        }
        
        let group = DispatchGroup()
        var mergedBackURL: URL?
        var mergedFrontURL: URL?
        var hadError = false
        
        // Merge audio into back camera video
        if let backURL = backURL {
            group.enter()
            print("🎬 ViewModel: Merging audio into back camera video...")
            VideoAudioMerger.mergeAudioIntoVideo(videoURL: backURL, audioURL: audioURL) { result in
                switch result {
                case .success(let url):
                    print("✅ ViewModel: Back video merged successfully")
                    mergedBackURL = url
                    // Clean up original video file
                    try? FileManager.default.removeItem(at: backURL)
                case .failure(let error):
                    print("❌ ViewModel: Back video merge failed: \(error.localizedDescription)")
                    hadError = true
                    mergedBackURL = backURL // Use original if merge fails
                }
                group.leave()
            }
        }
        
        // Merge audio into front camera video
        if let frontURL = frontURL {
            group.enter()
            print("🎬 ViewModel: Merging audio into front camera video...")
            VideoAudioMerger.mergeAudioIntoVideo(videoURL: frontURL, audioURL: audioURL) { result in
                switch result {
                case .success(let url):
                    print("✅ ViewModel: Front video merged successfully")
                    mergedFrontURL = url
                    // Clean up original video file
                    try? FileManager.default.removeItem(at: frontURL)
                case .failure(let error):
                    print("❌ ViewModel: Front video merge failed: \(error.localizedDescription)")
                    hadError = true
                    mergedFrontURL = frontURL // Use original if merge fails
                }
                group.leave()
            }
        }
        
        // After all merges complete, save to library
        group.notify(queue: .main) {
            print("🎬 ViewModel: Audio merge complete, saving to library...")
            
            // Clean up audio file
            try? FileManager.default.removeItem(at: audioURL)
            print("✅ ViewModel: Temporary audio file deleted")
            
            if hadError {
                print("⚠️ ViewModel: Some merges failed, but continuing with available videos")
            }
            
            self.saveVideosToLibrary(backURL: mergedBackURL, frontURL: mergedFrontURL)
        }
    }
    
    private func saveVideosToLibrary(backURL: URL?, frontURL: URL?) {
        print("🎥 ViewModel: saveVideosToLibrary called")
        print("🎥 ViewModel: Has back video: \(backURL != nil)")
        print("🎥 ViewModel: Has front video: \(frontURL != nil)")
        
        guard backURL != nil || frontURL != nil else {
            DispatchQueue.main.async {
                self.saveStatus = "No videos to save"
                self.showSaveAlert = true
                self.isRecording = false
            }
            return
        }
        
        var savedCount = 0
        var failedCount = 0
        let group = DispatchGroup()
        
        // Save back camera video
        if let backURL = backURL {
            group.enter()
            print("🎥 ViewModel: Saving back camera video...")
            self.saveVideoToLibrary(backURL) { success in
                if success {
                    print("✅ ViewModel: Back camera video saved")
                    savedCount += 1
                } else {
                    print("❌ ViewModel: Back camera video failed")
                    failedCount += 1
                }
                group.leave()
            }
        }
        
        // Save front camera video
        if let frontURL = frontURL {
            group.enter()
            print("🎥 ViewModel: Saving front camera video...")
            self.saveVideoToLibrary(frontURL) { success in
                if success {
                    print("✅ ViewModel: Front camera video saved")
                    savedCount += 1
                } else {
                    print("❌ ViewModel: Front camera video failed")
                    failedCount += 1
                }
                group.leave()
            }
        }
        
        // Show result after all saves complete
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            print("🎥 ViewModel: All video saves complete. Saved: \(savedCount), Failed: \(failedCount)")
            
            if failedCount == 0 {
                self.saveStatus = "\(savedCount) video(s) saved successfully!"
            } else if savedCount == 0 {
                self.saveStatus = "Failed to save videos. Please check photo library permissions."
            } else {
                self.saveStatus = "Saved \(savedCount) video(s), failed \(failedCount)"
            }
            
            self.showSaveAlert = true
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
    
    func switchMode() {
        captureMode = captureMode == .photo ? .video : .photo
        print("📸 ViewModel: Switched to \(captureMode.displayName) mode")
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
    
    func savePhotosToLibrary() {
        let backImage = capturedBackImage
        let frontImage = capturedFrontImage
        
        print("📸 ViewModel: savePhotosToLibrary called")
        print("📸 ViewModel: Has back image: \(backImage != nil)")
        print("📸 ViewModel: Has front image: \(frontImage != nil)")
        
        guard backImage != nil || frontImage != nil else {
            saveStatus = "No photos to save"
            showSaveAlert = true
            return
        }
        
        var savedCount = 0
        var failedCount = 0
        let group = DispatchGroup()
        
        // Save back camera image
        if let backImage = backImage {
            group.enter()
            print("📸 ViewModel: Saving back camera image...")
            cameraManager.savePhotoToLibrary(backImage) { success, error in
                if success {
                    print("✅ ViewModel: Back camera photo saved")
                    savedCount += 1
                } else {
                    print("❌ ViewModel: Back camera photo failed: \(error?.localizedDescription ?? "unknown")")
                    failedCount += 1
                }
                group.leave()
            }
        }
        
        // Save front camera image
        if let frontImage = frontImage {
            group.enter()
            print("📸 ViewModel: Saving front camera image...")
            cameraManager.savePhotoToLibrary(frontImage) { success, error in
                if success {
                    print("✅ ViewModel: Front camera photo saved")
                    savedCount += 1
                } else {
                    print("❌ ViewModel: Front camera photo failed: \(error?.localizedDescription ?? "unknown")")
                    failedCount += 1
                }
                group.leave()
            }
        }
        
        // Show result after all saves complete
        group.notify(queue: .main) { [weak self] in
            print("📸 ViewModel: All saves complete. Saved: \(savedCount), Failed: \(failedCount)")
            if failedCount == 0 {
                self?.saveStatus = "\(savedCount) photo(s) saved successfully!"
            } else if savedCount == 0 {
                self?.saveStatus = "Failed to save photos. Please check photo library permissions in Settings."
            } else {
                self?.saveStatus = "Saved \(savedCount) photo(s), failed \(failedCount)"
            }
            self?.showSaveAlert = true
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
}
