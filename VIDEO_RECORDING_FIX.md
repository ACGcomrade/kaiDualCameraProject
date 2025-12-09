# 视频录制修复 + 方向锁定

## 问题诊断

### 视频录制崩溃
**错误**: `[AVAssetWriterInput appendSampleBuffer:] Cannot append sample buffer: Must start a session first`

**根本原因**: 
代码在调用 `startSession(atSourceTime:)` 之前就尝试追加帧,或者重复调用 `startSession`。

在帧 delegate 回调中:
```swift
// ❌ 错误逻辑
if isRecording {
    if recordingStartTime == nil {
        backVideoWriter?.startSession(atSourceTime: timestamp)  // 第一次
    }
    videoInput.append(sampleBuffer)  // ✅ 后置摄像头 OK
}

// 前置摄像头
if isRecording {
    if frontVideoWriter?.status == .writing {
        frontVideoWriter?.startSession(atSourceTime: startTime)  // ❌ 每帧都调用!
        videoInput.append(sampleBuffer)  // ❌ 崩溃!
    }
}

// 音频同理
audioWriter?.startSession(atSourceTime: startTime)  // ❌ 每帧都调用!
```

**问题**:
1. 前置摄像头和音频每次收到帧都调用 `startSession`
2. `startSession` 只能调用一次,重复调用会崩溃
3. 需要跟踪每个 writer 的会话是否已启动

## 修复方案

### 1. 添加会话启动标志

```swift
// 新增属性
private var backWriterSessionStarted = false
private var frontWriterSessionStarted = false
private var audioWriterSessionStarted = false
```

### 2. 修复帧写入逻辑

**后置摄像头**:
```swift
if isRecording, let videoInput = backVideoWriterInput, videoInput.isReadyForMoreMediaData {
    // 只启动一次会话
    if !backWriterSessionStarted, let writer = backVideoWriter, writer.status == .writing {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        writer.startSession(atSourceTime: timestamp)
        recordingStartTime = timestamp
        backWriterSessionStarted = true
        print("✅ Back video writer session started")
    }
    // 会话启动后才追加帧
    if backWriterSessionStarted {
        videoInput.append(sampleBuffer)
    }
}
```

**前置摄像头**:
```swift
if isRecording, let videoInput = frontVideoWriterInput, videoInput.isReadyForMoreMediaData {
    // 使用后置摄像头的时间戳,确保同步
    if !frontWriterSessionStarted, let writer = frontVideoWriter, writer.status == .writing, let startTime = recordingStartTime {
        writer.startSession(atSourceTime: startTime)
        frontWriterSessionStarted = true
        print("✅ Front video writer session started")
    }
    if frontWriterSessionStarted {
        videoInput.append(sampleBuffer)
    }
}
```

**音频**:
```swift
if isRecording, let audioInput = audioWriterInput, audioInput.isReadyForMoreMediaData {
    if !audioWriterSessionStarted, let writer = audioWriter, writer.status == .writing, let startTime = recordingStartTime {
        writer.startSession(atSourceTime: startTime)
        audioWriterSessionStarted = true
        print("✅ Audio writer session started")
    }
    if audioWriterSessionStarted {
        audioInput.append(sampleBuffer)
    }
}
```

### 3. 开始录制时重置标志

```swift
func startVideoRecording(...) {
    // ...
    backWriter.startWriting()
    frontWriter.startWriting()
    audioWriter.startWriting()
    
    // 重置所有标志
    self.recordingStartTime = nil
    self.backWriterSessionStarted = false
    self.frontWriterSessionStarted = false
    self.audioWriterSessionStarted = false
    // ...
}
```

## 预览方向锁定

### 需求
手机旋转时,预览不旋转,保持竖屏。其他 UI(按钮等)照常旋转。

### 实现方案

#### 1. 创建 AppDelegate
```swift
// AppDelegate.swift
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.portrait
    
    func application(_ application: UIApplication, 
                     supportedInterfaceOrientationsFor window: UIWindow?) 
                     -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}
```

#### 2. 集成到 App
```swift
// dualCameraApp.swift
@main
struct dualCameraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

#### 3. 效果
- 整个应用锁定为竖屏模式
- 预览不会旋转
- UI 按钮布局保持不变
- 用户体验更一致

**注意**: 如果将来需要横屏,可以动态修改:
```swift
AppDelegate.orientationLock = .landscape
```

## 已修改的文件

### 1. `/dualCamera/Managers/CameraManager.swift`
- 添加 `backWriterSessionStarted`, `frontWriterSessionStarted`, `audioWriterSessionStarted` 标志
- 修复后置摄像头帧写入逻辑 (第800-813行)
- 修复前置摄像头帧写入逻辑 (第824-833行)
- 修复音频帧写入逻辑 (第836-845行)
- 在 `startVideoRecording` 中重置标志 (第516-524行)

### 2. `/dualCamera/AppDelegate.swift` (新建)
- 添加方向锁定支持

### 3. `/dualCamera/dualCameraApp.swift`
- 集成 AppDelegate

## 测试步骤

### 视频录制测试

1. 运行应用
2. 点击模式切换按钮,切换到视频模式
3. 点击录制按钮(红色圆圈)
4. 应该看到:
   ```
   ✅ Back video writer session started at X.XX
   ✅ Front video writer session started at X.XX
   ✅ Audio writer session started at X.XX
   ```
5. 预览应该保持流畅,不冻结
6. 录制时间计数器增加
7. 点击停止录制
8. 应该看到:
   ```
   ✅ ViewModel: Back camera video saved
   ✅ ViewModel: Front camera video saved
   2 video(s) saved successfully!
   ```

### 方向锁定测试

1. 运行应用
2. 旋转手机
3. **预览应该保持竖屏,不旋转**
4. UI 元素保持在原位

## 预期结果

### 成功指标
- ✅ 点击录制不崩溃
- ✅ 预览保持流畅
- ✅ 录制计时器正常工作
- ✅ 停止后视频保存到相册
- ✅ 前后两个视频都成功保存
- ✅ 旋转手机时预览不旋转

### 已知限制

1. **视频和音频分离**: 当前实现保存3个独立文件:
   - `back_camera.mov` (后置视频,无音频)
   - `front_camera.mov` (前置视频,无音频)
   - `audio.m4a` (音频)
   
2. **未来改进**: 
   - 可以在后台合并音频到视频中
   - 使用 `AVMutableComposition` 组合多个视频
   - 添加画中画效果(前置 + 后置在同一视频)

## 如果仍然崩溃

### 检查点 1: Session Status
确认看到:
```
✅ Back video writer created
✅ Front video writer created
✅ Audio writer created
```

### 检查点 2: Writer Status
如果崩溃,检查:
```swift
print("Writer status: \(backVideoWriter?.status.rawValue)")
// 0 = unknown, 1 = writing, 2 = completed, 3 = failed, 4 = cancelled
```

### 检查点 3: 权限
确保麦克风权限已授予:
- 设置 → 隐私 → 麦克风 → dualCamera (开启)

### 检查点 4: 磁盘空间
确保设备有足够存储空间
