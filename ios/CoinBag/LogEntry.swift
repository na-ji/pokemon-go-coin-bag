import Foundation

enum LogEventType {
    case paired
    case exchanged
    case failed
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: LogEventType
    let playerName: String?
    let message: String?
}
