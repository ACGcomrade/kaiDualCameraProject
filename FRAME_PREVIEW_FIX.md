# 帧捕获预览修复

## 问题诊断

根据控制台输出:
```
CameraManager: Back image: false, Front image: false
ViewModel: No images captured!
```

**根本原因**: `lastBackFrame` 和 `lastFrontFrame` 一直是 `nil`,说明帧回调 delegate 没有正常工作。

## 修复内容

### 1. 修复 Delegate 方法中的相机识别逻辑

**问题**: 之前使用 `output == backVideoDataOutput` 进行对象引用比较可能失败

**修复**: 改为通过 `AVCaptureConnection` 的 `inputPort` 来识别相机位置:

```swift
func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    if let videoOutput = output as? AVCaptureVideoDataOutput {
        if let inputPort = connection.inputPorts.first,
           let deviceInput = inputPort.input as? AVCaptureDeviceInput {
            
            let position = deviceInput.device.position
            
            if position == .back {
                // 处理后置摄像头帧
                frameLock.lock()
                lastBackFrame = sampleBuffer
                backFrameCount += 1
                frameLock.unlock()
            } else if position == .front {
                // 处理前置摄像头帧
                frameLock.lock()
                lastFrontFrame = sampleBuffer
                frontFrameCount += 1
                frameLock.unlock()
            }
        }
    }
}
```

### 2. 重写 DualCameraPreview - 使用帧渲染而非 AVCaptureVideoPreviewLayer

**问题**: `AVCaptureVideoDataOutput` 不会自动填充 `AVCaptureVideoPreviewLayer`

**修复**: 使用 `UIImageView` 并通过定时器每秒刷新30次:

```swift
// 在 makeUIView 中创建定时器
let timer = Timer.publish(every: 1.0/30.0, on: .main, in: .common)
    .autoconnect()
    .sink { _ in
        self.viewModel.cameraManager.getLatestFrames { backImage, frontImage in
            view.updateBackFrame(backImage)
            view.updateFrontFrame(frontImage)
        }
    }
```

### 3. 添加 getLatestFrames 方法

在 `CameraManager` 中添加了新方法供预览调用:

```swift
func getLatestFrames(completion: @escaping (UIImage?, UIImage?) -> Void) {
    frameLock.lock()
    let backFrame = lastBackFrame
    let frontFrame = lastFrontFrame
    frameLock.unlock()
    
    let backImage = imageFromSampleBuffer(backFrame)
    let frontImage = imageFromSampleBuffer(frontFrame)
    
    completion(backImage, frontImage)
}
```

### 4. 添加调试计数器

添加了帧计数器,每30帧输出一次日志,用于验证帧是否正常接收:

```swift
private var backFrameCount: Int = 0
private var frontFrameCount: Int = 0

// 在 delegate 中
backFrameCount += 1
if backFrameCount % 30 == 0 {
    print("📹 CameraManager: Received \(backFrameCount) back camera frames")
}
```

## 预期效果

1. **预览显示**: 应该立即看到双摄像头预览(后置全屏 + 前置PIP)
2. **帧计数日志**: 控制台每秒输出一次 "Received XX frames" (30帧/秒)
3. **照片拍摄**: 点击拍照按钮应该立即捕获,返回 `true`
4. **视频录制**: 预览不会冻结,录制期间持续流畅

## 测试步骤

1. 运行应用,授予相机和麦克风权限
2. 检查控制台是否出现:
   ```
   📹 CameraManager: Received 30 back camera frames
   📹 CameraManager: Received 30 front camera frames
   ```
3. 检查预览是否显示(应该看到实时画面)
4. 点击拍照,检查是否输出:
   ```
   📸 CameraManager: Back image: true, Front image: true
   ```
5. 测试视频录制

## 如果仍然没有帧

可能的原因:
1. **权限问题**: 确保在设置中授予了相机权限
2. **会话未启动**: 检查控制台是否有 "Session started!" 日志
3. **设备不支持**: 多摄像头需要 iPhone XS 或更新机型 + iOS 13+

## 已修改的文件

1. `/dualCamera/Managers/CameraManager.swift`
   - 修复 delegate 方法的相机识别逻辑
   - 添加 `getLatestFrames` 方法
   - 添加帧计数器和调试日志

2. `/dualCamera/Managers/DualCameraPreview.swift`
   - 完全重写为基于 UIImageView 的帧渲染模式
   - 使用定时器每秒30帧刷新
   - 移除了 AVCaptureVideoPreviewLayer 相关代码
