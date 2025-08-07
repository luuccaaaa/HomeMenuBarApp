import Foundation
import OSLog

public enum LogCategory: String {
    case app = "app"
    case menu = "menu"
    case state = "state"
    case settings = "settings"
    case homekit = "homekit"
    case ui = "ui"
}

public enum LoggerFactory {
    static let subsystem = "com.homemenubar"

    public static func logger(_ category: LogCategory) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }
}

// Lightweight wrapper to keep callsites concise and gate verbose logs behind DEBUG
public enum HMLog {
    // Default categories for convenience
    private static let app = LoggerFactory.logger(.app)
    private static let menu = LoggerFactory.logger(.menu)
    private static let state = LoggerFactory.logger(.state)
    private static let settings = LoggerFactory.logger(.settings)
    private static let homekit = LoggerFactory.logger(.homekit)
    private static let ui = LoggerFactory.logger(.ui)

    // Generic logging APIs
    @inlinable public static func debug(_ category: LogCategory = .app, _ message: String) {
        #if DEBUG
        LoggerFactory.logger(category).debug("\(message, privacy: .public)")
        #endif
    }

    @inlinable public static func info(_ category: LogCategory = .app, _ message: String) {
        LoggerFactory.logger(category).info("\(message, privacy: .public)")
    }

    @inlinable public static func error(_ category: LogCategory = .app, _ message: String) {
        LoggerFactory.logger(category).error("\(message, privacy: .public)")
    }

    // Shorthands by domain
    @inlinable public static func menuDebug(_ message: String) { debug(.menu, message) }
    @inlinable public static func menuInfo(_ message: String) { info(.menu, message) }
    @inlinable public static func stateDebug(_ message: String) { debug(.state, message) }
    @inlinable public static func stateInfo(_ message: String) { info(.state, message) }
    @inlinable public static func settingsInfo(_ message: String) { info(.settings, message) }
    @inlinable public static func hkDebug(_ message: String) { debug(.homekit, message) }
    @inlinable public static func uiDebug(_ message: String) { debug(.ui, message) }
}
