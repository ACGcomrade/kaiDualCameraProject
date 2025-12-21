//
//  SaveProgressIndicator.swift
//  dualCamera
//
//  保存进度指示器 - 显示在左上角
//

import SwiftUI

struct SaveProgressIndicator: View {
    @ObservedObject var saveQueue: SaveQueueManager

    var body: some View {
        // 只在有待处理任务时渲染，减少不必要的重绘
        Group {
            if saveQueue.pendingTasksCount > 0 {
                indicatorView
            }
        }
    }

    private var indicatorView: some View {
        HStack(spacing: 8) {
            // 旋转的加载图标
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(0.8)

            // 显示待处理任务数量
            Text("保存中 \(saveQueue.pendingTasksCount)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.7))
        )
        .transition(.opacity)
    }
}

/// 简化版 - 只显示图标
struct SaveProgressIndicatorCompact: View {
    @ObservedObject var saveQueue: SaveQueueManager

    var body: some View {
        if saveQueue.isProcessing {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.7))
                    .frame(width: 32, height: 32)

                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.7)

                // 任务数量badge
                if saveQueue.pendingTasksCount > 1 {
                    Text("\(saveQueue.pendingTasksCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Circle().fill(Color.red))
                        .offset(x: 12, y: -12)
                }
            }
            .transition(.scale.combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: saveQueue.isProcessing)
        }
    }
}
