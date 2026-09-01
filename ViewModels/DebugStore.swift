import Foundation
import Observation

/// Singleton debug log used by the secret debug mode (10 taps on version in Settings).
/// Receives log entries from AircraftDataStore and displays them in an overlay sheet.
@MainActor
@Observable
final class DebugStore {
    static let shared = DebugStore()
    private init() {}

    var isEnabled: Bool = false
    private(set) var entries: [LogEntry] = []

    private let maxEntries = 300

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let isError: Bool
    }

    func log(_ message: String, isError: Bool = false) {
        #if DEBUG
        entries.insert(LogEntry(timestamp: .now, message: message, isError: isError), at: 0)
        if entries.count > maxEntries { entries.removeLast() }
        #endif
    }

    func clear() {
        #if DEBUG
        entries = []
        #endif
    }

    func toggle() {
        #if DEBUG
        isEnabled.toggle()
        if isEnabled {
            entries = []
            log("🐛 Debug mode activated")
        }
        #endif
    }
}
