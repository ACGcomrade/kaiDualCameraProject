import Foundation
import UIKit
import Combine

/// Monitors app performance and adjusts camera preview quality
class PerformanceMonitor: ObservableObject {
    
    @Published var pipQuality: PreviewQuality = .high
    @Published var mainQuality: PreviewQuality = .high
    
    private var cpuUsageHistory: [Float] = []
    private var frameRateHistory: [Double] = []
    private var monitorTimer: Timer?
    
    private let maxHistoryCount = 10
    private let checkInterval: TimeInterval = 5.0  // Reduced frequency to save CPU
    
    // Performance thresholds - more lenient to avoid over-adjustment
    private let highCPUThreshold: Float = 70.0  // 70% CPU usage
    private let criticalCPUThreshold: Float = 85.0  // 85% CPU usage
    private let lowFrameRateThreshold: Double = 20.0  // 20 fps
    
    enum PreviewQuality: Int {
        case high = 0      // Original resolution
        case medium = 1    // 75% resolution
        case low = 2       // 50% resolution
        case veryLow = 3   // 25% resolution
        
        var scale: CGFloat {
            switch self {
            case .high: return 1.0
            case .medium: return 0.75
            case .low: return 0.5
            case .veryLow: return 0.25
            }
        }
        
        var description: String {
            switch self {
            case .high: return "高清"
            case .medium: return "中等"
            case .low: return "低"
            case .veryLow: return "极低"
            }
        }
    }
    
    init() {
        print("📊 PerformanceMonitor: Initialized")
        startMonitoring()
    }
    
    func startMonitoring() {
        monitorTimer?.invalidate()
        
        monitorTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkPerformance()
        }
    }
    
    func stopMonitoring() {
        monitorTimer?.invalidate()
    }
    
    private func checkPerformance() {
        // Get CPU usage
        let cpuUsage = getCPUUsage()
        cpuUsageHistory.append(cpuUsage)
        if cpuUsageHistory.count > maxHistoryCount {
            cpuUsageHistory.removeFirst()
        }
        
        // Calculate average CPU usage
        let avgCPU = cpuUsageHistory.reduce(0, +) / Float(cpuUsageHistory.count)
        
        // Only log if CPU is concerning (> 50%)
        if avgCPU > 50.0 {
            print("📊 PerformanceMonitor: CPU \(String(format: "%.1f", avgCPU))% | PIP: \(pipQuality.description) | Main: \(mainQuality.description)")
        }
        
        // Adjust quality based on CPU usage
        adjustQuality(basedOnCPU: avgCPU)
    }
    
    private func adjustQuality(basedOnCPU cpu: Float) {
        // Critical CPU usage - aggressive downgrade
        if cpu > criticalCPUThreshold {
            // First downgrade PIP to minimum
            if pipQuality.rawValue < PreviewQuality.veryLow.rawValue {
                DispatchQueue.main.async {
                    self.pipQuality = PreviewQuality(rawValue: self.pipQuality.rawValue + 1) ?? .veryLow
                    print("📊 PerformanceMonitor: PIP downgraded to \(self.pipQuality.description)")
                }
            }
            // Then downgrade main preview
            else if mainQuality.rawValue < PreviewQuality.low.rawValue {
                DispatchQueue.main.async {
                    self.mainQuality = PreviewQuality(rawValue: self.mainQuality.rawValue + 1) ?? .low
                    print("📊 PerformanceMonitor: Main downgraded to \(self.mainQuality.description)")
                }
            }
        }
        // High CPU usage - moderate downgrade
        else if cpu > highCPUThreshold {
            // Only downgrade PIP
            if pipQuality.rawValue < PreviewQuality.low.rawValue {
                DispatchQueue.main.async {
                    self.pipQuality = PreviewQuality(rawValue: self.pipQuality.rawValue + 1) ?? .low
                    print("📊 PerformanceMonitor: PIP downgraded to \(self.pipQuality.description)")
                }
            }
        }
        // Low CPU usage - upgrade quality
        else if cpu < highCPUThreshold * 0.7 {  // 42% threshold for upgrade
            // First upgrade main preview
            if mainQuality.rawValue > PreviewQuality.high.rawValue {
                DispatchQueue.main.async {
                    self.mainQuality = PreviewQuality(rawValue: self.mainQuality.rawValue - 1) ?? .high
                    print("📊 PerformanceMonitor: Main upgraded to \(self.mainQuality.description)")
                }
            }
            // Then upgrade PIP
            else if pipQuality.rawValue > PreviewQuality.high.rawValue {
                DispatchQueue.main.async {
                    self.pipQuality = PreviewQuality(rawValue: self.pipQuality.rawValue - 1) ?? .high
                    print("📊 PerformanceMonitor: PIP upgraded to \(self.pipQuality.description)")
                }
            }
        }
    }
    
    private func getCPUUsage() -> Float {
        var totalUsageOfCPU: Float = 0.0
        var threadsList = UnsafeMutablePointer(mutating: [thread_act_t]())
        var threadsCount = mach_msg_type_number_t(0)
        let threadsResult = withUnsafeMutablePointer(to: &threadsList) {
            return $0.withMemoryRebound(to: thread_act_array_t?.self, capacity: 1) {
                task_threads(mach_task_self_, $0, &threadsCount)
            }
        }
        
        if threadsResult == KERN_SUCCESS {
            for index in 0..<threadsCount {
                var threadInfo = thread_basic_info()
                var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threadsList[Int(index)], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                    }
                }
                
                guard infoResult == KERN_SUCCESS else {
                    break
                }
                
                let threadBasicInfo = threadInfo as thread_basic_info
                if threadBasicInfo.flags & TH_FLAGS_IDLE == 0 {
                    totalUsageOfCPU += Float(threadBasicInfo.cpu_usage) / Float(TH_USAGE_SCALE) * 100.0
                }
            }
        }
        
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadsList)), vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride))
        return totalUsageOfCPU
    }
    
    deinit {
        stopMonitoring()
    }
}
