# 摄像头选择器崩溃修复 - December 11, 2025

## 问题描述

**崩溃信息**: `Thread 1: signal SIGABRT`

**崩溃场景**:
1. 用户双击屏幕冻结画面（停止接收 camera 数据）
2. 点击摄像头选择按钮
3. 摄像头选择器尝试为每个摄像头创建新的 `AVCaptureSession`
4. **崩溃** - SIGABRT 错误

## 根本原因分析

### 问题 1: 多个 AVCaptureSession 冲突 ❌

**原因**:
- 主应用的 `AVCaptureMultiCamSession` 可能仍在占用摄像头资源
- 摄像头选择器试图为每个摄像头创建新的 `AVCaptureSession`
- 多个 session 同时访问同一摄像头导致资源冲突
- iOS 限制了同时运行的 capture session 数量

**技术细节**:
```swift
// 主应用的 session (可能在后台运行)
let mainSession = AVCaptureMultiCamSession()

// 选择器试图创建多个新 session
for camera in cameras {
    let session = AVCaptureSession()  // ❌ 冲突！
    session.startRunning()
}
```

### 问题 2: 画面冻结状态下的逻辑错误 ❌

**原来的逻辑**:
```swift
Button("打开摄像头选择器") {
    viewModel.ensureCameraActiveAndExecute {
        showCameraSelector = true
    }
}
```

**问题**:
1. 即使画面冻结，也会尝试恢复主 camera
2. 主 camera 恢复后，选择器又创建新 session
3. 多个 session 同时运行 → 崩溃

### 问题 3: 不必要的摄像头恢复 ❌

用户的意图：
- **画面冻结** = 不想看到实时预览
- **查看摄像头选择器** = 只是想查看设备上有哪些摄像头

不应该：
- 强制恢复主 camera
- 在选择器中启动所有 camera

## 解决方案

### 修复 1: 添加 `isCameraActive` 参数 ✅

**CameraSelectorView.swift**:
```swift
struct CameraSelectorView: View {
    let isCameraActive: Bool  // ✅ 传入参数：摄像头是否激活
    
    var body: some View {
        // ...
        .onAppear {
            viewModel.detectCameras(startPreviews: isCameraActive)  // ✅
        }
    }
}
```

**行为**:
- `isCameraActive = true`: 启动所有摄像头预览（正常状态）
- `isCameraActive = false`: 只检测摄像头，不启动预览（冻结状态）

### 修复 2: 条件渲染预览 ✅

**CameraPreviewCard.swift**:
```swift
struct CameraPreviewCard: View {
    let showPlaceholder: Bool  // ✅ 是否显示占位符
    
    var body: some View {
        ZStack {
            if showPlaceholder {
                // 显示黑屏 + 图标
                VStack {
                    Image(systemName: "video.slash")
                    Text("预览不可用")
                }
            } else if let session = previewSession {
                // 显示实时预览
                CameraPreviewLayer(session: session)
            }
        }
    }
}
```

**效果**:
- **Camera 激活**: 显示实时预览
- **Camera 冻结**: 显示黑屏 + "预览不可用" 提示

### 修复 3: ViewModel 条件启动预览 ✅

**CameraSelectorViewModel.swift**:
```swift
func detectCameras(startPreviews: Bool = true) {
    // 检测所有摄像头
    let allCameras = CameraDeviceDetector.getAllAvailableCameras()
    
    // 只在 startPreviews = true 时启动预览
    if startPreviews {
        print("📷 Starting previews for all cameras")
        self.startPreviewsForAllCameras()
    } else {
        print("📷 Skipping previews (camera inactive)")
    }
}
```

### 修复 4: ContentView 传递状态 ✅

**ContentView.swift**:
```swift
.sheet(isPresented: $showCameraSelector) {
    CameraSelectorView(
        isCameraActive: viewModel.uiVisibilityManager.isPreviewVisible  // ✅
    )
}
```

**逻辑**:
- `isPreviewVisible = true`: 主 camera 运行中 → 启动预览
- `isPreviewVisible = false`: 主 camera 已冻结 → 不启动预览

### 修复 5: 移除自动恢复 Camera ✅

**之前**:
```swift
Button("摄像头选择器") {
    viewModel.ensureCameraActiveAndExecute {  // ❌ 会恢复 camera
        showCameraSelector = true
    }
}
```

**现在**:
```swift
Button("摄像头选择器") {
    showCameraSelector = true  // ✅ 直接打开，不恢复 camera
}
```

**原因**:
- 摄像头选择器不需要主 camera 运行
- 用户只是想查看设备摄像头信息
- 避免不必要的 session 启动

### 修复 6: 添加警告提示 ✅

**CameraSelectorView.swift**:
```swift
if !isCameraActive {
    VStack {
        Image(systemName: "video.slash.fill")
        Text("摄像头已暂停")
        Text("当前画面已冻结，预览不可用")
    }
    .background(Color.yellow.opacity(0.2))
}
```

**效果**:
- 画面冻结时显示黄色警告横幅
- 明确告知用户为什么没有预览

## 修改的文件

### 1. CameraSelectorView.swift 🔧

**新增参数**:
```swift
let isCameraActive: Bool
```

**更新 onAppear**:
```swift
.onAppear {
    viewModel.detectCameras(startPreviews: isCameraActive)
}
```

**新增警告横幅**:
```swift
if !isCameraActive {
    VStack {
        Image(systemName: "video.slash.fill")
        Text("摄像头已暂停")
    }
}
```

**更新卡片传值**:
```swift
CameraPreviewCard(
    camera: camera,
    previewSession: isCameraActive ? viewModel.getPreviewSession(for: camera) : nil,
    showPlaceholder: !isCameraActive
)
```

### 2. CameraPreviewCard 🔧

**新增参数**:
```swift
let showPlaceholder: Bool
```

**条件渲染**:
```swift
if showPlaceholder {
    // 黑屏 + 图标
} else if let session = previewSession {
    // 实时预览
} else {
    // 加载中
}
```

### 3. CameraSelectorViewModel 🔧

**更新 detectCameras**:
```swift
func detectCameras(startPreviews: Bool = true) {
    // ...
    if startPreviews {
        self.startPreviewsForAllCameras()
    } else {
        print("📷 Skipping previews (camera inactive)")
    }
}
```

### 4. ContentView.swift 🔧

**传递状态**:
```swift
.sheet(isPresented: $showCameraSelector) {
    CameraSelectorView(isCameraActive: viewModel.uiVisibilityManager.isPreviewVisible)
}
```

**移除自动恢复**:
```swift
// 横屏
Button(action: { 
    showCameraSelector = true  // ✅ 直接打开
})

// 竖屏
onOpenCameraSelector: {
    showCameraSelector = true  // ✅ 直接打开
}
```

### 5. CameraControlButtons.swift 🔧

**移除 onInteraction 调用**:
```swift
Button(action: {
    // 不调用 onInteraction，直接打开选择器
    onOpenCameraSelector()
})
```

## 行为对比

### 之前的行为 ❌

**场景**: 画面冻结，点击摄像头选择按钮

1. 调用 `ensureCameraActiveAndExecute`
2. 主 camera 恢复运行
3. 0.3 秒后打开选择器
4. 选择器为每个摄像头创建新 session
5. 多个 session 同时运行
6. **崩溃** - SIGABRT

### 现在的行为 ✅

**场景**: 画面冻结，点击摄像头选择按钮

1. 直接打开选择器
2. 传入 `isCameraActive = false`
3. ViewModel 检测摄像头但**不启动预览**
4. 显示所有摄像头信息（名称、焦距、类型）
5. 预览区域显示黑屏 + "预览不可用"
6. **正常运行**，无崩溃

## UI 效果

### Camera 激活状态

```
┌──────────────────────────┐
│   选择摄像头          [完成]│
├──────────────────────────┤
│                          │
│  后置摄像头              │
│                          │
│  ┌────────────────────┐  │
│  │ [实时预览画面]     │  │
│  │                    │  │
│  └────────────────────┘  │
│  后置 超广角              │
│  0.5x (13mm)             │
│  Ultra Wide              │
│                          │
└──────────────────────────┘
```

### Camera 冻结状态

```
┌──────────────────────────┐
│   选择摄像头          [完成]│
├──────────────────────────┤
│  ⚠️ 摄像头已暂停          │
│  当前画面已冻结，预览不可用│
│                          │
│  后置摄像头              │
│                          │
│  ┌────────────────────┐  │
│  │    🚫 video.slash  │  │
│  │    预览不可用      │  │
│  └────────────────────┘  │
│  后置 超广角              │
│  0.5x (13mm)             │
│  Ultra Wide              │
│                          │
└──────────────────────────┘
```

## Console 日志对比

### Camera 激活时

```
🖐️ ContentView: Camera selector button tapped
📷 CameraSelectorViewModel: Detecting cameras... (startPreviews: true)
📷 CameraDeviceDetector: Detecting all available cameras...
   ✅ Found: 后置 超广角 (0.5x (13mm))
   ✅ Found: 后置 广角 (1x (26mm))
   ✅ Found: 后置 长焦 (2x (52mm))
   ✅ Found: 前置 原深感 (1x (前置))
📷 CameraSelectorViewModel: Found 3 back cameras, 1 front cameras
📷 CameraSelectorViewModel: Starting previews for all cameras
📷 Starting preview for: 后置 超广角
✅ Preview started for: 后置 超广角
📷 Starting preview for: 后置 广角
✅ Preview started for: 后置 广角
```

### Camera 冻结时

```
🖐️ ContentView: Camera selector button tapped
📷 CameraSelectorViewModel: Detecting cameras... (startPreviews: false)
📷 CameraDeviceDetector: Detecting all available cameras...
   ✅ Found: 后置 超广角 (0.5x (13mm))
   ✅ Found: 后置 广角 (1x (26mm))
   ✅ Found: 后置 长焦 (2x (52mm))
   ✅ Found: 前置 原深感 (1x (前置))
📷 CameraSelectorViewModel: Found 3 back cameras, 1 front cameras
📷 CameraSelectorViewModel: Skipping previews (camera inactive)
```

## 测试场景

### 测试 1: Camera 激活状态下打开选择器 ✅
1. 启动 app（camera 运行中）
2. 点击摄像头选择按钮
3. **预期**: 
   - 选择器打开
   - 显示所有摄像头的实时预览
   - 画面流畅，无卡顿
   - 无崩溃

### 测试 2: Camera 冻结状态下打开选择器 ✅
1. 启动 app
2. 双击屏幕冻结画面
3. 单击显示 UI
4. 点击摄像头选择按钮
5. **预期**:
   - 选择器打开
   - 显示警告横幅："摄像头已暂停"
   - 所有预览区域显示黑屏 + "预览不可用"
   - 摄像头信息正常显示（名称、焦距、类型）
   - **无崩溃**

### 测试 3: 多次开关选择器 ✅
1. 打开选择器 → 关闭
2. 双击冻结画面
3. 打开选择器 → 关闭
4. 单击恢复画面
5. 打开选择器 → 关闭
6. **预期**: 所有操作流畅，无崩溃

### 测试 4: 长时间停留在选择器 ✅
1. 打开选择器（camera 激活）
2. 停留 2 分钟
3. **预期**:
   - 预览持续运行
   - 无内存泄漏
   - 点击"完成"正常关闭
   - 所有 session 正确停止

### 测试 5: 选择器中切换方向 ✅
1. 打开选择器（竖屏）
2. 旋转到横屏
3. 再旋转回竖屏
4. **预期**:
   - 布局正确适应
   - 预览继续运行
   - 无崩溃

## 技术要点

### AVCaptureSession 限制

**iOS 限制**:
- 同时运行的 session 数量有限
- 同一摄像头不能被多个 session 同时占用
- `AVCaptureMultiCamSession` 允许多摄像头，但仍有资源限制

**最佳实践**:
- 只在需要时启动 session
- 不使用时立即停止
- 避免创建不必要的 session

### 条件启动的好处

**性能**:
- 减少 CPU/GPU 使用
- 节省电量
- 降低内存占用

**稳定性**:
- 避免 session 冲突
- 减少崩溃风险
- 更好的资源管理

## 代码审查检查清单

- [x] `CameraSelectorView` 接收 `isCameraActive` 参数
- [x] `CameraPreviewCard` 接收 `showPlaceholder` 参数
- [x] `detectCameras` 方法支持 `startPreviews` 参数
- [x] ContentView 传递正确的 `isPreviewVisible` 状态
- [x] 移除摄像头选择器的自动恢复逻辑
- [x] 添加警告横幅提示用户
- [x] 条件渲染预览或占位符
- [x] Console 日志清晰
- [x] Preview 更新
- [x] 无编译错误

## 总结

✅ **崩溃已修复**:
- 画面冻结时不再启动摄像头预览
- 避免了多个 AVCaptureSession 冲突
- SIGABRT 错误不再出现

✅ **用户体验改进**:
- 明确的警告提示
- 黑屏占位符清晰易懂
- 摄像头信息仍然可见

✅ **代码质量提升**:
- 条件启动预览
- 更好的资源管理
- 清晰的状态传递

关键改进是理解了用户意图：**查看摄像头列表 ≠ 需要实时预览**。画面冻结时，用户只想看到设备上有哪些摄像头，不需要实时画面。这样避免了不必要的资源占用和 session 冲突。🎉
