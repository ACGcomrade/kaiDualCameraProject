# 智能曝光和对焦系统

## 📋 概述

新增的智能曝光管理系统，能够自动优化相机的曝光、ISO和对焦设置，解决前置摄像头画面过暗、后置摄像头过曝等问题。

## ✨ 核心功能

### 1. **人脸检测优先对焦**
- 使用 Vision 框架实时检测人脸
- 自动将焦点和曝光点设置在最大的人脸位置
- 确保人物主体清晰且曝光准确

### 2. **智能曝光补偿**
- **前置摄像头**：默认增加 +0.5 EV 曝光补偿，画面更明亮
- **后置摄像头**：默认减少 -0.3 EV 曝光补偿，防止高光过曝
- 根据场景亮度动态调整

### 3. **自适应ISO控制**
- **前置摄像头**：提升 30% ISO，增强弱光表现
- **后置摄像头**：限制最大 ISO 为 800，减少噪点
- 最小 ISO 设置为 50，保证画质

### 4. **场景亮度分析**
- 实时分析画面中心区域的亮度
- **过亮场景**（>80% 亮度）：降低曝光补偿到 -0.8 EV
- **过暗场景**（<30% 亮度）：提高曝光补偿到 +1.0 EV
- **正常场景**：使用默认相机补偿值

### 5. **连续自动对焦和曝光**
- 启用连续自动对焦模式，实时跟踪移动物体
- 启用连续自动曝光模式，适应光线变化
- 启用主体区域变化监控

### 6. **自动白平衡**
- 连续自动白平衡，确保色彩准确

## 🔧 技术实现

### 文件结构
```
dualCamera/Managers/
├── SmartExposureManager.swift  (新增)
└── CameraManager.swift         (已更新)
```

### 关键类：SmartExposureManager

#### 主要方法

1. **configureCamera(_:isFrontCamera:)**
   - 初始化相机时调用
   - 设置曝光补偿、ISO、对焦模式等

2. **detectFaces(in:)**
   - 使用 VNDetectFaceRectanglesRequest 检测人脸
   - 返回最大人脸的中心点坐标

3. **applySmartFocusAndExposure(to:sampleBuffer:isFrontCamera:)**
   - 每秒调用一次（每30帧）
   - 优先人脸检测，其次场景分析

4. **analyzeSceneBrightness(sampleBuffer:completion:)**
   - 分析画面中心区域亮度
   - 采样 BGRA 像素并计算平均亮度

5. **setManualFocusAndExposure(on:at:isFrontCamera:)**
   - 处理用户点击对焦

## 🎯 使用场景

### 自动优化场景
1. **人像拍摄**：自动检测人脸并优化曝光
2. **自拍**：前置摄像头自动增亮
3. **逆光场景**：提升曝光补偿
4. **强光场景**：降低曝光防止过曝
5. **移动物体**：连续对焦跟踪

### 手动对焦
- 用户点击屏幕时，系统会：
  1. 设置焦点到点击位置
  2. 设置曝光点到点击位置
  3. 应用智能曝光补偿

## 📊 性能优化

- **更新频率**：每30帧（约1秒）更新一次，避免过度占用CPU
- **人脸检测**：使用 VNSequenceRequestHandler 复用，性能优化
- **场景分析**：仅采样中心区域的部分像素，快速计算
- **异步处理**：亮度分析在后台线程完成

## 🔍 参数调优

### 可调整参数（SmartExposureManager.swift）

```swift
// 曝光补偿
private let frontCameraExposureBias: Float = 0.5   // 前置相机
private let backCameraExposureBias: Float = -0.3   // 后置相机

// ISO 范围
private let minISO: Float = 50
private let maxISO: Float = 800
private let frontCameraISOBoost: Float = 1.3       // 前置相机ISO增强

// 场景亮度阈值
if brightness > 0.8 { /* 过亮 */ }
if brightness < 0.3 { /* 过暗 */ }
```

## 🐛 调试信息

系统会输出详细的日志：

```
✅ SmartExposure: Exposure bias set to 0.5 for front camera
📊 SmartExposure: Front camera ISO range: 29.0-1392.0, target: 537.6
👤 SmartExposure: Face detected at (0.5, 0.45)
🎯 SmartExposure: Focus point set to (0.5, 0.45) (face detection)
☀️ SmartExposure: Bright scene detected, reducing exposure bias to -0.8
🌙 SmartExposure: Dark scene detected, increasing exposure bias to 1.0
```

## ✅ 测试要点

### 前置摄像头测试
- [ ] 室内弱光环境 - 画面应该比之前更明亮
- [ ] 人脸检测 - 应自动对焦到人脸
- [ ] 窗户逆光 - 人脸应该清晰可见

### 后置摄像头测试
- [ ] 拍摄灯光 - 灯光不应过曝
- [ ] 高对比场景 - 亮部和暗部都应有细节
- [ ] 人物拍摄 - 应自动对焦到人脸

### 动态测试
- [ ] 移动设备 - 焦点应平滑跟踪
- [ ] 改变光线 - 曝光应自动调整
- [ ] 手动点击对焦 - 应正确响应

## 🔄 更新日志

**2025-12-15**
- ✅ 创建 SmartExposureManager
- ✅ 集成到 CameraManager
- ✅ 添加人脸检测功能
- ✅ 实现场景亮度分析
- ✅ 优化前后摄像头曝光参数
- ✅ 每秒自动应用智能曝光

## 📝 注意事项

1. **隐私**：人脸检测仅用于对焦，不保存任何人脸数据
2. **性能**：在低端设备上，可以调整更新频率（如每60帧更新一次）
3. **手动控制**：用户点击屏幕时会暂时覆盖自动设置
4. **极端光线**：在极暗或极亮环境下，可能需要手动调整

## 🚀 未来改进方向

- [ ] 支持物体识别（不仅是人脸）
- [ ] 机器学习场景分类
- [ ] HDR 智能合成
- [ ] 手动曝光滑块控制
- [ ] 保存用户偏好设置
