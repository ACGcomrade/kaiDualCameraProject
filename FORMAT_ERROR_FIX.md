# 相机格式不兼容错误修复

## 问题诊断

控制台显示的关键错误:
```
❌ Session runtime error: AVError -11873
❌ Error description: Cannot Record
❌ NSLocalizedFailureReason=The camera's active format is unsupported by this session
```

**根本原因**: 我们通过 `configureFrameRate()` 为每个相机设置了 `activeFormat`,但选择的格式**不支持多相机会话**。

## 错误代码含义

- **AVError -11873**: `AVErrorDeviceNotAvailableInBackground` / 格式不支持
- **"Cannot Record"**: 会话因格式不兼容无法启动

## 为什么会发生

在单相机会话中,几乎所有格式都可用。但在 `AVCaptureMultiCamSession` 中:
- 只有标记为 `isMultiCamSupported = true` 的格式可用
- 高分辨率格式(如4K)通常不支持多相机
- 不同相机必须使用兼容的格式组合

原代码的问题:
```swift
// ❌ 错误 - 没有检查 isMultiCamSupported
for format in device.formats {
    // 选择任意匹配帧率的格式
    device.activeFormat = format  // 可能不支持多相机!
}
```

## 修复方案

### 1. 移除强制帧率配置

**修复前**:
```swift
configureFrameRate(for: backCamera, fps: settings.backCameraFrameRate.rawValue)
configureFrameRate(for: frontCamera, fps: settings.frontCameraFrameRate.rawValue)
```

**修复后**:
```swift
// 移除 - 让系统自动选择兼容格式
// 添加注释说明原因
```

### 2. 实现多相机格式选择

添加新方法 `findMultiCamCompatibleFormat()`:

```swift
private func findMultiCamCompatibleFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
    var bestFormat: AVCaptureDevice.Format?
    var bestWidth: Int32 = 0
    
    for format in device.formats {
        // ✅ 关键检查: isMultiCamSupported
        if format.isMultiCamSupported {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let width = dimensions.width
            
            // 优先选择 1080p 或 720p (性能更好)
            if width <= 1920 && width > bestWidth {
                bestFormat = format
                bestWidth = width
            }
        }
    }
    
    return bestFormat
}
```

### 3. 应用兼容格式

```swift
// 后置摄像头
if let multiCamFormat = findMultiCamCompatibleFormat(for: backCamera) {
    try? backCamera.lockForConfiguration()
    backCamera.activeFormat = multiCamFormat
    backCamera.unlockForConfiguration()
    print("✅ Back camera using multi-cam compatible format")
}

// 前置摄像头
if let multiCamFormat = findMultiCamCompatibleFormat(for: frontCamera) {
    try? frontCamera.lockForConfiguration()
    frontCamera.activeFormat = multiCamFormat
    frontCamera.unlockForConfiguration()
    print("✅ Front camera using multi-cam compatible format")
}
```

## 预期效果

修复后,运行应用应该看到:

### 成功日志:
```
🔍 CameraManager: Finding multi-cam compatible format for back camera
   Format: 1920x1080, multi-cam: ✅
   Format: 1280x720, multi-cam: ✅
✅ CameraManager: Selected format: 1920x1080
✅ CameraManager: Back camera using multi-cam compatible format

🔍 CameraManager: Finding multi-cam compatible format for front camera
   Format: 1920x1080, multi-cam: ✅
✅ CameraManager: Selected format: 1920x1080
✅ CameraManager: Front camera using multi-cam compatible format

🔧 CameraManager: Session configuration committed
🔍 CameraManager: Session has 3 outputs
▶️ CameraManager: Starting session...
✅ CameraManager: Session isRunning = true ✅✅✅
🎯 CameraManager: captureOutput DELEGATE CALLED! (first time)
📹 CameraManager: Received 30 back camera frames
📹 CameraManager: Received 30 front camera frames
```

### 不再出现:
```
❌ Session runtime error: -11873  (这个错误应该消失)
❌ Cannot Record
❌ The camera's active format is unsupported
```

## 帧率影响

移除固定帧率配置后:
- **默认帧率**: 系统会选择30fps(常见)
- **可变帧率**: 根据光线条件自动调整
- **更好兼容性**: 保证多相机会话能启动

如果未来需要特定帧率,应该:
1. 先检查 `format.isMultiCamSupported`
2. 再检查 `format.videoSupportedFrameRateRanges`
3. 同时满足两个条件才设置

## 测试步骤

1. 运行应用
2. 检查控制台输出
3. 验证关键点:
   - ✅ "Selected format: XXXxYYY" (应该是1920x1080或更低)
   - ✅ "Session isRunning = true"
   - ✅ "captureOutput DELEGATE CALLED!"
   - ✅ "Received XX frames"
4. 检查预览是否显示
5. 点击拍照,检查是否成功

## 已修改的文件

`/dualCamera/Managers/CameraManager.swift`
- 移除了对 `configureFrameRate()` 的调用
- 添加了 `findMultiCamCompatibleFormat()` 方法
- 在相机设置时应用兼容格式
- 保留了原 `configureFrameRate()` 方法以备将来改进

## 如果仍然失败

如果修复后仍然看到格式错误:
1. 检查设备型号 - 确保是 iPhone XS 或更新
2. 检查 iOS 版本 - 需要 iOS 13.0+
3. 查看日志中是否有 "multi-cam: ✅" - 确认存在兼容格式
4. 尝试完全注释掉格式选择代码,让系统完全自动选择
