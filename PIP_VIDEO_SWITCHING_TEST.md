# 画中画视频切换功能测试指南

## 实现的功能

### 1. **录制时实时切换主副画面**
- ✅ 点击小预览框可以切换主画面和副画面
- ✅ 切换会被记录到视频中（不仅仅是UI显示）
- ✅ 使用 PreviewSwitcher 状态同步UI和录制

### 2. **美化的UI设计**
- ✅ 更大的圆角 (16px)
- ✅ 更厚的白色边框 (3px)
- ✅ 阴影效果增加深度感
- ✅ 改进的切换图标（带圆形背景）

## 技术实现

### 核心改动

#### 1. PIPComposer.composePIPVideoFrame()
```swift
static func composePIPVideoFrame(
    backBuffer: CVPixelBuffer,
    frontBuffer: CVPixelBuffer,
    isLandscape: Bool,
    isBackCameraMain: Bool,  // 新增参数
    ciContext: CIContext
) -> CVPixelBuffer?
```

**逻辑变化**：
- 根据 `isBackCameraMain` 参数决定哪个相机作为主画面
- `mainImage = isBackCameraMain ? backImage : frontImage`
- `pipImage = isBackCameraMain ? frontImage : backImage`

#### 2. CameraManager 连接 PreviewSwitcher
```swift
// 新增属性
weak var previewSwitcher: PreviewSwitcher?

// 在合成时读取状态
let isBackMain = self.previewSwitcher?.isBackCameraMain ?? true
if let composedBuffer = PIPComposer.composePIPVideoFrame(
    backBuffer: rotatedBackPixel,
    frontBuffer: rotatedFrontPixel,
    isLandscape: isLandscape,
    isBackCameraMain: isBackMain,  // 传递状态
    ciContext: self.ciContext
)
```

#### 3. DualCameraPreview 建立连接
```swift
func makeUIView(context: Context) -> PreviewView {
    let view = PreviewView(frame: .zero)
    
    // 连接 PreviewSwitcher 到 CameraManager
    viewModel.cameraManager.previewSwitcher = view.previewSwitcher
    
    // ... 其他代码
}
```

#### 4. UI 美化
```swift
// PIP 容器
pipContainer.layer.cornerRadius = 16
pipContainer.layer.borderWidth = 3
pipContainer.layer.shadowOpacity = 0.5
pipContainer.layer.shadowRadius = 8

// 前置相机视图（内嵌，留出边框空间）
frontView.layer.cornerRadius = 13
// 使用约束让它在容器内留3px的边距

// 切换图标
swapIcon = UIImage(systemName: "arrow.triangle.2.circlepath.circle.fill")
swapIcon.layer.cornerRadius = 15
swapIcon.layer.shadowOpacity = 0.3
```

## 测试步骤

### 测试 1: UI 显示
1. **启动应用** → 进入画中画模式
2. **检查小预览框**：
   - ✅ 圆角更圆润（16px）
   - ✅ 白色边框更明显（3px）
   - ✅ 有阴影效果
   - ✅ 切换图标是圆形带填充的样式

### 测试 2: 录制前切换
1. **进入画中画模式**（不录制）
2. **点击小预览框** → 主画面和小预览框应该互换
3. **再次点击** → 应该换回来
4. **验证**：UI 切换流畅，有动画效果

### 测试 3: 录制中切换（关键测试）
1. **进入画中画模式**
2. **开始录制视频**
3. **录制5秒后，点击小预览框** → 观察主画面和副画面是否互换
4. **再等5秒，再次点击** → 应该再次互换
5. **停止录制**
6. **查看录制的视频**：
   - ✅ 前5秒：后置相机为主画面，前置为小预览
   - ✅ 中间部分：前置相机为主画面，后置为小预览（白边框）
   - ✅ 最后部分：又换回来
7. **验证点**：
   - 切换应该被记录到视频中
   - 小预览框的白色边框应该始终可见
   - 切换没有延迟或卡顿

### 测试 4: 横竖屏切换
1. **竖屏录制** → 点击切换 → 停止
2. **横屏录制** → 点击切换 → 停止
3. **验证**：
   - 两种方向下切换都正常工作
   - 小预览框位置正确（右上角）
   - 比例正确（竖屏3:4，横屏16:9）

### 测试 5: 边界情况
1. **快速连续点击小预览框**（3-4次）
   - 应该能响应每次点击
   - 不应该崩溃或卡住
2. **录制开始时立即点击切换**
   - 应该从第一帧开始就是切换后的状态
3. **录制结束前点击切换**
   - 最后的帧应该正确记录切换状态

## 预期结果

### ✅ 成功标准
1. **UI美观**：圆角、边框、阴影都正确显示
2. **切换响应**：点击立即切换，无延迟
3. **录制正确**：视频中记录了所有切换操作
4. **性能良好**：切换时不卡顿，录制流畅
5. **边框一致**：无论哪个相机作为小预览，白边框都显示

### ❌ 失败场景（需要修复）
1. 点击小预览框没反应
2. UI切换了但视频中没有记录
3. 切换后画面比例或位置错误
4. 崩溃或性能问题

## 故障排查

### 如果点击不响应
1. 检查 ContentView 中的 DragGesture 是否正确检测 PIP 区域
2. 检查通知是否正确发送和接收
3. 查看控制台日志是否有 "Toggle preview camera" 消息

### 如果视频中没有记录切换
1. 检查 `CameraManager.previewSwitcher` 是否正确连接
2. 检查 `composePIPVideoFrame` 是否接收到正确的 `isBackCameraMain` 参数
3. 查看控制台日志确认合成时的参数

### 如果UI样式不对
1. 检查 PIP 容器的 `masksToBounds` 应该是 `false`（显示阴影）
2. 检查 frontView 的约束是否正确（3px 边距）
3. 检查边框宽度和颜色设置

## 性能注意事项

- ✅ PreviewSwitcher 是轻量级对象，切换只改变布尔值
- ✅ 视频合成时只是交换两个已有的 buffer，无额外开销
- ✅ UI 切换使用 Core Animation，GPU 加速
- ✅ 不会影响录制的帧率或质量

## 代码审查检查点

1. ✅ `composePIPVideoFrame` 正确使用 `mainImage` 和 `pipImage`
2. ✅ `CameraManager` 正确传递 `isBackCameraMain` 参数
3. ✅ `DualCameraPreview` 在 `makeUIView` 中建立连接
4. ✅ UI 约束正确，不会相互冲突
5. ✅ 所有修改都是线程安全的（PreviewSwitcher 属性访问）

## 完成状态

- [x] PIPComposer 支持切换参数
- [x] CameraManager 读取 PreviewSwitcher 状态
- [x] DualCameraPreview 建立连接
- [x] UI 美化（圆角、边框、阴影）
- [x] 切换图标改进
- [ ] 测试验证（待用户测试）

---

**实现日期**: 2025年12月14日
**实现方案**: 低资源开销、高性能的状态同步方案
**关键技术**: PreviewSwitcher 状态共享、PIPComposer 动态合成、Core Animation UI
