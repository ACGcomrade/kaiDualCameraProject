# 横屏方向和UI布局修复

## 修复的问题

### 1. ✅ 横屏时画面反转180度

**问题**: 横屏时预览画面倒置

**原因**: `landscapeLeft` 和 `landscapeRight` 的旋转角度设置反了

**修复**:
```swift
// 修复前
case .landscapeLeft:
    rotationAngle = .pi  // 180度 ❌
case .landscapeRight:
    rotationAngle = 0    // 0度 ❌

// 修复后
case .landscapeLeft:
    rotationAngle = 0    // 0度 ✅
case .landscapeRight:
    rotationAngle = .pi  // 180度 ✅
```

### 2. ✅ 横屏时按钮布局优化

**需求**: 横屏时,除了拍摄按钮外,其他控件移到底部横排(和 zoom slider 同一行)

**实现**: 在 `ContentView.swift` 中根据设备方向使用不同布局

#### 横屏布局 (新)
```
┌────────────────────────────────────────┐
│                                        │
│           Preview (正常方向)            │
│                                        │
├────────────────────────────────────────┤
│ [Gallery] [Flash] [Mode]    (O)    [Zoom Slider] │
└────────────────────────────────────────┘
```

从左到右:
- **左侧**: Gallery, Flash, Mode Switch (3个小按钮)
- **中间**: 拍摄按钮 (大圆圈)
- **右侧**: Zoom Slider (滑块)

#### 竖屏布局 (保持原样)
```
┌──────────────┐
│   Preview    │
│              │
│              │
├──────────────┤
│ [Buttons]    │
└──────────────┘
```

底部横排: Gallery, Capture, Flash, Mode

## 代码实现

### DualCameraPreview.swift

修复方向旋转逻辑:

```swift
private func fixImageOrientation(_ image: UIImage) -> UIImage {
    let orientation = UIDevice.current.orientation
    
    switch orientation {
    case .portrait:
        rotationAngle = .pi / 2  // 90度
    case .landscapeLeft:
        rotationAngle = 0        // 0度 - 正确
    case .landscapeRight:
        rotationAngle = .pi      // 180度 - 正确
    // ...
    }
}
```

### ContentView.swift

根据方向使用不同布局:

```swift
GeometryReader { geometry in
    let isLandscape = geometry.size.width > geometry.size.height
    
    if isLandscape {
        // 横屏布局: 底部横排
        HStack {
            // 左: Gallery, Flash, Mode
            HStack(spacing: 15) {
                Button(galleryButtonContent) { ... }
                Button(flashButton) { ... }
                Button(modeButton) { ... }
            }
            
            Spacer()
            
            // 中: Capture button
            Button(captureButtonContent) { ... }
            
            Spacer()
            
            // 右: Zoom slider 占位
        }
    } else {
        // 竖屏布局: 使用 CameraControlButtons
        CameraControlButtons(...)
    }
}
```

添加辅助视图:

```swift
@ViewBuilder
private var galleryButtonContent: some View {
    if let image = viewModel.lastCapturedImage {
        Image(uiImage: image)
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    } else {
        Image(systemName: "photo.on.rectangle")
            .frame(width: 50, height: 50)
    }
}

@ViewBuilder
private var captureButtonContent: some View {
    ZStack {
        Circle().stroke(Color.white, lineWidth: 3)
            .frame(width: 80, height: 80)
        // 根据模式显示不同内容
    }
}
```

## 测试场景

### 场景 1: 竖屏 → 横屏
1. 应用启动,竖屏模式
2. 旋转手机到横屏
3. **预期**:
   - ✅ 预览画面正确显示(不倒置)
   - ✅ 按钮移到底部横排
   - ✅ 拍摄按钮在中间
   - ✅ Gallery/Flash/Mode 在左侧
   - ✅ Zoom slider 在右侧

### 场景 2: 横屏操作
1. 横屏模式下
2. 移动手机
3. **预期**:
   - ✅ 画面方向正确(不倒置)
   - ✅ 所有按钮可点击
   - ✅ 拍照/录像功能正常

### 场景 3: 横屏 → 竖屏
1. 从横屏旋转回竖屏
2. **预期**:
   - ✅ 预览画面恢复竖向
   - ✅ 按钮恢复到底部横排
   - ✅ 布局切换流畅

### 场景 4: 不同横屏方向
1. LandscapeLeft (Home键在左)
2. LandscapeRight (Home键在右)
3. **预期**:
   - ✅ 两种横屏方向画面都正确
   - ✅ 按钮布局一致

## 布局细节

### 横屏按钮尺寸
- **小按钮**: 50x50 (Gallery, Flash, Mode)
- **拍摄按钮**: 80x80 (外圈), 70x70 (内圈)
- **间距**: 15px (按钮间), 20px (组间), 30px (边距)

### 竖屏按钮布局
保持原 `CameraControlButtons` 组件不变

### Zoom Slider
- **竖屏**: 垂直,在左侧
- **横屏**: 水平,在底部右侧

## 已修改的文件

1. `/dualCamera/Managers/DualCameraPreview.swift`
   - 修复 `fixImageOrientation()` 中横屏方向角度
   - `landscapeLeft`: 0度
   - `landscapeRight`: 180度

2. `/dualCamera/Views/ContentView.swift`
   - 添加横屏/竖屏布局判断
   - 横屏时使用自定义底部横排布局
   - 竖屏时使用原 `CameraControlButtons`
   - 添加 `galleryButtonContent` 辅助视图
   - 添加 `captureButtonContent` 辅助视图

## 优化建议

### 如果横屏画面仍然反了
根据实际设备测试调整角度:
```swift
// 尝试交换
case .landscapeLeft:
    rotationAngle = .pi
case .landscapeRight:
    rotationAngle = 0
```

### 如果需要调整按钮位置
修改 `ContentView.swift` 中的 `spacing` 和 `padding`:
```swift
HStack(spacing: 15) { ... }  // 调整间距
.padding(.horizontal, 30)    // 调整边距
```

### 如果需要更多按钮
在横屏布局的 HStack 中添加:
```swift
HStack(spacing: 15) {
    Button(...) { ... }  // 新按钮
    Button(galleryButtonContent) { ... }
    // ...
}
```

## 注意事项

1. **设备方向获取**: `UIDevice.current.orientation` 依赖重力感应,设备平放时可能为 `.unknown`
2. **布局刷新**: `GeometryReader` 会在屏幕尺寸变化时自动重新计算
3. **按钮状态**: 横屏和竖屏共享 ViewModel,状态一致
4. **Zoom Slider**: 横屏时需要确保 Zoom Slider 在正确位置(已有单独实现)

## 测试清单

- [ ] 竖屏时按钮在底部
- [ ] 横屏时按钮在底部横排
- [ ] 横屏时拍摄按钮在中间
- [ ] 横屏时画面方向正确(不倒置)
- [ ] LandscapeLeft 和 LandscapeRight 都正确
- [ ] 旋转切换流畅无卡顿
- [ ] 拍照录像功能正常
- [ ] Gallery/Flash/Mode 按钮可点击
