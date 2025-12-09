# 预览方向和 UI 旋转修复

## 问题

1. **预览画面横向**: 竖拍时,画面应该是竖着的,但实际是横着的
   - 手机向上移动,画面向左移动 ❌
   - 应该: 手机向上移动,画面也向上移动 ✅

2. **UI 固定**: 之前锁定了整个应用方向,导致所有 UI 都不旋转
   - 应该: 只有预览画面固定,其他 UI 随设备旋转

3. **PIP 位置**: 前置摄像头小窗口位置不随设备旋转调整
   - 竖屏: 应该在右上角
   - 横屏: 应该在左上角

## 解决方案

### 1. 移除应用级方向锁定

**删除**: `AppDelegate.swift`
**还原**: `dualCameraApp.swift` 移除 `@UIApplicationDelegateAdaptor`

现在应用可以自由旋转,UI 会响应设备方向。

### 2. 修复预览画面方向

**问题根源**: 
相机捕获的帧默认方向是横向(Landscape),需要根据设备方向旋转。

**实现**:

```swift
private func fixImageOrientation(_ image: UIImage) -> UIImage {
    let orientation = UIDevice.current.orientation
    
    var rotationAngle: CGFloat = 0
    
    switch orientation {
    case .portrait:
        rotationAngle = .pi / 2  // 90度 - 竖屏
    case .portraitUpsideDown:
        rotationAngle = -.pi / 2  // -90度 - 倒置
    case .landscapeLeft:
        rotationAngle = .pi  // 180度
    case .landscapeRight:
        rotationAngle = 0  // 0度
    default:
        rotationAngle = .pi / 2  // 默认竖屏
    }
    
    return rotateImage(image, by: rotationAngle)
}
```

**效果**:
- 竖拍时: 画面是竖着的,手机上移 → 画面上移 ✅
- 横拍时: 画面自动旋转到正确方向

### 3. PIP 位置动态调整

```swift
override func layoutSubviews() {
    super.layoutSubviews()
    
    let isLandscape = bounds.width > bounds.height
    
    if isLandscape {
        // 横屏: PIP 在左上角
        frontContainerView?.frame = CGRect(
            x: safeLeft + pipPadding,
            y: safeTop + pipPadding,
            width: pipWidth,
            height: pipHeight
        )
    } else {
        // 竖屏: PIP 在右上角
        frontContainerView?.frame = CGRect(
            x: bounds.width - pipWidth - pipPadding,
            y: safeTop + pipPadding,
            width: pipWidth,
            height: pipHeight
        )
    }
}
```

**效果**:
- 竖屏 → 横屏: PIP 从右上角移动到左上角
- 横屏 → 竖屏: PIP 从左上角移动回右上角

### 4. 其他 UI 自动适应

因为移除了方向锁定,所有其他 UI 组件会自然响应旋转:
- **按钮布局**: CameraControlButtons 已经有横竖屏不同布局
- **Zoom 滑块**: ZoomSlider 会自动调整方向
- **录制指示器**: 保持在屏幕顶部

## 工作原理

### 预览画面固定
**并非真正"锁定"**,而是:
1. 持续检测设备方向 (`UIDevice.current.orientation`)
2. 根据方向动态旋转捕获的图像
3. 显示旋转后的图像

**结果**: 
- 画面始终保持"正"的方向
- 看起来像是"锁定",实际上是实时调整

### UI 自由旋转
- SwiftUI 和 UIKit 组件自然响应设备旋转
- `layoutSubviews` 在旋转时自动调用
- PIP 位置在布局时根据 `isLandscape` 调整

## 测试场景

### 场景 1: 竖屏拍摄
1. 手机竖着拿
2. 向上移动手机
3. **预期**: 画面向上移动(不是向左!) ✅
4. **PIP**: 在右上角 ✅

### 场景 2: 旋转到横屏
1. 手机顺时针旋转90度(横屏)
2. **预期**: 
   - 画面自动旋转,保持正确方向 ✅
   - PIP 移动到左上角 ✅
   - 按钮从底部移到右侧 ✅

### 场景 3: 横屏拍摄
1. 手机横着拿
2. 向右移动手机
3. **预期**: 画面向右移动 ✅
4. **PIP**: 在左上角 ✅

### 场景 4: 旋转回竖屏
1. 手机逆时针旋转90度(回到竖屏)
2. **预期**:
   - 画面旋转回竖向 ✅
   - PIP 移回右上角 ✅
   - 按钮回到底部 ✅

## 已修改的文件

1. **删除**: `/dualCamera/AppDelegate.swift`
   - 移除应用级方向锁定

2. **修改**: `/dualCamera/dualCameraApp.swift`
   - 移除 `@UIApplicationDelegateAdaptor`

3. **修改**: `/dualCamera/Managers/DualCameraPreview.swift`
   - 添加 `fixImageOrientation()` 方法
   - 添加 `rotateImage()` 方法
   - 更新 `layoutSubviews()` 中 PIP 位置逻辑
   - 在 `updateBackFrame()` 和 `updateFrontFrame()` 中应用旋转

## 注意事项

### 设备方向 vs 界面方向
- **UIDevice.current.orientation**: 物理设备方向(重力感应)
- **UIInterfaceOrientation**: 界面方向(可能被锁定)

我们使用设备方向来旋转画面,确保画面始终"站立"。

### 性能考虑
图像旋转在 30fps 下可能有性能开销。如果发现卡顿:
1. 可以降低预览帧率
2. 或使用 GPU 加速旋转(Metal/Core Image)
3. 或缓存旋转后的图像

### 前置摄像头镜像
前置摄像头可能需要水平翻转(镜像)。如果发现前置画面反了,可以添加:
```swift
if isFrontCamera {
    context.scaleBy(x: -1, y: 1)  // 水平翻转
}
```

## 测试清单

- [ ] 竖屏时画面正确显示
- [ ] 手机上移,画面上移(不是左移)
- [ ] PIP 在竖屏时位于右上角
- [ ] 旋转到横屏,画面自动调整
- [ ] PIP 在横屏时位于左上角
- [ ] 按钮布局在横屏时垂直排列
- [ ] 拍照和录像功能不受影响
- [ ] 画面流畅,无明显卡顿
