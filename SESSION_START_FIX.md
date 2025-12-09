# 会话启动失败修复

## 问题诊断

从控制台输出看到关键证据:
```
🔍 CameraManager: Session isRunning = false
🔍 CameraManager: Session isInterrupted = false
📸 CameraManager: Frame status - Back: false (count: 0), Front: false (count: 0)
```

**根本问题**: `AVCaptureMultiCamSession.startRunning()` 被调用,但会话**没有真正启动**。

## 可能的原因

1. **权限问题**: 相机权限未授予
2. **硬件冲突**: 另一个应用正在使用相机
3. **配置错误**: Session 配置有问题导致无法启动
4. **线程问题**: 在错误的队列启动会话
5. **设备不支持**: 设备不支持多相机

## 修复内容

### 1. 改进会话启动逻辑

**问题**: 异步检查会话状态,时间不准确

**修复**: 在 `startRunning()` 后**立即同步检查**状态:

```swift
newSession.startRunning()

// 立即检查 (同一个队列,同步)
let isRunning = newSession.isRunning
let isInterrupted = newSession.isInterrupted

print("🔍 CameraManager: Session isRunning = \(isRunning) (checked immediately)")

if !isRunning {
    print("❌ CameraManager: WARNING - Session NOT running!")
    print("   Possible reasons:")
    print("   - Camera permission not granted")
    print("   - Configuration error")
    print("   - Hardware resource conflict")
}
```

### 2. 添加会话错误监听

添加了3个通知观察者来捕获运行时错误:

```swift
// Runtime error
NotificationCenter.default.addObserver(
    self,
    selector: #selector(sessionRuntimeError),
    name: .AVCaptureSessionRuntimeError,
    object: newSession
)

// Interruption
NotificationCenter.default.addObserver(
    self,
    selector: #selector(sessionWasInterrupted),
    name: .AVCaptureSessionWasInterrupted,
    object: newSession
)

// Interruption ended
NotificationCenter.default.addObserver(
    self,
    selector: #selector(sessionInterruptionEnded),
    name: .AVCaptureSessionInterruptionEnded,
    object: newSession
)
```

### 3. 添加测试模式

为了**先验证UI是否正常工作**,添加了测试模式:

```swift
// 在 CameraViewModel 中
private let enableTestMode = false  // 改为 true 启用测试模式

// 在 CameraManager 中
func startTestMode() {
    // 生成蓝色/绿色测试图片
    let backTestImage = createTestImage(color: .blue, text: "BACK CAMERA")
    let frontTestImage = createTestImage(color: .green, text: "FRONT CAMERA")
    
    // 30fps 定时器更新
    Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { ... }
}
```

**用途**: 
- 测试预览UI是否能正常显示图像
- 排除相机硬件问题
- 验证图像流程是否正确

### 4. 修复会话赋值逻辑

**问题**: 异步赋值 `self.session`,可能导致预览层找不到会话

**修复**: 使用 `DispatchQueue.main.sync` 同步赋值:

```swift
DispatchQueue.main.sync {
    self.session = newSession
}
```

## 测试步骤

### 阶段 1: 使用测试模式验证UI

1. 在 `CameraViewModel.swift` 第27行,设置:
   ```swift
   private let enableTestMode = true
   ```

2. 运行应用

3. **预期结果**:
   - 应该立即看到蓝色(后置)和绿色(前置)测试图案
   - 证明预览UI工作正常
   - 可以点击拍照(会保存测试图片)

4. **如果测试模式也不显示**: 说明是预览UI的问题,不是相机问题

### 阶段 2: 诊断真实相机会话

将 `enableTestMode` 改回 `false`,运行应用,检查控制台:

#### 检查点 1: 权限
```
✅ 应该看到: CameraViewModel: Camera authorized
❌ 如果看到: Camera access DENIED
    → 解决: 在设置中授予相机权限
```

#### 检查点 2: 多相机支持
```
✅ 应该看到: Multi-cam IS supported
❌ 如果看到: Multi-cam NOT supported
    → 原因: 设备不支持 (需要 iPhone XS 或更新)
```

#### 检查点 3: 会话启动
```
✅ 应该看到: Session isRunning = true (checked immediately)
❌ 如果看到: Session isRunning = false
    → 检查下方的错误日志
```

#### 检查点 4: Delegate 回调
```
✅ 应该在1秒内看到: 🎯 captureOutput DELEGATE CALLED!
❌ 如果没有看到:
    → 检查 outputs: "Session has 2 outputs"
    → 检查 delegate: "delegate: true"
```

#### 检查点 5: 帧接收
```
✅ 每秒应该看到: 📹 Received 30/60/90... frames
❌ 如果没有帧:
    → 检查是否有 "⚠️ Could not determine camera position"
```

## 常见问题排查

### 问题 A: Session isRunning = false

可能原因:
1. **权限未授予**: 检查设置 → 隐私 → 相机
2. **其他应用占用**: 关闭所有相机应用,重启设备
3. **配置错误**: 查看 runtime error 通知输出

### 问题 B: 有 outputs 但无 delegate 回调

可能原因:
1. **Delegate 设置失败**: 检查 "delegate: false"
2. **队列问题**: 已修复(独立队列)

### 问题 C: 有 delegate 回调但无帧

可能原因:
1. **Connection 问题**: 检查 "Could not determine camera position"
2. **帧过滤逻辑错误**: delegate 被调用但帧被过滤掉

## 已修改的文件

1. `/dualCamera/Managers/CameraManager.swift`
   - 添加会话错误通知观察者
   - 同步检查会话运行状态
   - 添加测试模式 `startTestMode()`
   - 同步赋值 `self.session`

2. `/dualCamera/Modesl/CameraViewModel.swift`
   - 添加 `enableTestMode` 开关
   - 支持测试模式初始化

## 下一步

1. **先启用测试模式**: 验证UI和预览流程正常
2. **禁用测试模式**: 诊断真实相机会话问题
3. **根据日志**: 精确定位失败点
4. **修复会话启动**: 确保 `isRunning = true`
5. **验证帧流入**: 确保 delegate 回调和帧计数增加
