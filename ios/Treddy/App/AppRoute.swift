import Foundation

enum AppRoute: String, Hashable {
    case lobby
    case running
    case debug

    var label: String {
        switch self {
        case .lobby: return "Lobby"
        case .running: return "Running"
        case .debug: return "Debug"
        }
    }
}
