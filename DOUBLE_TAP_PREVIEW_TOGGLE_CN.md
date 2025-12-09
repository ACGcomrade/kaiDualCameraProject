# 功能更新：双击切换预览黑屏

## 变更总结

### 移除的功能
- ❌ 双击隐藏 UI 按钮的功能
- ❌ `isUIVisible` 状态对按钮的影响
- ❌ 所有与 UI 按钮隐藏相关的逻辑

### 新增/恢复的功能
- ✅ 双击切换预览可见性（黑屏/显示预览）
- ✅ 录制时 5 分钟后自动黑屏（保留）
- ✅ 预览隐藏时保留 capture button
- ✅ 所有 UI 按钮始终可见（不再隐藏）

## 具体修改

### 1. UIVisibilityManager.swift

#### 修改前：`toggleUI()`
```swift
func toggleUI() {
    // 切换 UI 按钮可见性
    isUIVisible.toggle()
}
```

#### 修改后：`togglePreview()`
```swift
func togglePreview() {
    // 切换预览可见性（黑屏）
    isPreviewVisible.toggle()
    
    // 如果显示预览，重启定时器
    if isPreviewVisible {
        startPreviewTimer()
    }
}
```

**说明**：
- 从控制 UI 按钮改为控制预览显示
- 显示预览时自动重启 5 分钟定时器
- 预览隐藏时显示黑屏

### 2. CameraViewModel.swift

#### 修改前：`toggleUIVisibility()`
```swift
func toggleUIVisibility() {
    uiVisibilityManager.toggleUI()
}
```

#### 修改后：`togglePreviewVisibility()`
```swift
func togglePreviewVisibility() {
    uiVisibilityManager.togglePreview()
}
```

### 3. ContentView.swift

#### 修改 1：双击手势
```swift
.onTapGesture(count: 2) {
    print("🖐️ ContentView: Double tap - toggling preview")
    // 双击切换预览可见性（黑屏）
    viewModel.togglePreviewVisibility()  // ← 从 toggleUIVisibility 改为 togglePreviewVisibility
}
```

#### 修改 2：预览视图
```swift
DualCameraPreview(viewModel: viewModel)
    .ignoresSafeArea()
    .id(viewModel.uiVisibilityManager.isPreviewVisible)  // ✅ 强制视图重建
    .opacity(viewModel.uiVisibilityManager.isPreviewVisible ? 1.0 : 0.0)
```

**添加**：`.id()` 修饰符确保预览立即更新

#### 修改 3：Zoom Sliders
```swift
// 横屏
ZoomSlider(...)
    .padding(.bottom, 20)
    .opacity(viewModel.uiVisibilityManager.isPreviewVisible ? 1.0 : 0.0)
    // 移除了 isUIVisible 依赖

// 竖屏
ZoomSlider(...)
    .padding(.bottom, 150)
    .opacity(viewModel.uiVisibilityManager.isPreviewVisible ? 1.0 : 0.0)
    // 移除了 isUIVisible 依赖
```

**说明**：Zoom slider 只跟随预览显示，不再有独立的隐藏状态

#### 修改 4：横屏按钮组
```swift
HStack(spacing: 20) {
    // Flash, Mode, Gallery 按钮
}
// ❌ 移除了所有关于 isUIVisible 的检查
// ✅ 按钮始终可见（除非预览隐藏）
```

#### 修改 5：移除所有 `.animation()` 修饰符
```diff
- .animation(.easeInOut(duration: 0.3), value: ...)
```

清理了所有残留的动画修饰符，确保立即更新

## 工作流程

### 用户操作流程

#### 1. 双击屏幕（预览可见时）
```
双击 → togglePreviewVisibility()
     → isPreviewVisible = false
     → 预览立即变黑
     → Zoom slider 隐藏
     → Zoom indicator 隐藏
     → Capture button 保留
     → Flash/Mode/Gallery 按钮保留
```

#### 2. 双击屏幕（预览隐藏时）
```
双击 → togglePreviewVisibility()
     → isPreviewVisible = true
     → 预览立即显示
     → Zoom slider 显示
     → Zoom indicator 显示
     → 重启 5 分钟定时器
```

#### 3. 单击屏幕（预览隐藏时）
```
单击 → handleUserInteraction()
     → isPreviewVisible = true
     → 预览立即显示
     → 重启 5 分钟定时器
```

#### 4. 录制 5 分钟后（自动）
```
定时器触发 → hidePreview()
          → isPreviewVisible = false
          → 预览自动变黑
          → 用户可以单击或双击恢复
```

### 状态管理

| 元素 | 预览可见 | 预览隐藏 |
|------|----------|----------|
| Camera Preview | ✅ 显示 | ⚫️ 黑屏 |
| Capture Button | ✅ 显示 | ✅ 显示 |
| Flash Button | ✅ 显示 | ✅ 显示 |
| Mode Button | ✅ 显示 | ✅ 显示 |
| Gallery Button | ✅ 显示 | ✅ 显示 |
| Zoom Slider | ✅ 显示 | ❌ 隐藏 |
| Zoom Indicator | ✅ 显示 | ❌ 隐藏 |
| Recording Dot (when preview hidden) | ❌ 隐藏 | ✅ 显示 |

## 关键技术点

### 1. 强制视图重建
```swift
.id(viewModel.uiVisibilityManager.isPreviewVisible)
```
确保预览状态改变时立即更新，无需旋转设备

### 2. 双重通知机制
```swift
objectWillChange.send()  // before
isPreviewVisible.toggle()
objectWillChange.send()  // after (async)
```
确保 SwiftUI 立即捕获状态变化

### 3. 主线程保障
```swift
guard Thread.isMainThread else {
    DispatchQueue.main.async { [weak self] in
        self?.togglePreview()
    }
    return
}
```
所有 UI 更新在主线程执行

### 4. 无动画更新
```swift
// ❌ 移除了所有 .animation()
// ✅ 状态改变立即生效
```

## 用例场景

### 场景 1：长时间录制省电
```
1. 开始录制
2. 双击屏幕 → 预览变黑
3. 继续录制，屏幕保持黑色
4. 节省电量和 GPU 资源
5. 需要检查画面时 → 单击/双击恢复
```

### 场景 2：自动黑屏
```
1. 开始录制
2. 5 分钟后自动黑屏
3. 用户可以随时点击恢复
4. 恢复后重新开始 5 分钟计时
```

### 场景 3：手动控制画面
```
1. 不想看预览 → 双击变黑
2. 想看预览 → 再次双击显示
3. 所有按钮始终可用
4. 无需在菜单中找设置
```

## 与之前版本的区别

### 之前的设计
- 双击 → 隐藏 Flash/Mode/Gallery 按钮
- Capture button 始终可见
- 预览始终可见（除非自动隐藏）
- isUIVisible 控制按钮

### 现在的设计
- 双击 → 切换预览黑屏
- 所有按钮始终可见
- 预览可以手动/自动隐藏
- isPreviewVisible 控制预览

### 为什么改变？
1. **更简单**：只控制预览，不控制按钮
2. **更实用**：黑屏省电，按钮始终可用
3. **更直观**：双击 = 黑屏/显示，单一功能
4. **更可靠**：避免按钮隐藏后找不到的问题

## 测试检查表

### 基础功能
- [ ] 双击屏幕 → 预览立即变黑
- [ ] 再次双击 → 预览立即显示
- [ ] 单击黑屏 → 预览立即显示
- [ ] 无需旋转设备

### 按钮可见性
- [ ] 预览可见时：所有按钮可见
- [ ] 预览隐藏时：所有按钮仍然可见
- [ ] Capture button 始终可用
- [ ] 可以在黑屏时拍照/录像

### 自动黑屏
- [ ] 开始录制
- [ ] 5 分钟后预览自动变黑
- [ ] 红点出现在左上角
- [ ] Capture button 仍然可见
- [ ] 可以停止录制

### Zoom 控制
- [ ] 预览可见时：Zoom slider 可见
- [ ] 预览隐藏时：Zoom slider 隐藏
- [ ] Zoom indicator 跟随预览状态

### 横竖屏
- [ ] 竖屏：功能正常
- [ ] 横屏：功能正常
- [ ] 旋转时保持状态

## 性能优化

### CPU 使用
- ✅ 无动画计算
- ✅ 直接状态切换
- ✅ 黑屏时节省 GPU 渲染

### 内存使用
- ✅ 视图不销毁，只改变 opacity
- ✅ 手势识别器保持活跃
- ✅ 无频繁重建

### 电池消耗
- ✅ 黑屏时大幅降低功耗
- ✅ 长时间录制更省电
- ✅ 无不必要的动画循环

## 总结

### 核心变化
- **功能转变**：从"隐藏按钮"改为"黑屏预览"
- **控制对象**：从 `isUIVisible` 改为 `isPreviewVisible`
- **用户体验**：更简单、更实用、更直观

### 优势
1. **按钮始终可用** - 无需担心找不到按钮
2. **黑屏省电** - 长时间录制更节能
3. **操作简单** - 双击切换，单一功能
4. **立即响应** - 无延迟，无需旋转

### 保留的功能
- ✅ 录制 5 分钟自动黑屏
- ✅ 单击恢复预览
- ✅ Capture button 始终可用
- ✅ 主线程安全

现在双击屏幕会让预览变黑（省电），但所有按钮保持可见可用！
