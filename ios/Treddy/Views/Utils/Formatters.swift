import Foundation

enum Fmt {
    static func time(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    static func pace(_ mph: Double) -> String {
        guard mph > 0 else { return "--:--" }
        let minPerMile = 60.0 / mph
        let m = Int(minPerMile)
        let s = Int((minPerMile - Double(m)) * 60)
        return String(format: "%d:%02d", m, s)
    }

    static func speed(_ mph: Double) -> String {
        String(format: "%.1f", mph)
    }

    static func duration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return s > 0 ? "\(m):\(String(format: "%02d", s))" : "\(m):00"
    }
}
