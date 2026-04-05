import Foundation

enum AppRoute: String, Hashable {
    case setup
    case profilePicker
    case lobby
    case running
    case debug

    var label: String {
        switch self {
        case .setup: return "Setup"
        case .profilePicker: return "Profiles"
        case .lobby: return "Lobby"
        case .running: return "Running"
        case .debug: return "Debug"
        }
    }
}
