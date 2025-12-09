# 视频录制调试修复

## 问题症状

1. **预览冻结**: 点击开始录制后,预览画面完全卡住
2. **无法保存**: 停止录制后不保存任何视频文件

## 可能原因分析

### 原因 1: 预览冻结

**可能问题**:
1. 预览定时器与录制冲突
2. 帧处理队列被阻塞
3. 主线程被占用

**诊断方法**:
- 检查录制时是否仍有 "Received XX frames" 日志
- 如果有帧日志,说明相机正常,问题在预览UI
- 如果没有帧日志,说明相机会话被暂停

### 原因 2: 视频无法保存

**可能问题**:
1. Writer session 未启动
2. 没有帧被写入
3. Writer finishWriting 失败

**诊断方法**:
- 检查是否有 "Writer session started" 日志
- 检查是否有 "frames appended" 日志
- 检查 finishWriting 的状态和错误

## 添加的调试日志

### 开始录制
```
✅ Writers started - status:
   Back: 1 (writing)
   Front: 1 (writing)
   Audio: 1 (writing)
✅ Recording started - isRecording = true
```

### 录制中 (每30帧)
```
📹 Received 30 back camera frames
📹 Back video frames appended (count: 60)
```

### 停止录制
```
🎥 Current isRecording = true
🎥 Stopping recording on sessionQueue...
✅ isRecording set to false, timer stopped
🎥 Marking inputs as finished...
🎥 Finishing back writer (status: 1)...
✅ Back video writing completed
   URL: /tmp/back_XXX.mov
   File size: 1234567 bytes
```

## 修复内容

### 1. 添加详细日志

**startVideoRecording**:
- Writer 状态检查
- 添加 completion 回调

**stopVideoRecording**:
- 当前 isRecording 状态
- 每个 writer 的状态和错误
- 输出文件大小验证

**captureOutput (录制中)**:
- 每60帧输出一次写入日志
- 检测无法写入的情况

### 2. 添加延迟

```swift
// Give time for last frames to be written
Thread.sleep(forTimeInterval: 0.5)
```

在标记 finished 前等待0.5秒,确保最后的帧写入完成。

### 3. 文件大小验证

```swift
if let url = self.backOutputURL {
    let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
    print("   File size: \(fileSize) bytes")
}
```

## 测试步骤

### 步骤 1: 开始录制
1. 切换到视频模式
2. 点击红色圆圈开始录制
3. **检查控制台**:
   ```
   ✅ Writers started - status: Back: 1, Front: 1, Audio: 1
   ✅ Recording started - isRecording = true
   ```
4. **检查预览**:
   - 预览是否继续更新?
   - 录制时间计数器是否增加?
5. 等待5-10秒

### 步骤 2: 录制中
1. 录制过程中,**检查控制台**:
   ```
   📹 Received 30 back camera frames  (持续出现)
   📹 Back video frames appended      (持续出现)
   ```
2. **如果没有这些日志**:
   - 检查是否有 "cannot write" 警告
   - 检查 writer 状态

### 步骤 3: 停止录制
1. 点击方形按钮停止
2. **检查控制台**:
   ```
   🎥 Stopping recording...
   ✅ Back video writing completed
      File size: XXX bytes (应该 > 0)
   ✅ Front video writing completed
      File size: XXX bytes (应该 > 0)
   ```
3. **检查相册**:
   - 是否保存了2个视频?
   - 视频是否可以播放?

## 常见问题诊断

### 问题 A: 预览冻结但有帧日志

**症状**:
```
📹 Received 30 back camera frames  ✓ (有日志)
```
但预览画面不动

**原因**: 预览 UI 更新问题,不是录制问题

**解决**:
- 检查 DualCameraPreview 的定时器
- 检查主线程是否被阻塞

### 问题 B: 无帧日志

**症状**:
```
✅ Recording started
(之后没有 "Received XX frames")
```

**原因**: 相机会话被暂停或 delegate 未调用

**解决**:
- 检查 session.isRunning
- 检查 delegate 是否设置

### 问题 C: Writer session 未启动

**症状**:
```
✅ Recording started
📹 Received 30 frames
⚠️ Back recording but cannot write  ← 警告!
```

**原因**: Writer 状态不是 .writing

**解决**:
- 检查 writer.status
- 检查 startWriting() 是否成功

### 问题 D: 文件大小为 0

**症状**:
```
✅ Back video writing completed
   File size: 0 bytes  ← 问题!
```

**原因**: 没有帧被写入

**解决**:
- 检查是否有 "frames appended" 日志
- 检查 writer session 是否启动
- 检查 isReadyForMoreMediaData

### 问题 E: Writer 错误

**症状**:
```
❌ Back video writing failed
   Status: 3 (failed)
   Error: ...
```

**原因**: Writer 配置或写入错误

**解决**:
- 检查错误信息
- 检查输出 URL 是否有效
- 检查磁盘空间

## 预期成功输出

### 完整成功日志示例

```
🎥 startVideoRecording called
✅ Writers started - status: Back: 1, Front: 1, Audio: 1
✅ Recording started - isRecording = true

📹 Received 30 back camera frames
📹 Received 30 front camera frames
✅ Back video writer session started at 0.5
✅ Front video writer session started at 0.5

📹 Received 60 back camera frames
📹 Back video frames appended (count: 60)

📹 Received 90 back camera frames
📹 Back video frames appended (count: 120)

🎥 stopVideoRecording called
🎥 Current isRecording = true
🎥 Stopping recording on sessionQueue...
✅ isRecording set to false, timer stopped
🎥 Finishing back writer (status: 1)...
🎥 Finishing front writer (status: 1)...
✅ Back video writing completed
   URL: /tmp/back_XXX.mov
   File size: 2456789 bytes
✅ Front video writing completed
   URL: /tmp/front_XXX.mov
   File size: 2345678 bytes

✅ ViewModel: Back camera video saved
✅ ViewModel: Front camera video saved
2 video(s) saved successfully!
```

## 下一步行动

### 如果预览冻结

1. 检查是否有帧日志
2. 如果有帧,问题在 DualCameraPreview
3. 可能需要降低预览刷新率或优化 UI

### 如果无法保存

1. 查看停止录制的日志
2. 找到具体失败点
3. 根据错误信息修复

### 收集信息

运行测试后,提供以下信息:
1. 完整的控制台日志(从开始录制到停止)
2. 预览是否冻结?
3. 录制时间计数器是否增加?
4. 是否保存了视频?文件大小?
5. 任何错误信息

## 已修改的文件

**CameraManager.swift**
- `startVideoRecording`: 添加 writer 状态日志和 completion 回调
- `stopVideoRecording`: 添加详细的完成日志和文件大小检查
- `captureOutput`: 添加帧写入日志和警告信息
- 添加 0.5秒延迟确保最后帧写入
