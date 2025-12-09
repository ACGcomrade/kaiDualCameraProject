# 横屏布局调整

## 调整内容

### 1. ✅ Capture按钮移到横向中轴线

**之前**: 右下角
**现在**: 右侧,垂直居中(横向中轴线)

**实现**:
```swift
HStack {
    Spacer()
    Button(captureButton) { ... }
        .padding(.trailing, 30)
}
// 移除了 VStack + Spacer 包装
// 按钮自然居中在垂直方向
```

### 2. ✅ 三个按钮往左移

**之前**: `.padding(.trailing, geo.size.width * 0.25 / 2)` (屏幕右侧1/4)
**现在**: `.padding(.trailing, geo.size.width * 0.35)` (更靠左)

**效果**: 
- 从屏幕右边缘向左移动约35%
- 给Capture按钮和PIP留出更多空间

### 3. ✅ 小预览窗口移到右上角

**之前**: 横屏时在左上角
**现在**: 横屏和竖屏都在右上角

**实现**:
```swift
if isLandscape {
    // 横屏: PIP 在右上角
    frontContainerView?.frame = CGRect(
        x: bounds.width - pipWidth - pipPadding,
        y: safeTop + pipPadding,
        width: pipWidth,
        height: pipHeight
    )
}
```

## 最终横屏布局

```
┌─────────────────────────────────────────────┐
│                               [PIP 160x90]  │ ← 右上角
│                                             │
│                         [G]                 │ ← 左移35%
│                         [F]         (O)     │ ← 中轴线
│          Preview        [M]                 │
│                                             │
│                                             │
│ [Zoom Slider]                               │
└─────────────────────────────────────────────┘
```

布局元素:
- **右上角**: PIP (160x90)
- **右侧偏左**: Gallery/Flash/Mode (向左35%, 竖向排列)
- **右侧中间**: Capture按钮 (垂直居中)
- **左下角**: Zoom Slider

## 代码变更

### ContentView.swift

**Capture按钮位置**:
```swift
// 之前: 右下角
VStack {
    Spacer()
    HStack {
        Spacer()
        Button(...).padding(.trailing, 30).padding(.bottom, 30)
    }
}

// 现在: 垂直居中
HStack {
    Spacer()
    Button(...).padding(.trailing, 30)
}
```

**三个按钮位置**:
```swift
// 之前
.padding(.trailing, geo.size.width * 0.25 / 2)  // ~12.5%

// 现在
.padding(.trailing, geo.size.width * 0.35)      // 35%
```

### DualCameraPreview.swift

**PIP位置**:
```swift
// 之前: 横屏左上角
if isLandscape {
    x: safeLeft + pipPadding
}

// 现在: 横屏右上角
if isLandscape {
    x: bounds.width - pipWidth - pipPadding
}
```

## 视觉对比

### 之前的布局
```
┌─────────────────────────────────────────────┐
│ [PIP]                                       │
│                                    [G]      │
│                                    [F]      │
│           Preview                  [M]      │
│                                             │
│                                      (O)    │ ← 右下角
└─────────────────────────────────────────────┘
```

### 现在的布局
```
┌─────────────────────────────────────────────┐
│                               [PIP]         │ ← 右上角
│                                             │
│                         [G]                 │
│                         [F]         (O)     │ ← 中轴线
│          Preview        [M]                 │
│                                             │
│                                             │
│ [Zoom]                                      │
└─────────────────────────────────────────────┘
```

## 布局参数

| 元素 | 位置 | 尺寸 | 说明 |
|------|------|------|------|
| PIP | 右上角 | 160x90 | 横向长方形 |
| Capture | 右侧,垂直居中 | 80x80 | 中轴线 |
| Gallery/Flash/Mode | 右侧左移35% | 56x56 | 竖向排列 |
| Zoom Slider | 左下角 | - | 独立实现 |

## 测试场景

### 场景 1: 横屏布局
1. 旋转到横屏
2. **检查位置**:
   - ✅ PIP 在右上角
   - ✅ Capture在右侧,垂直方向居中
   - ✅ Gallery/Flash/Mode在左侧一些(不是最右边)
   - ✅ 元素之间不重叠

### 场景 2: 按钮功能
1. 横屏模式
2. 点击Capture按钮 → 拍照/录像
3. 点击Gallery → 打开相册
4. 点击Flash → 切换闪光灯
5. 点击Mode → 切换模式
6. **预期**: 所有功能正常

### 场景 3: 视觉平衡
1. 横屏模式
2. **检查**:
   - ✅ 右上角PIP不遮挡重要内容
   - ✅ 中间区域留给预览画面
   - ✅ 按钮分布均匀,不拥挤
   - ✅ Capture按钮易于点击(居中)

### 场景 4: 竖屏切换
1. 从横屏旋转到竖屏
2. **预期**:
   - ✅ 布局自动切换到竖屏模式
   - ✅ PIP保持在右上角
   - ✅ 按钮切换到底部横排

## 布局调整指南

### 如果Capture按钮需要上下移动

当前实现使用`HStack`自动垂直居中。如需微调:

**方法1: 添加偏移**
```swift
Button(...).offset(y: -20)  // 向上移, 正数向下
```

**方法2: 使用VStack控制**
```swift
VStack {
    Spacer()
    Button(...)
    Spacer().frame(height: 100)  // 底部留空,按钮上移
}
```

### 如果三个按钮需要左右调整

```swift
.padding(.trailing, geo.size.width * 0.35)
// 增大系数 → 更左, 减小 → 更右
// 0.4 = 更左, 0.3 = 更右
```

### 如果三个按钮需要上下调整

```swift
.padding(.bottom, 120)
// 增大 → 向上, 减小 → 向下
```

### 如果PIP需要调整位置

**左右移动**:
```swift
x: bounds.width - pipWidth - pipPadding
// 增大pipPadding → 向左
// 减小pipPadding → 向右
```

**上下移动**:
```swift
y: safeTop + pipPadding
// 增大pipPadding → 向下
// 减小pipPadding → 向上
```

## 已修改的文件

### 1. ContentView.swift
- Capture按钮从VStack嵌套改为单层HStack
- 移除`.padding(.bottom, 30)`,实现垂直居中
- 三个按钮的`.padding(.trailing)`从`0.25/2`改为`0.35`

### 2. DualCameraPreview.swift
- 横屏时PIP的x坐标从`safeLeft + pipPadding`改为`bounds.width - pipWidth - pipPadding`
- PIP在横竖屏都位于右上角

## 注意事项

1. **Capture居中**: 使用HStack自动居中,无需手动计算
2. **按钮百分比**: `geo.size.width * 0.35`适应不同屏幕尺寸
3. **PIP一致性**: 横竖屏都在右上角,用户体验一致
4. **响应式布局**: 所有位置都相对计算,支持多种设备

## 完成状态

- ✅ Capture按钮在横向中轴线
- ✅ Gallery/Flash/Mode往左35%
- ✅ PIP在右上角(横竖屏一致)
- ✅ 布局清晰,不重叠
- ✅ 所有功能正常工作
- ✅ 响应式适应不同屏幕
