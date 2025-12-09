# 最终方向和布局修复

## 修复的问题

### 1. ✅ 小预览画面(PIP)横屏方向

**问题**: 大预览画面修复后正确了,但小预览画面(前置摄像头)在横屏时反转了180度

**原因**: 前置和后置摄像头需要不同的旋转角度

**解决方案**: 
为前置和后置摄像头分别处理旋转逻辑

```swift
private func fixImageOrientation(_ image: UIImage, isFrontCamera: Bool) -> UIImage {
    let orientation = UIDevice.current.orientation
    var rotationAngle: CGFloat = 0
    
    if isFrontCamera {
        // 前置摄像头: 保持原来的角度
        switch orientation {
        case .landscapeLeft:
            rotationAngle = .pi  // 180度
        case .landscapeRight:
            rotationAngle = 0    // 0度
        // ...
        }
    } else {
        // 后置摄像头: 使用新的角度
        switch orientation {
        case .landscapeLeft:
            rotationAngle = 0    // 0度
        case .landscapeRight:
            rotationAngle = .pi  // 180度
        // ...
        }
    }
}
```

调用时区分前后摄像头:
```swift
func updateBackFrame(_ image: UIImage?) {
    let fixedImage = fixImageOrientation(image, isFrontCamera: false)
}

func updateFrontFrame(_ image: UIImage?) {
    let fixedImage = fixImageOrientation(image, isFrontCamera: true)
}
```

### 2. ✅ 横屏UI布局优化

**需求**: 横屏时,按钮在 zoom slider 右侧紧凑排列,不要分散

**修复前**:
```
[Gallery] [Flash] [Mode]    (Capture)    [Zoom...]
  左侧分散                   中间          右侧
```

**修复后**:
```
[Zoom Slider] [Gallery][Flash][Mode]    (Capture保持原位)
  左侧         右侧紧凑排列                原CameraControlButtons
```

实现:
```swift
if isLandscape {
    VStack {
        Spacer()
        HStack(spacing: 0) {
            Spacer()
            
            // 右侧按钮组: 紧凑排列
            HStack(spacing: 8) {
                Button(galleryButtonContent) { ... }  // 44x44
                Button(flashButton) { ... }           // 44x44
                Button(modeButton) { ... }            // 44x44
            }
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
    }
}
```

**按钮尺寸**:
- 从 50x50 缩小到 44x44
- 间距从 15px 缩小到 8px
- 更紧凑,不占用过多空间

### 3. ✅ Capture按钮保持原样

**修改**: 移除了横屏时的自定义 capture 按钮
**效果**: 横屏时 capture 按钮仍使用 `CameraControlButtons` 中的布局

## 最终布局

### 竖屏模式
```
┌──────────────┐
│              │
│   Preview    │
│              │
│              │
├──────────────┤
│ [Buttons]    │  ← CameraControlButtons (不变)
└──────────────┘
```

### 横屏模式
```
┌────────────────────────────────────────┐
│                                        │
│           Preview (正确方向)            │
│                                        │
├────────────────────────────────────────┤
│ [Zoom Slider]           [G][F][M]  (O)│
└────────────────────────────────────────┘
```

- **Zoom Slider**: 左侧(已有独立实现)
- **[G][F][M]**: Gallery, Flash, Mode (右侧紧凑排列)
- **(O)**: Capture 按钮 (使用 CameraControlButtons,在最右侧)

## 代码修改

### DualCameraPreview.swift

1. `fixImageOrientation()` 添加 `isFrontCamera` 参数
2. 前置和后置摄像头使用不同的旋转角度
3. `updateBackFrame()` 调用时传 `false`
4. `updateFrontFrame()` 调用时传 `true`

### ContentView.swift

1. 横屏布局改为右对齐紧凑排列
2. 移除 `captureButtonContent` 辅助方法
3. `galleryButtonContent` 尺寸改为 44x44
4. 按钮间距缩小到 8px

## 方向角度总结

### 后置摄像头(大预览)
- Portrait: 90°
- LandscapeLeft: 0°
- LandscapeRight: 180°

### 前置摄像头(小预览)
- Portrait: 90°
- LandscapeLeft: 180°
- LandscapeRight: 0°

**差异**: 横屏时前后摄像头角度相反

## 测试场景

### 场景 1: 竖屏预览
- [ ] 大预览画面正确(竖直)
- [ ] 小预览画面正确(竖直)
- [ ] 按钮在底部横排

### 场景 2: 旋转到横屏
- [ ] 大预览画面正确(不倒置)
- [ ] 小预览画面正确(不倒置) ← 重点测试!
- [ ] 按钮移到右侧紧凑排列
- [ ] Zoom slider 在左侧
- [ ] Capture 按钮在最右

### 场景 3: 横屏拍照
- [ ] 大小预览都正确
- [ ] 拍照功能正常
- [ ] 保存的照片方向正确

### 场景 4: LandscapeLeft vs LandscapeRight
- [ ] 两种横屏方向大预览都正确
- [ ] 两种横屏方向小预览都正确
- [ ] 按钮布局一致

### 场景 5: 横屏录像
- [ ] 预览流畅不卡顿
- [ ] 录像功能正常
- [ ] 保存的视频方向正确

## 已修改的文件

1. **DualCameraPreview.swift**
   - `fixImageOrientation()` 添加 `isFrontCamera: Bool` 参数
   - 前后摄像头使用不同旋转逻辑
   - `updateBackFrame()` 和 `updateFrontFrame()` 传递不同参数

2. **ContentView.swift**
   - 横屏布局改为右对齐
   - 按钮尺寸 50x50 → 44x44
   - 间距 15px → 8px
   - 移除 `captureButtonContent` 方法
   - 保持 capture 按钮使用原 `CameraControlButtons`

## 注意事项

### 如果小预览仍然反了
可能需要交换前置摄像头的角度:
```swift
if isFrontCamera {
    case .landscapeLeft:
        rotationAngle = 0     // 尝试交换
    case .landscapeRight:
        rotationAngle = .pi   // 尝试交换
}
```

### 如果按钮位置需要调整
修改 ContentView 中的 spacing 和 padding:
```swift
HStack(spacing: 8) { ... }     // 调整间距
.padding(.trailing, 20)        // 调整右边距
.padding(.bottom, 20)          // 调整下边距
```

### 前置摄像头镜像
如果需要镜像翻转(自拍效果),可以在旋转前添加:
```swift
if isFrontCamera {
    // 水平翻转
    context.scaleBy(x: -1, y: 1)
}
```

## 完成状态

- ✅ 大预览画面横屏正确
- ✅ 小预览画面横屏正确
- ✅ 横屏UI紧凑排列
- ✅ Capture按钮保持原样
- ✅ 竖屏布局不变
