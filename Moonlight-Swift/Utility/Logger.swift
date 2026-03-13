//
//  Logger.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 07.03.2026.
//

class Logger: NSObject {
    nonisolated
    static let shared = Logger()

    enum Level {
        case debug
        case info
        case warning
        case error
    }

    nonisolated
    func log(_ text: String, level: Level = .debug) {
        print("[\(level)] \(text)")
    }
}

@objcMembers
class Log: NSObject {
    nonisolated
    static func d(_ text: String) {
        Logger.shared.log(text, level: .debug)
    }

    nonisolated
    static func i(_ text: String) {
        Logger.shared.log(text, level: .info)
    }

    nonisolated
    static func w(_ text: String) {
        Logger.shared.log(text, level: .warning)
    }

    nonisolated
    static func e(_ text: String) {
        Logger.shared.log(text, level: .error)
    }
}
