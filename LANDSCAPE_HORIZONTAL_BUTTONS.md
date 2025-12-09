# 横屏按钮横向排列

## 布局修改

### 改为横向排列

**之前**: Gallery/Flash/Mode 竖向排列 (VStack)
**现在**: 横向排列 (HStack)

**顺序**: 从左到右
1. Flash (闪光灯)
2. Mode (模式切换)
3. Gallery (相册)

## 最终横屏布局

```
┌─────────────────────────────────────────────┐
│                               [PIP 160x90]  │ ← 右上角
│                                             │
│                                             │
│                                     (O)     │ ← Capture (上方)
│                                             │
│                              [F] [M] [G]    │ ← 三个按钮横向 (下方)
│                                             │
│ [Zoom Slider]                               │
└─────────────────────────────────────────────┘
```

布局说明:
- **右上角**: PIP (160x90)
- **右侧上方**: Capture 按钮 (80x80)
- **右侧下方**: Flash, Mode, Gallery 横向排列 (56x56, 间距20px)
- **左下角**: Zoom Slider

## 代码实现

```swift
if isLandscape {
    VStack(spacing: 30) {
        Spacer()
        
        // Capture button - 在上方
        Button(captureButton) { ... }
        
        // 三个按钮横向排列
        HStack(spacing: 20) {
            Button(flashButton) { ... }   // 闪光
            Button(modeButton) { ... }    // 切换
            Button(galleryButton) { ... } // 相册
        }
        
        Spacer().frame(height: 40) // 底部留空
    }
    .frame(maxWidth: .infinity, alignment: .trailing)
    .padding(.trailing, 30)
}
```

## 布局结构

### VStack (整体垂直布局)
- `Spacer()` - 顶部弹性空间
- **Capture 按钮** - 80x80
- **间距**: 30px
- **HStack** - 三个按钮横向组
  - Flash: 56x56
  - Mode: 56x56
  - Gallery: 56x56
  - 间距: 20px
- `Spacer(40)` - 底部固定空间

### 对齐方式
- `.frame(maxWidth: .infinity, alignment: .trailing)` - 右对齐
- `.padding(.trailing, 30)` - 距离右边缘30px

## 按钮顺序

**从左到右**:
1. **Flash** (闪光灯) - `bolt.fill` / `bolt.slash.fill`
2. **Mode** (模式切换) - `video.fill` / `camera.fill`
3. **Gallery** (相册) - `photo.on.rectangle` 或缩略图

## 视觉效果

### 按钮组合
```
  (O)        ← Capture (80x80, 独立在上方)
   ↓ 30px
[F] [M] [G] ← 三个按钮横向 (56x56, 间距20px)
```

### 在屏幕上的位置
```
                                    ┌─────┐
                                    │  O  │ Capture
                                    └─────┘
                                       ↓
                                ┌───┬───┬───┐
                                │ F │ M │ G │ 三个按钮
                                └───┴───┴───┘
```

## 布局参数

| 元素 | 尺寸 | 位置 | 间距 |
|------|------|------|------|
| PIP | 160x90 | 右上角 | - |
| Capture | 80x80 | 右侧,上方 | - |
| Flash/Mode/Gallery | 56x56 | 右侧,下方 | 20px |
| Capture 到三个按钮 | - | 垂直间距 | 30px |
| 底部留空 | - | - | 40px |

## 测试场景

### 场景 1: 横屏布局
1. 旋转到横屏
2. **检查**:
   - ✅ PIP在右上角
   - ✅ Capture在右侧上方
   - ✅ 三个按钮在Capture下方横向排列
   - ✅ 顺序: Flash, Mode, Gallery (从左到右)

### 场景 2: 按钮间距
1. 横屏模式
2. **检查**:
   - ✅ Capture到三个按钮约30px间距
   - ✅ 三个按钮之间20px间距
   - ✅ 按钮组距底部约40px
   - ✅ 所有按钮右对齐,距右边缘30px

### 场景 3: 功能测试
1. 点击Flash → 切换闪光灯 ✓
2. 点击Mode → 切换拍照/录像 ✓
3. 点击Gallery → 打开相册 ✓
4. 点击Capture → 拍照/录像 ✓

### 场景 4: 视觉平衡
1. 横屏模式
2. **检查**:
   - ✅ 按钮组在右侧,不遮挡预览
   - ✅ PIP在右上角,不与按钮重叠
   - ✅ 布局紧凑,易于单手操作
   - ✅ 所有按钮易于点击

## 布局调整指南

### 如果需要调整垂直间距

**Capture到三个按钮**:
```swift
VStack(spacing: 30) { ... }  // 改为20, 40等
```

**三个按钮之间**:
```swift
HStack(spacing: 20) { ... }  // 改为15, 25等
```

**底部留空**:
```swift
Spacer().frame(height: 40)  // 改为30, 50等
```

### 如果需要调整水平位置

**右边距**:
```swift
.padding(.trailing, 30)  // 增大→向左, 减小→向右
```

**按钮组宽度**:
三个按钮宽度 = 56×3 + 20×2 = 208px

### 如果需要改变按钮顺序

在HStack中调整Button顺序:
```swift
HStack(spacing: 20) {
    Button(flash)   // 第一个
    Button(mode)    // 第二个
    Button(gallery) // 第三个
}
```

## 已修改的文件

**ContentView.swift**
- 横屏布局改为VStack垂直结构
- Capture按钮在上方
- 三个按钮改为HStack横向排列
- 顺序: Flash, Mode, Gallery
- 间距: Capture到按钮30px, 按钮间20px
- 底部留空40px

## 注意事项

1. **右对齐**: 使用`.frame(maxWidth: .infinity, alignment: .trailing)`
2. **底部留空**: `Spacer().frame(height: 40)` 防止按钮太靠边缘
3. **按钮顺序**: Flash → Mode → Gallery (从左到右)
4. **响应式**: 整个布局自适应不同屏幕尺寸

## 完成状态

- ✅ 三个按钮横向排列
- ✅ 顺序: Flash, Mode, Gallery (从左到右)
- ✅ Capture在上方,三个按钮在下方
- ✅ 右对齐,距右边缘30px
- ✅ 垂直间距30px
- ✅ 横向间距20px
- ✅ 底部留空40px
- ✅ PIP在右上角
- ✅ 所有功能正常
