import Foundation

/// Lightweight logging utility to control debug output
/// Use this instead of print() for better performance in production
class Logger {
    
    /// Log levels
    enum Level: Int, Comparable {
        case verbose = 0
        case debug = 1
        case info = 2
        case warning = 3
        case error = 4
        case none = 5
        
        var emoji: String {
            switch self {
            case .verbose: return "💬"
            case .debug: return "🔧"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            case .none: return ""
            }
        }
        
        static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
    
    /// Current log level - change to .warning or .error for production
    #if DEBUG
    static var currentLevel: Level = .debug
    #else
    static var currentLevel: Level = .warning  // Only warnings and errors in release
    #endif
    
    /// Log a message if it meets the current level threshold
    /// - Parameters:
    ///   - level: Log level
    ///   - message: Message to log
    ///   - file: Source file (auto-filled)
    ///   - function: Function name (auto-filled)
    ///   - line: Line number (auto-filled)
    static func log(
        _ level: Level,
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard level >= currentLevel else { return }
        
        let fileName = (file as NSString).lastPathComponent
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        
        // Only include file/function for errors
        if level >= .error {
            print("\(level.emoji) [\(timestamp)] \(fileName):\(line) \(function) - \(message)")
        } else {
            print("\(level.emoji) \(message)")
        }
    }
    
    /// Convenience methods
    static func verbose(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.verbose, message, file: file, function: function, line: line)
    }
    
    static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, message, file: file, function: function, line: line)
    }
    
    static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message, file: file, function: function, line: line)
    }
    
    static func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.warning, message, file: file, function: function, line: line)
    }
    
    static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message, file: file, function: function, line: line)
    }
    
    /// Measure and log execution time of a closure
    static func measure<T>(
        _ label: String,
        minimumDuration: TimeInterval = 0.01,  // Only log if > 10ms
        level: Level = .debug,
        block: () -> T
    ) -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = block()
        let duration = CFAbsoluteTimeGetCurrent() - start
        
        if duration >= minimumDuration {
            log(level, "⏱️ \(label): \(String(format: "%.2f", duration * 1000))ms")
        }
        
        return result
    }
}
