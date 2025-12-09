# Build Fix - Missing Imports - December 11, 2025

## 问题

编译失败，错误信息：
```
error: Initializer 'init(wrappedValue:)' is not available due to missing import of defining module 'Combine'
error: Type 'CameraSelectorViewModel' does not conform to protocol 'ObservableObject'
```

## 根本原因

新创建的文件缺少必要的 import 语句：

### 1. `CameraSelectorView.swift` ❌
**缺少**:
- `import SwiftUI`
- `import Combine`

**需要这些 import 的原因**:
- `@StateObject` 需要 `Combine` 框架
- `@Published` 需要 `Combine` 框架
- `ObservableObject` 协议定义在 `Combine` 中
- `View`、`NavigationView` 等需要 `SwiftUI`

### 2. `CameraDeviceInfo.swift` ❌
**缺少**:
- `import AVFoundation`

**需要的原因**:
- `AVCaptureDevice` 定义在 `AVFoundation` 中
- `AVCaptureDevice.Position` 枚举在 `AVFoundation` 中
- `AVCaptureDevice.DeviceType` 枚举在 `AVFoundation` 中

## 修复

### 修复 1: CameraSelectorView.swift ✅

**修改前**:
```swift
import AVFoundation

/// Camera selector menu with live previews
struct CameraSelectorView: View {
    @StateObject private var viewModel = CameraSelectorViewModel()  // ❌ Error
    // ...
}
```

**修改后**:
```swift
import SwiftUI        // ✅ 添加
import AVFoundation
import Combine        // ✅ 添加

/// Camera selector menu with live previews
struct CameraSelectorView: View {
    @StateObject private var viewModel = CameraSelectorViewModel()  // ✅ 正常
    // ...
}
```

### 修复 2: CameraDeviceInfo.swift ✅

**修改前**:
```swift
import UIKit

/// Information about a camera device
struct CameraDeviceInfo: Identifiable, Hashable {
    let device: AVCaptureDevice  // ❌ Error: Cannot find type 'AVCaptureDevice'
    // ...
}
```

**修改后**:
```swift
import AVFoundation   // ✅ 添加
import UIKit

/// Information about a camera device
struct CameraDeviceInfo: Identifiable, Hashable {
    let device: AVCaptureDevice  // ✅ 正常
    // ...
}
```

## Import 依赖关系解释

### SwiftUI Framework
**提供**:
- `View` 协议
- `@State`, `@Binding`, `@StateObject` 等属性包装器
- `Text`, `Button`, `VStack`, `HStack` 等视图组件
- `NavigationView`, `ScrollView` 等容器
- `@Environment` 属性包装器

**需要导入的情况**:
- 任何定义 SwiftUI 视图的文件
- 使用 SwiftUI 组件的文件

### Combine Framework
**提供**:
- `ObservableObject` 协议
- `@Published` 属性包装器
- `Publisher` 和相关类型
- 响应式编程工具

**需要导入的情况**:
- 定义 `ObservableObject` 的 ViewModel
- 使用 `@Published` 属性
- 使用 `@StateObject` 或 `@ObservedObject`

### AVFoundation Framework
**提供**:
- `AVCaptureDevice` - 摄像头设备
- `AVCaptureSession` - 捕获会话
- `AVCaptureInput` / `AVCaptureOutput` - 输入输出
- `AVCaptureVideoPreviewLayer` - 预览层
- 所有相机和音视频相关 API

**需要导入的情况**:
- 使用摄像头 API
- 处理音视频捕获
- 创建预览层

### UIKit Framework
**提供**:
- `UIView`, `UIViewController` 等 UI 组件
- `UIImage` - 图像类
- `UIColor` - 颜色类
- UIKit 相关 API

**需要导入的情况**:
- 创建 `UIViewRepresentable` 或 `UIViewControllerRepresentable`
- 使用 `UIImage`
- 桥接 UIKit 和 SwiftUI

## 为什么会漏掉 Import

### 原因分析

1. **AI 创建文件时的疏忽**
   - 创建新文件时没有完整考虑所有依赖
   - 关注功能实现，忽略了基础 import

2. **代码块复制**
   - 从其他文件复制代码时，可能漏掉头部 import

3. **增量编写**
   - 先写基础结构，后添加功能
   - 添加功能时引入新类型，但忘记添加 import

## 检查清单 - 避免类似错误

创建新 Swift 文件时，检查是否需要这些 import：

### SwiftUI 文件
```swift
import SwiftUI        // ✅ 必需：如果定义 View
import Combine        // ✅ 可能需要：如果使用 ObservableObject
import AVFoundation   // ✅ 可能需要：如果使用相机
import UIKit          // ✅ 可能需要：如果使用 UIImage 或桥接 UIKit
```

### ViewModel 文件
```swift
import Foundation     // ✅ 基础类型
import Combine        // ✅ 必需：如果是 ObservableObject
import AVFoundation   // ✅ 可能需要：如果管理相机
```

### UIKit 桥接文件
```swift
import SwiftUI        // ✅ 必需：如果是 UIViewRepresentable
import UIKit          // ✅ 必需：桥接 UIKit
import AVFoundation   // ✅ 可能需要：如果桥接相机相关
```

### 模型/数据文件
```swift
import Foundation     // ✅ 基础类型（String, Int, etc.）
import AVFoundation   // ✅ 可能需要：如果包含 AVFoundation 类型
```

## 编译错误识别指南

### 错误类型 1: Missing Import
```
error: Initializer 'init(wrappedValue:)' is not available due to missing import
```
**原因**: 缺少定义该属性包装器的模块
**解决**: 添加 `import Combine` (对于 @Published, @StateObject)

### 错误类型 2: Protocol Conformance
```
error: Type 'XXX' does not conform to protocol 'ObservableObject'
```
**原因**: `ObservableObject` 定义在 `Combine` 中
**解决**: 添加 `import Combine`

### 错误类型 3: Cannot Find Type
```
error: Cannot find type 'AVCaptureDevice' in scope
```
**原因**: 类型定义在未导入的模块中
**解决**: 添加 `import AVFoundation`

### 错误类型 4: Cannot Find Name
```
error: Cannot find 'View' in scope
```
**原因**: 协议/类型定义在未导入的模块中
**解决**: 添加 `import SwiftUI`

## 文件头部标准模板

### SwiftUI View 文件
```swift
import SwiftUI
import Combine        // 如果使用 @StateObject 或 @ObservedObject
import AVFoundation   // 如果使用相机

struct MyView: View {
    var body: some View {
        // ...
    }
}
```

### ViewModel 文件
```swift
import Foundation
import Combine
import AVFoundation   // 如果管理相机

class MyViewModel: ObservableObject {
    @Published var someProperty: String = ""
    // ...
}
```

### 工具类文件
```swift
import Foundation
import AVFoundation   // 如果使用 AVFoundation 类型

class MyUtility {
    // ...
}
```

## 验证修复

### 编译测试
1. Clean Build Folder (Cmd + Shift + K)
2. Build (Cmd + B)
3. 确认无错误

### 预期结果
```
✅ Build Succeeded
```

### 如果仍有错误
检查：
1. 所有新文件是否添加到 target
2. 文件路径是否正确
3. 是否有循环依赖
4. 其他文件是否需要更新 import

## 总结

✅ **修复完成**:
1. `CameraSelectorView.swift` - 添加 `SwiftUI` 和 `Combine` import
2. `CameraDeviceInfo.swift` - 添加 `AVFoundation` import

✅ **学到的经验**:
- 创建新文件时，首先添加所有必要的 import
- 使用 `@StateObject` 或 `@Published` 必须 import `Combine`
- 使用相机 API 必须 import `AVFoundation`
- SwiftUI 文件必须 import `SwiftUI`

✅ **避免类似错误**:
- 使用文件模板
- 创建文件后立即添加 import
- 编译前检查依赖关系
- 参考项目中已有的类似文件

现在应该可以成功编译了！🎉
