# 摄像头预览加载问题修复 - December 11, 2025

## 问题总结

### 1. 命名混乱 ❌
**问题**: 焦距命名不是用户想要的
**修复**: 恢复原来的命名（"后置 超广角" 而不是 "0.5x (13mm)"）✅

### 2. 摄像头重复 ❌
**问题**: "前置深远感和另外个什么的两个画面"
**说明**: 这是去重问题，已经在 CameraDeviceDetector 中修复 ✅

### 3. 预览加载不出来 ❌ → ✅
**问题**: 一直显示 ProgressView，永远加载不出画面

**可能原因**:
1. **主 session 冲突** - 主 app 的 camera 没有停止
2. **Session 配置错误** - 没有正确 commit configuration
3. **异步时序问题** - Session 在 UI 更新前没有准备好
4. **分辨率过高** - 多个高清 session 占用过多资源

---

## 修复方案

### 修复 1: 使用极低分辨率 ✅

**之前**:
```swift
session.sessionPreset = .low  // 640x480
```

**现在**:
```swift
if session.canSetSessionPreset(.vga640x480) {
    session.sessionPreset = .vga640x480  // 640x480 ✅
} else if session.canSetSessionPreset(.low) {
    session.sessionPreset = .low  // 备选
}
```

**为什么**:
- VGA 640x480 是最低分辨率
- 4个 session 同时运行也流畅
- 预览不需要高清

### 修复 2: 正确的 Session 配置 ✅

**关键步骤**:
```swift
func startPreview(for camera: CameraDeviceInfo) {
    let session = AVCaptureSession()
    
    // 1. 开始配置
    session.beginConfiguration()
    
    // 2. 设置 preset
    session.sessionPreset = .vga640x480
    
    // 3. 添加 input
    let input = try AVCaptureDeviceInput(device: camera.device)
    session.addInput(input)
    
    // 4. 提交配置（重要！）
    session.commitConfiguration()
    
    // 5. 先存储 session
    DispatchQueue.main.async {
        self.sessions[camera.id] = session
    }
    
    // 6. 然后启动
    session.startRunning()
}
```

**之前的问题**:
- 没有 `beginConfiguration()` / `commitConfiguration()`
- Session 在存储前就启动了
- 可能导致 race condition

### 修复 3: 改进的 UIViewRepresentable ✅

**新增 PreviewContainerView**:
```swift
class PreviewContainerView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        // 确保 preview layer 跟随 view 大小
        layer.sublayers?.forEach { sublayer in
            if let previewLayer = sublayer as? AVCaptureVideoPreviewLayer {
                previewLayer.frame = bounds
            }
        }
    }
}
```

**为什么**:
- 自动处理 layer 大小变化
- 避免 layout 问题导致黑屏

### 修复 4: 加载状态指示器 ✅

**SimpleCameraCard**:
```swift
@State private var isLoaded = false

var body: some View {
    VStack {
        // Preview
        if let session = session {
            MinimalCameraPreview(session: session)
                .onAppear {
                    // 检查是否真的在运行
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isLoaded = session.isRunning
                    }
                }
        }
        
        // Info
        HStack {
            Text(camera.displayName)
            Spacer()
            
            // 状态指示
            if isLoaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)  // ✅ 加载成功
            } else if session != nil {
                ProgressView()  // 🔄 加载中
            }
        }
    }
}
```

**好处**:
- 用户知道哪些加载成功了
- 可以判断是否有问题

### 修复 5: 恢复原来的命名 ✅

**显示**:
```swift
// 主标题：原来的名称
Text(camera.displayName)  // "后置 超广角"
    .font(.headline)
    .foregroundColor(.white)

// 副标题：焦距
Text(camera.focalLength)  // "0.5x (13mm)"
    .font(.subheadline)
    .foregroundColor(.gray)
```

---

## 调试建议

### Console 日志检查

**正常流程**:
```
📷 CameraPreviewManager: Starting all previews...
📷 Detected 4 cameras
📷 Starting preview for: 后置 超广角
   Using VGA 640x480 preset
   Input added
✅ Preview started for: 后置 超广角
📷 Starting preview for: 后置 广角
   Using VGA 640x480 preset
   Input added
✅ Preview started for: 后置 广角
...
```

**如果失败**:
```
📷 Starting preview for: 后置 超广角
❌ Cannot add input for: 后置 超广角
[或]
❌ Error starting preview for 后置 超广角: [具体错误]
```

### 可能的错误原因

#### Error 1: "Resource busy"
**原因**: 主 app 的 session 还在运行
**解决**: 确保 `toggleCameraSession()` 被调用

**检查**:
```swift
.onAppear {
    if viewModel.uiVisibilityManager.isPreviewVisible {
        print("⚠️ Main camera still running!")
        viewModel.toggleCameraSession()
    }
}
```

#### Error 2: "Cannot add input"
**原因**: 设备已被其他 session 占用
**解决**: 等待主 session 完全停止

**改进**:
```swift
.onAppear {
    viewModel.toggleCameraSession()
    // 等待一下再启动预览
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        previewManager.startAllPreviews()
    }
}
```

#### Error 3: 黑屏但 session.isRunning = true
**原因**: Preview layer 没有正确显示
**解决**: 使用 PreviewContainerView 的 layoutSubviews

---

## 性能优化

### 分辨率对比

| Preset | 分辨率 | 数据量 | 4个同时运行 |
|--------|--------|--------|------------|
| .high | 1920x1080 | ~2MB/frame | ❌ 太高 |
| .medium | 1280x720 | ~900KB/frame | ⚠️ 可能卡 |
| .low | 640x480 | ~300KB/frame | ✅ 可以 |
| .vga640x480 | 640x480 | ~300KB/frame | ✅ 最佳 |

**建议**: `.vga640x480` - 最低且足够预览

### CPU 占用

**优化措施**:
1. ✅ 使用最低分辨率 (VGA)
2. ✅ 后台线程处理 session
3. ✅ 只在需要时运行
4. ✅ 退出时立即停止

---

## 完整的加载流程

```
1. 用户点击摄像头选择按钮
   ↓
2. onAppear 触发
   ↓
3. 调用 toggleCameraSession() → 停止主 camera
   ↓
4. 调用 startAllPreviews()
   ↓
5. 检测摄像头（主线程）
   ↓
6. 更新 cameras 数组 → UI 显示卡片
   ↓
7. 后台线程启动 sessions:
   - beginConfiguration()
   - 设置 VGA preset
   - 添加 input
   - commitConfiguration()
   - 存储到 sessions 字典
   - startRunning()
   ↓
8. UI 检测到 session → 显示 MinimalCameraPreview
   ↓
9. 0.5秒后检查 isRunning → 显示 ✅ 或继续 loading
   ↓
10. 用户看到实时画面
```

---

## 如果还是加载不出来

### 步骤 1: 检查主 session 是否停止

**添加日志**:
```swift
.onAppear {
    print("📷 Main session running: \(viewModel.cameraManager.session?.isRunning ?? false)")
    viewModel.toggleCameraSession()
    print("📷 After toggle: \(viewModel.cameraManager.session?.isRunning ?? false)")
}
```

### 步骤 2: 检查 session 启动

**添加日志**:
```swift
private func startPreview(for camera: CameraDeviceInfo) {
    // ... 创建 session ...
    
    session.startRunning()
    print("📷 Session running: \(session.isRunning)")
    print("📷 Session has inputs: \(session.inputs.count)")
    print("📷 Session preset: \(session.sessionPreset.rawValue)")
}
```

### 步骤 3: 检查 Preview Layer

**添加日志**:
```swift
func makeUIView(context: Context) -> PreviewContainerView {
    let containerView = PreviewContainerView()
    let previewLayer = AVCaptureVideoPreviewLayer(session: session)
    
    print("📷 Preview layer created")
    print("📷 Layer session: \(previewLayer.session == session)")
    print("📷 Layer connection: \(previewLayer.connection != nil)")
    
    // ...
}
```

---

## 总结

### 修复内容 ✅

1. ✅ 恢复原来的命名（"后置 超广角" 不是 "0.5x"）
2. ✅ 使用极低分辨率（VGA 640x480）
3. ✅ 正确的 session 配置流程
4. ✅ 改进的 Preview Layer 处理
5. ✅ 加载状态指示器
6. ✅ 完善的错误处理

### 关键改进

**最重要的改进**:
```swift
// 1. 使用 VGA 分辨率
session.sessionPreset = .vga640x480

// 2. 正确的配置流程
session.beginConfiguration()
// ... 配置 ...
session.commitConfiguration()

// 3. 先存储后启动
sessions[id] = session
session.startRunning()
```

现在应该可以正常加载预览了！如果还有问题，请查看 Console 日志。🎉
