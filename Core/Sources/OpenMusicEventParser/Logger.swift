//
//  Logger.swift
//  OpenMusicEventParser
//
//  Created by Claude on 8/6/25.
//

import Foundation
import Dependencies

public protocol OMELogger: Sendable {
    func log(_ message: String, level: LogLevel, file: String, line: Int)
}

public enum LogLevel: String, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"  
    case error = "ERROR"
}

public extension OMELogger {
    func debug(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .debug, file: file, line: line)
    }
    
    func info(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .info, file: file, line: line)
    }
    
    func warning(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .warning, file: file, line: line)
    }
    
    func error(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .error, file: file, line: line)
    }
}

public struct NoOpLogger: OMELogger {
    public init() {}
    
    public func log(_ message: String, level: LogLevel, file: String, line: Int) {
        // No-op implementation
    }
}

public struct ConsoleLogger: OMELogger {
    public init() {}
    
    public func log(_ message: String, level: LogLevel, file: String, line: Int) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(message)")
    }
}

// MARK: - Dependencies Integration

extension DependencyValues {
    public var omeLogger: OMELogger {
        get { self[OMELoggerKey.self] }
        set { self[OMELoggerKey.self] = newValue }
    }
}

private enum OMELoggerKey: DependencyKey {
    static let liveValue: OMELogger = NoOpLogger()
    static let testValue: OMELogger = ConsoleLogger()
}
