# Delegate 回调诊断与修复

## 问题分析

根据控制台输出,**关键证据**:
```
CameraManager: Converting frames to images...
CameraManager: Back image: false, Front image: false
```

这说明 `lastBackFrame` 和 `lastFrontFrame` 都是 `nil`,意味着 `captureOutput` delegate 方法**从未被调用**,或者没有正确存储帧。

## 可能的根本原因

### 1. ❌ 队列冲突 (已修复)
**问题**: 两个 `AVCaptureVideoDataOutput` 使用了相同的 `videoDataQueue`

在多相机会话中,每个输出应该有独立的队列,否则系统可能无法正确调度回调。

**修复**:
```swift
// 之前 - 共享队列
private let videoDataQueue = DispatchQueue(label: "videoDataQueue")
backVideoOutput.setSampleBufferDelegate(self, queue: videoDataQueue)
frontVideoOutput.setSampleBufferDelegate(self, queue: videoDataQueue)

// 现在 - 独立队列
private let backVideoDataQueue = DispatchQueue(label: "backVideoDataQueue")
private let frontVideoDataQueue = DispatchQueue(label: "frontVideoDataQueue")
backVideoOutput.setSampleBufferDelegate(self, queue: backVideoDataQueue)
frontVideoOutput.setSampleBufferDelegate(self, queue: frontVideoDataQueue)
```

### 2. 🔍 Delegate 未被调用的诊断

添加了关键日志:
```swift
func captureOutput(...) {
    static var callCount = 0
    callCount += 1
    if callCount == 1 {
        print("🎯 CameraManager: captureOutput DELEGATE CALLED! (first time)")
    }
    ...
}
```

**预期结果**: 如果 delegate 正常工作,应该在启动后1秒内看到这条日志

**如果没有出现**: 说明 delegate 根本没被调用,需要检查:
- Session 是否真的在运行
- Outputs 是否正确添加
- Delegate 是否正确设置

### 3. 🔍 会话状态验证

添加了会话状态检查:
```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
    print("🔍 CameraManager: Session isRunning = \(newSession.isRunning)")
    print("🔍 CameraManager: Session isInterrupted = \(newSession.isInterrupted)")
}
```

### 4. 🔍 Outputs 验证

```swift
print("🔍 CameraManager: Session has \(newSession.outputs.count) outputs")
for (index, output) in newSession.outputs.enumerated() {
    if let videoOutput = output as? AVCaptureVideoDataOutput {
        print("🔍 CameraManager: Output \(index): AVCaptureVideoDataOutput, delegate: \(videoOutput.sampleBufferDelegate != nil)")
    }
}
```

**预期**: 应该看到至少 2 个 video outputs,每个都有 delegate

## 修复内容总结

1. ✅ 为每个相机创建独立的 dispatch queue
2. ✅ 在 delegate 方法开始处添加首次调用日志
3. ✅ 在拍照方法中输出帧计数器,确认是否有帧被接收
4. ✅ 添加会话状态验证日志
5. ✅ 添加 outputs 和 delegate 验证日志

## 测试步骤

运行应用后,检查控制台输出:

### Step 1: 验证会话启动
应该看到:
```
✅ CameraManager: Back camera video data output added
✅ CameraManager: Front camera video data output added
🔍 CameraManager: Session has 3 outputs
🔍 CameraManager: Output 0: AVCaptureVideoDataOutput, delegate: true
🔍 CameraManager: Output 1: AVCaptureVideoDataOutput, delegate: true
✅ CameraManager: Session started!
🔍 CameraManager: Session isRunning = true
🔍 CameraManager: Session isInterrupted = false
```

### Step 2: 验证 Delegate 被调用
应该在1秒内看到:
```
🎯 CameraManager: captureOutput DELEGATE CALLED! (first time)
```

### Step 3: 验证帧接收
每秒应该看到:
```
📹 CameraManager: Received 30 back camera frames
📹 CameraManager: Received 30 front camera frames
```

### Step 4: 测试拍照
点击拍照后应该看到:
```
📸 CameraManager: Frame status - Back: true (count: 120), Front: true (count: 120)
📸 CameraManager: Back image: true, Front image: true
```

## 如果仍然失败

### 场景 A: Delegate 从未被调用
```
❌ 1秒后没有看到 "🎯 captureOutput DELEGATE CALLED!"
```
**原因**: Outputs 没有正确添加或 delegate 设置失败
**检查**: 
- 是否看到 "✅ Back/Front camera video data output added"
- 是否看到 "delegate: true"

### 场景 B: Delegate 被调用但没有帧
```
✅ 看到 "🎯 captureOutput DELEGATE CALLED!"
❌ 但没有看到 "📹 Received XX frames"
```
**原因**: Connection 的 inputPort 获取失败
**检查**: 是否看到 "⚠️ Could not determine camera position"

### 场景 C: 有帧但拍照失败
```
✅ 看到 "📹 Received XX frames"
❌ 拍照时 "Frame status - Back: false"
```
**原因**: 帧锁问题或帧没有被存储
**需要**: 检查 frameLock 逻辑

## 已修改的文件

`/dualCamera/Managers/CameraManager.swift`
- 创建独立的队列: `backVideoDataQueue`, `frontVideoDataQueue`
- 添加 delegate 首次调用日志
- 添加会话状态和 outputs 验证日志
- 在拍照方法中输出帧计数器
