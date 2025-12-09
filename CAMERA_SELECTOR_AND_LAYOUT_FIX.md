# 摄像头选择器与按钮布局优化 - December 11, 2025

## 新增功能

### 1. 摄像头选择器 (Camera Selector) ✨

**功能描述**:
- 新增摄像头选择菜单，显示设备上所有可用摄像头的实时预览
- 自动检测前置和后置摄像头（根据不同机型）
- 每个摄像头显示：
  - 实时预览画面
  - 摄像头名称（中文）
  - 焦距信息（如 "0.5x (13mm)", "1x (26mm)", "2x (52mm)"）
  - 摄像头类型（Wide, Ultra Wide, Telephoto 等）
  - 前后摄标识

**使用方式**:
- 点击摄像头图标按钮（`camera.metering.multispot`）打开菜单
- 类似 Gallery 的弹出式界面
- 滚动查看所有可用摄像头
- 每个摄像头都显示实时预览

**支持的摄像头类型**:
- 后置超广角 (Ultra Wide) - 0.5x (13mm)
- 后置广角 (Wide) - 1x (26mm)
- 后置长焦 (Telephoto) - 2x (52mm) / 3x (77mm)
- 前置摄像头 / 原深感摄像头
- 双摄 / 三摄系统

### 2. 横屏布局优化 🔧

**问题**: Capture 按钮位置和之前不一样

**解决方案**:
```
之前的布局:
┌─────────────────────────────────────┐
│                                     │
│                                     │  Spacer (顶部留空)
│                              [Cap] │  Capture 按钮
│                         [F][M][G]  │  三个辅助按钮
│                              空白   │  Spacer (底部留空)
└─────────────────────────────────────┘

新的布局:
┌─────────────────────────────────────┐
│                              [Cam] │  摄像头选择按钮 (顶部)
│                                     │
│                                     │  Spacer (垂直居中)
│                              [Cap] │  Capture 按钮 (完全居中)
│                                     │
│                                     │  Spacer (垂直居中)
│                         [F][M][G]  │  三个辅助按钮 (底部)
└─────────────────────────────────────┘
```

**关键改进**:
- Capture 按钮现在真正垂直居中（两边 `Spacer()` 相等）
- 摄像头选择按钮在顶部
- 辅助按钮在底部
- 布局更加平衡和对称

### 3. 竖屏布局优化 🔧

**新增**:
- 摄像头选择按钮在右上角
- 主要按钮仍在底部

```
竖屏布局:
┌─────────────────────┐
│                [Cam]│  摄像头选择按钮 (右上角)
│                     │
│                     │
│                     │
│                     │
│                     │
│                     │
│                     │
│    [G] [Cap] [F]   │  底部按钮行 1 (Gallery, Capture, Flash)
│            [M]     │  底部按钮行 2 (Mode)
└─────────────────────┘

注: [M] 在实际实现中是和其他按钮在同一行
```

实际底部布局:
```
[Gallery]  [Capture]  [Flash]  [Mode]
  (50px)     (80px)    (60px)  (60px)
```

## 新增文件

### 1. `CameraDeviceInfo.swift` ✨
**功能**: 摄像头设备信息结构和检测器

**主要类型**:
```swift
struct CameraDeviceInfo: Identifiable, Hashable {
    let id: String
    let device: AVCaptureDevice
    let position: AVCaptureDevice.Position  // .back / .front
    let deviceType: AVCaptureDevice.DeviceType
    let displayName: String  // "后置 超广角"
    let focalLength: String  // "0.5x (13mm)"
    
    var typeName: String  // "Ultra Wide"
    var positionName: String  // "后摄"
}
```

**检测器**:
```swift
class CameraDeviceDetector {
    static func getAllAvailableCameras() -> [CameraDeviceInfo]
}
```

**检测方式**:
1. 遍历所有可能的 `AVCaptureDevice.DeviceType`
2. 检查前置和后置两个位置
3. 使用 `AVCaptureDevice.DiscoverySession` 确保全面检测
4. 去重（避免同一摄像头被重复检测）
5. 排序：后置优先，同位置按焦距排序

### 2. `CameraSelectorView.swift` ✨
**功能**: 摄像头选择器 UI

**主要组件**:

#### `CameraSelectorView`
- 主视图，使用 `NavigationView`
- 显示所有摄像头的滚动列表
- 分组显示：后置摄像头 / 前置摄像头
- 导航栏带"完成"按钮

#### `CameraPreviewCard`
- 单个摄像头卡片
- 实时预览画面（200px 高度，4:3 比例）
- 摄像头信息文字
- 圆角卡片设计，半透明背景

#### `CameraPreviewLayer` (UIViewRepresentable)
- 将 `AVCaptureVideoPreviewLayer` 包装为 SwiftUI 视图
- 自动适应视图大小
- 使用 Coordinator 管理 layer

#### `CameraSelectorViewModel`
- 管理摄像头检测
- 为每个摄像头创建独立的预览 session
- 自动启动/停止所有预览
- 内存管理：视图消失时停止所有 session

**工作流程**:
```
1. onAppear → detectCameras()
2. 检测所有摄像头 (后台线程)
3. 为每个摄像头创建 AVCaptureSession
4. 启动所有预览 session
5. 更新 UI 显示实时画面
6. onDisappear → stopAllPreviews()
```

## 修改的文件

### 1. `ContentView.swift` 🔧

**新增状态**:
```swift
@State private var showCameraSelector = false
```

**新增 sheet**:
```swift
.sheet(isPresented: $showCameraSelector) {
    CameraSelectorView()
}
```

**横屏布局修改**:
```swift
VStack(spacing: 0) {
    // 顶部: 摄像头选择按钮
    if viewModel.uiVisibilityManager.isUIVisible {
        VStack(spacing: 20) {
            Button(action: { ... }) {
                Image(systemName: "camera.metering.multispot")
            }
        }
        .padding(.top, 60)
    }
    
    Spacer()  // ← 新增，让 Capture 居中
    
    // 中间: Capture 按钮 (垂直居中)
    Button(action: { ... }) { ... }
    
    Spacer()  // ← 新增，让 Capture 居中
    
    // 底部: 三个辅助按钮
    if viewModel.uiVisibilityManager.isUIVisible {
        HStack(spacing: 20) {
            // Flash, Mode, Gallery
        }
        .padding(.bottom, 40)
    } else {
        Spacer().frame(height: 40)  // 保持一致的底部间距
    }
}
```

**关键改进**:
- 使用两个 `Spacer()` 让 Capture 按钮真正居中
- 当 `isUIVisible = false` 时，用固定高度 frame 代替按钮组，保持布局稳定

**竖屏布局**:
- 传递 `onOpenCameraSelector` 回调给 `CameraControlButtons`

### 2. `CameraControlButtons.swift` 🔧

**新增参数**:
```swift
let onOpenCameraSelector: () -> Void
```

**横屏布局**:
- 摄像头选择按钮在顶部（可隐藏）

**竖屏布局**:
```swift
VStack {
    // 顶部: 摄像头选择按钮
    if isUIVisible {
        HStack {
            Spacer()
            Button(action: {
                onInteraction()
                onOpenCameraSelector()
            }) {
                Image(systemName: "camera.metering.multispot")
            }
            .padding(.trailing, 20)
            .padding(.top, 60)
        }
    }
    
    Spacer()
    
    // 底部: 主要按钮
    HStack(spacing: 30) {
        // Gallery, Capture, Flash, Mode
    }
    .padding(.bottom, 40)
}
```

**更新 Previews**:
- 所有 Preview 都添加 `onOpenCameraSelector: {}` 参数

## 技术细节

### 摄像头检测算法

**1. 设备类型枚举**:
```swift
let deviceTypes: [AVCaptureDevice.DeviceType] = [
    .builtInWideAngleCamera,      // 标准广角
    .builtInUltraWideCamera,      // 超广角
    .builtInTelephotoCamera,      // 长焦
    .builtInDualCamera,           // 双摄
    .builtInDualWideCamera,       // 双广角
    .builtInTripleCamera,         // 三摄
    .builtInTrueDepthCamera       // 原深感（前置）
]
```

**2. 去重逻辑**:
```swift
if !cameras.contains(where: { $0.id == info.id }) {
    cameras.append(info)
}
```
- 使用 `device.uniqueID` 作为唯一标识
- 避免同一摄像头通过不同 API 被重复检测

**3. 焦距估算**:
```swift
private static func getFocalLength(for device: AVCaptureDevice) -> String {
    let minZoom = device.minAvailableVideoZoomFactor
    
    if minZoom <= 0.6 {
        return "0.5x (13mm)"
    } else if minZoom <= 0.8 {
        return "0.7x (18mm)"
    } else if minZoom <= 1.2 {
        return "1x (26mm)"
    }
    // ...
}
```
- 基于 `minAvailableVideoZoomFactor` 推断焦距
- 提供等效 35mm 焦距（mm）

### 预览 Session 管理

**内存优化**:
```swift
func stopAllPreviews() {
    sessionQueue.async {
        for (id, session) in self.previewSessions {
            if session.isRunning {
                session.stopRunning()
            }
        }
        DispatchQueue.main.async {
            self.previewSessions.removeAll()
        }
    }
}
```

**生命周期**:
- `onAppear`: 检测并启动所有摄像头预览
- `onDisappear`: 停止所有预览，释放资源
- `deinit`: 确保清理

### UI 布局技巧

**1. Spacer 居中法**:
```swift
Spacer()
Button { ... }  // 垂直居中
Spacer()
```

**2. 条件渲染保持布局**:
```swift
if isUIVisible {
    HStack { /* 按钮 */ }
} else {
    Spacer().frame(height: 40)  // 占位，保持布局
}
```

**3. GeometryReader 检测方向**:
```swift
GeometryReader { geometry in
    let isLandscape = geometry.size.width > geometry.size.height
    // ...
}
```

## 按钮图标

**摄像头选择器按钮**:
```swift
Image(systemName: "camera.metering.multispot")
```
- SF Symbol: `camera.metering.multispot`
- 含义: 测光模式（多点），象征多个摄像头
- 大小: 24-26pt
- 颜色: 白色

## 用户体验流程

### 打开摄像头选择器

**竖屏**:
1. 点击右上角摄像头图标
2. 弹出摄像头选择菜单（全屏 sheet）
3. 查看所有摄像头实时预览
4. 点击"完成"关闭

**横屏**:
1. 点击右侧顶部摄像头图标
2. 其余流程相同

### Camera 停止状态下

**行为**:
- 点击摄像头选择按钮
- 自动调用 `ensureCameraActiveAndExecute`
- Camera 先恢复运行
- 等待 0.3 秒
- 打开摄像头选择菜单

**Console 日志**:
```
🖐️ ContentView: Camera selector button tapped
🔄 CameraViewModel: ensureCameraActiveAndExecute() called
🔄 CameraViewModel: Camera is stopped, restarting...
🎥 CameraManager: setupSession() called
📷 CameraSelectorViewModel: Detecting cameras...
📷 CameraDeviceDetector: Detecting all available cameras...
   ✅ Found: 后置 超广角 (0.5x (13mm))
   ✅ Found: 后置 广角 (1x (26mm))
   ✅ Found: 后置 长焦 (2x (52mm))
   ✅ Found: 前置 原深感 (1x (前置))
📷 CameraSelectorViewModel: Found 3 back cameras, 1 front cameras
```

## 测试场景

### 测试 1: 摄像头检测 ✅
1. 打开摄像头选择器
2. **预期**（iPhone 14 Pro）:
   - 后置摄像头 3 个：超广角、广角、长焦
   - 前置摄像头 1 个：原深感
3. **预期**（iPhone 11）:
   - 后置摄像头 2 个：超广角、广角
   - 前置摄像头 1 个：TrueDepth
4. **预期**（iPhone SE）:
   - 后置摄像头 1 个：广角
   - 前置摄像头 1 个：前置

### 测试 2: 实时预览 ✅
1. 打开摄像头选择器
2. **预期**: 
   - 每个摄像头显示实时画面
   - 画面流畅，无卡顿
   - 信息标签正确（名称、焦距、类型）

### 测试 3: 横屏 Capture 按钮位置 ✅
1. 旋转到横屏
2. **预期**: Capture 按钮完全垂直居中
3. 等待 UI 自动隐藏
4. **预期**: 
   - 摄像头选择按钮消失
   - 辅助按钮消失
   - Capture 按钮仍然居中
5. **对比之前**: 位置应该和修复前一致

### 测试 4: 竖屏摄像头按钮 ✅
1. 竖屏模式
2. **预期**: 右上角显示摄像头图标
3. 等待 UI 隐藏
4. **预期**: 摄像头图标消失
5. 点击屏幕
6. **预期**: 摄像头图标重新出现

### 测试 5: Camera 停止状态下打开选择器 ✅
1. 双击停止 camera（黑屏）
2. 单击恢复 UI
3. 点击摄像头选择按钮
4. **预期**:
   - Camera 自动恢复
   - 0.3 秒后打开选择器
   - 所有摄像头预览正常

### 测试 6: 内存管理 ✅
1. 打开摄像头选择器
2. 观察所有预览启动
3. 点击"完成"关闭
4. **预期**:
   - Console 显示 "Stopping all previews..."
   - 所有 session 停止
   - 内存释放
5. 再次打开
6. **预期**: 重新检测和启动预览

## 代码审查检查清单

- [x] 横屏 Capture 按钮完全垂直居中
- [x] 竖屏摄像头选择按钮在右上角
- [x] 摄像头检测算法完整
- [x] 去重逻辑正确
- [x] 焦距估算合理
- [x] 实时预览功能正常
- [x] 内存管理安全（启动/停止 session）
- [x] UI 响应自动恢复 camera
- [x] 所有 Preview 更新
- [x] Console 日志完整
- [x] 用户体验流畅

## 未来可能的增强

### 1. 摄像头切换功能 🔮
```swift
struct CameraPreviewCard: View {
    // ...
    .onTapGesture {
        // 点击卡片切换到该摄像头
        viewModel.switchToCamera(camera)
        dismiss()
    }
}
```

### 2. 显示当前使用的摄像头 🔮
```swift
Image(systemName: "checkmark.circle.fill")
    .foregroundColor(.blue)
    .opacity(isCurrentCamera ? 1 : 0)
```

### 3. 摄像头规格信息 🔮
- 最大分辨率
- 支持的帧率
- 视频稳定性
- HDR 支持

### 4. 多摄像头同时录制预览 🔮
- 在选择器中同时显示多个摄像头
- 实时预览双摄/三摄同时录制的效果

## 总结

✅ **横屏 Capture 按钮位置已优化**:
- 使用双 Spacer 实现完全垂直居中
- 布局更加平衡

✅ **摄像头选择器功能完整**:
- 自动检测所有可用摄像头
- 实时预览画面
- 详细信息标签（名称、焦距、类型）
- 分组显示（后置/前置）
- 内存管理安全

✅ **UI 集成完美**:
- 竖屏: 右上角按钮
- 横屏: 右侧顶部按钮
- 自动隐藏/显示
- 自动恢复 camera

关键成就是创建了一个专业的摄像头管理界面，让用户可以查看和了解设备上所有的摄像头硬件。🎉
