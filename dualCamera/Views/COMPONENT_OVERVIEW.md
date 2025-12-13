# 双摄像头应用 - 组件和枚举概览

## 核心枚举 (CameraEnums.swift)

### CaptureMode
- `.photo` - 拍照模式
- `.video` - 录像模式

### CameraMode  
- `.dual` - 双摄像头模式
- `.backOnly` - 仅后置摄像头
- `.frontOnly` - 仅前置摄像头

### FilterStyle
11种滤镜效果：
- `.none` - 无滤镜
- `.mono`, `.tonal`, `.noir` - 黑白系列
- `.fade`, `.chrome`, `.process` - 复古系列
- `.transfer`, `.instant` - 特殊效果
- `.sepia`, `.vibrant` - 色调调整

## 视频设置枚举 (VideoSettings.swift)

### VideoResolution
- `.resolution_4K` - 3840×2160
- `.resolution_1080p` - 1920×1080  
- `.resolution_720p` - 1280×720
- `.resolution_480p` - 854×480

### FrameRate
- `.fps_24` - 24 FPS
- `.fps_30` - 30 FPS
- `.fps_60` - 60 FPS
- `.fps_120` - 120 FPS

## 其他枚举

### FlashMode (CameraViewModel.swift)
- `.off` - 关闭
- `.on` - 常亮（torch）
- `.auto` - 自动（屏幕闪光）

## UI 组件

### Alert Views (AlertViews.swift)
1. `CameraPermissionAlert` - 相机权限提示
2. `SaveStatusAlert` - 保存状态通知
3. `SettingsChangeAlert` - 设置更改通知 ✨ 新增

### Picker Overlays (PickerOverlay.swift)
1. `PickerOverlay<T>` - 通用选择器（用于分辨率）
2. `FrameRatePickerOverlay` - 帧率选择器

### 其他组件
- `CameraControlButtons` - 相机控制按钮
- `DualCameraPreview` - 双摄预览
- `ZoomSlider` - 缩放滑块
- `CentralZoomIndicator` - 中央缩放指示器
- `FocusIndicator` - 对焦指示器

## 参数签名

### PickerOverlay
```swift
PickerOverlay(
    title: String,
    options: [T],
    selection: Binding<T>,
    onDismiss: () -> Void,
    displayName: (T) -> String
)
```

### FrameRatePickerOverlay
```swift
FrameRatePickerOverlay(
    title: String,
    options: [FrameRate],
    selection: Binding<FrameRate>,
    onDismiss: () -> Void
)
```

### SettingsChangeAlert
```swift
SettingsChangeAlert(
    message: String,
    onDismiss: () -> Void
)
```

## 注意事项

1. ⚠️ `VideoResolution` 和 `FrameRate` 已在 `VideoSettings.swift` 中定义
2. ✅ 所有枚举都实现了 `displayName` 属性用于 UI 显示
3. ✅ Picker 使用 `@Binding` 实现双向绑定
4. ✅ Alert 都使用自动消失动画（1秒后）
5. ✅ 所有组件都支持横屏和竖屏布局
