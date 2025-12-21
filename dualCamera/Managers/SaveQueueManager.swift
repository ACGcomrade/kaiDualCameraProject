//
//  SaveQueueManager.swift
//  dualCamera
//
//  持久化的媒体保存队列管理器
//  支持应用退出后恢复保存任务
//

import Foundation
import UIKit
import AVFoundation
import Photos
import Combine

/// 保存任务类型
enum SaveTaskType: Codable {
    case photo(data: Data, isFrontCamera: Bool)
    case video(videoPath: String, audioPath: String?)
    case videoOnly(videoPath: String)
}

/// 保存任务
struct SaveTask: Codable {
    let id: String
    let type: SaveTaskType
    let createdAt: Date
    var status: TaskStatus
    var progress: Double

    enum TaskStatus: String, Codable {
        case pending     // 等待处理
        case processing  // 正在处理
        case completed   // 已完成
        case failed      // 失败
    }
}

/// 持久化保存队列管理器
class SaveQueueManager: ObservableObject {

    static let shared = SaveQueueManager()

    // MARK: - Published Properties
    @Published private(set) var pendingTasksCount: Int = 0
    @Published private(set) var isProcessing: Bool = false

    // MARK: - Private Properties
    private var tasks: [SaveTask] = []
    private let tasksKey = "SaveQueueTasks"
    private let queue = DispatchQueue(label: "com.dualcamera.savequeue", qos: .utility)
    private var isProcessingQueue = false

    // 缓存上一次的值，避免不必要的UI更新
    private var lastPendingCount: Int = 0
    private var lastIsProcessing: Bool = false

    // MARK: - Initialization

    private init() {
        // 后台加载任务，不阻塞UI
        queue.async { [weak self] in
            self?.loadTasks()
            self?.cleanupOldTasks()
            self?.updatePublishedPropertiesIfNeeded()

            // 延迟恢复处理，避免启动时性能开销
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.resumeProcessing()
            }
        }
    }

    // MARK: - Public Methods

    /// 添加照片保存任务
    func addPhotoTask(image: UIImage, isFrontCamera: Bool) {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            print("❌ SaveQueue: Failed to convert image to data")
            return
        }

        let task = SaveTask(
            id: UUID().uuidString,
            type: .photo(data: data, isFrontCamera: isFrontCamera),
            createdAt: Date(),
            status: .pending,
            progress: 0.0
        )

        addTask(task)
    }

    /// 添加视频保存任务（带音频合并）
    func addVideoTask(videoURL: URL, audioURL: URL?) {
        // 复制文件到持久化目录
        guard let savedVideoPath = copyToTempDirectory(videoURL),
              let savedAudioPath = audioURL.flatMap({ copyToTempDirectory($0) }) else {
            print("❌ SaveQueue: Failed to save files to persistent storage")
            return
        }

        let task = SaveTask(
            id: UUID().uuidString,
            type: .video(videoPath: savedVideoPath, audioPath: savedAudioPath),
            createdAt: Date(),
            status: .pending,
            progress: 0.0
        )

        addTask(task)
    }

    /// 添加纯视频保存任务（无音频）
    func addVideoOnlyTask(videoURL: URL) {
        guard let savedVideoPath = copyToTempDirectory(videoURL) else {
            print("❌ SaveQueue: Failed to save video to persistent storage")
            return
        }

        let task = SaveTask(
            id: UUID().uuidString,
            type: .videoOnly(videoPath: savedVideoPath),
            createdAt: Date(),
            status: .pending,
            progress: 0.0
        )

        addTask(task)
    }

    /// 恢复处理队列
    func resumeProcessing() {
        print("🔄 SaveQueue: Resuming processing...")
        processNextTask()
    }

    /// 暂停处理队列
    func pauseProcessing() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.isProcessingQueue = false
            self.updatePublishedPropertiesIfNeeded()
        }
    }

    // MARK: - Private Methods

    private func addTask(_ task: SaveTask) {
        queue.async { [weak self] in
            guard let self = self else { return }

            self.tasks.append(task)

            // 异步保存，不阻塞
            self.queue.async {
                self.saveTasks()
            }

            self.updatePublishedPropertiesIfNeeded()

            #if DEBUG
            print("✅ SaveQueue: Task added, Total: \(self.tasks.count)")
            #endif

            // 自动开始处理
            self.processNextTask()
        }
    }

    private func processNextTask() {
        queue.async { [weak self] in
            guard let self = self else { return }

            // 如果已经在处理，跳过
            guard !self.isProcessingQueue else { return }

            // 查找下一个待处理的任务
            guard let nextTask = self.tasks.first(where: { $0.status == .pending }) else {
                self.isProcessingQueue = false
                self.updatePublishedPropertiesIfNeeded()
                return
            }

            self.isProcessingQueue = true
            self.updatePublishedPropertiesIfNeeded()
            self.updateTaskStatus(taskId: nextTask.id, status: .processing)

            // 处理任务
            self.executeTask(nextTask) { [weak self] success in
                guard let self = self else { return }

                self.queue.async {
                    let status: SaveTask.TaskStatus = success ? .completed : .failed
                    self.updateTaskStatus(taskId: nextTask.id, status: status)

                    self.isProcessingQueue = false

                    // 处理下一个任务
                    self.processNextTask()
                }
            }
        }
    }

    private func executeTask(_ task: SaveTask, completion: @escaping (Bool) -> Void) {
        switch task.type {
        case .photo(let data, let isFrontCamera):
            executePhotoTask(data: data, isFrontCamera: isFrontCamera, completion: completion)

        case .video(let videoPath, let audioPath):
            executeVideoTask(videoPath: videoPath, audioPath: audioPath, completion: completion)

        case .videoOnly(let videoPath):
            executeVideoOnlyTask(videoPath: videoPath, completion: completion)
        }
    }

    private func executePhotoTask(data: Data, isFrontCamera: Bool, completion: @escaping (Bool) -> Void) {
        guard let image = UIImage(data: data) else {
            completion(false)
            return
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                completion(false)
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.creationRequestForAsset(from: image)
            }) { success, error in
                if let error = error {
                    print("❌ SaveQueue: Photo save error: \(error.localizedDescription)")
                }
                completion(success)
            }
        }
    }

    private func executeVideoTask(videoPath: String, audioPath: String?, completion: @escaping (Bool) -> Void) {
        let videoURL = URL(fileURLWithPath: videoPath)

        guard let audioPath = audioPath else {
            // 无音频，直接保存
            executeVideoOnlyTask(videoPath: videoPath, completion: completion)
            return
        }

        let audioURL = URL(fileURLWithPath: audioPath)

        // 合并音频和视频
        print("🎬 SaveQueue: Merging audio into video...")
        VideoAudioMerger.mergeAudioIntoVideo(videoURL: videoURL, audioURL: audioURL) { result in
            switch result {
            case .success(let mergedURL):
                print("✅ SaveQueue: Video merged successfully")

                // 保存到相册
                self.saveVideoToLibrary(mergedURL) { success in
                    // 清理文件
                    try? FileManager.default.removeItem(at: videoURL)
                    try? FileManager.default.removeItem(at: audioURL)
                    try? FileManager.default.removeItem(at: mergedURL)

                    completion(success)
                }

            case .failure(let error):
                print("❌ SaveQueue: Video merge failed: \(error.localizedDescription)")
                // 合并失败，保存原始视频
                self.saveVideoToLibrary(videoURL) { success in
                    try? FileManager.default.removeItem(at: videoURL)
                    try? FileManager.default.removeItem(atPath: audioPath)
                    completion(success)
                }
            }
        }
    }

    private func executeVideoOnlyTask(videoPath: String, completion: @escaping (Bool) -> Void) {
        let videoURL = URL(fileURLWithPath: videoPath)

        saveVideoToLibrary(videoURL) { success in
            try? FileManager.default.removeItem(at: videoURL)
            completion(success)
        }
    }

    private func saveVideoToLibrary(_ videoURL: URL, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                completion(false)
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
            }) { success, error in
                if let error = error {
                    print("❌ SaveQueue: Video save error: \(error.localizedDescription)")
                }
                completion(success)
            }
        }
    }

    // MARK: - Persistence

    private func saveTasks() {
        if let encoded = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(encoded, forKey: tasksKey)
        }
    }

    private func loadTasks() {
        if let data = UserDefaults.standard.data(forKey: tasksKey),
           let decoded = try? JSONDecoder().decode([SaveTask].self, from: data) {
            tasks = decoded
            #if DEBUG
            print("📂 SaveQueue: Loaded \(tasks.count) tasks")
            #endif
        }
    }

    private func updateTaskStatus(taskId: String, status: SaveTask.TaskStatus) {
        if let index = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[index].status = status

            // 在后台线程保存，不阻塞主线程
            queue.async {
                self.saveTasks()
            }

            // 只在需要时更新UI
            updatePublishedPropertiesIfNeeded()
        }
    }

    private func updatePublishedPropertiesIfNeeded() {
        let pending = tasks.filter { $0.status == .pending || $0.status == .processing }.count
        let processing = isProcessingQueue

        // 只有值真正改变时才更新（避免不必要的UI重绘）
        if pending != lastPendingCount || processing != lastIsProcessing {
            lastPendingCount = pending
            lastIsProcessing = processing

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.pendingTasksCount = pending
                self.isProcessing = processing
            }
        }
    }

    private func cleanupOldTasks() {
        // 删除超过7天的已完成任务
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        tasks.removeAll { task in
            task.status == .completed && task.createdAt < sevenDaysAgo
        }
        saveTasks()
    }

    // MARK: - File Management

    private func copyToTempDirectory(_ url: URL) -> String? {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("SaveQueue", isDirectory: true)

        // 创建目录（只在首次需要时）
        try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let fileName = "\(UUID().uuidString)_\(url.lastPathComponent)"
        let destinationURL = tempDir.appendingPathComponent(fileName)

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: url, to: destinationURL)
            return destinationURL.path
        } catch {
            #if DEBUG
            print("❌ SaveQueue: Copy failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }
}
