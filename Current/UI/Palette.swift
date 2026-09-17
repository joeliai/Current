import UIKit

enum Palette {
    static let background = adaptive(0xF7F8FA, 0x111414)
    static let surface = adaptive(0xFFFFFF, 0x1D2222)
    static let ink = adaptive(0x17201F, 0xF2F6F5)
    static let secondary = adaptive(0x6C7575, 0xA0AAAA)
    static let separator = adaptive(0xE3E7E8, 0x303838)
    static let accent = adaptive(0x087F69, 0x66E3BE)
    static let mint = adaptive(0x26B990, 0x5FDFB9)
    static let lime = adaptive(0xABD946, 0xCAE978)
    static let coral = adaptive(0xC76554, 0xF59986)
    static let blue = adaptive(0x527DBE, 0x9BBAEE)
    static let amber = adaptive(0xA37020, 0xEDC274)

    static func font(
        _ size: CGFloat,
        weight: UIFont.Weight = .regular,
        style: UIFont.TextStyle = .body,
        maximumSize: CGFloat? = nil,
        monospaced: Bool = false
    ) -> UIFont {
        let base = monospaced
            ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : UIFont.systemFont(ofSize: size, weight: weight)
        if let maximumSize {
            return UIFontMetrics(forTextStyle: style).scaledFont(for: base, maximumPointSize: maximumSize)
        }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }

    static func adaptive(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { traits in UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light) }
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum ReadingFormat {
    static func number(_ value: Double?, digits: Int = 1) -> String {
        guard let value, value.isFinite else { return "--" }
        return value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func measurement(_ value: Double?, unit: String, digits: Int = 1) -> String {
        guard value != nil else { return "Unavailable" }
        return "\(number(value, digits: digits)) \(unit)"
    }

    static func percent(_ level: Double?) -> String {
        guard let level else { return "--" }
        return "\(number(level * 100, digits: 0))%"
    }

    static func gain(_ value: Double?) -> String {
        guard let value else { return "--" }
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(number(value, digits: 1)) pts"
    }

    static func duration(_ interval: TimeInterval) -> String {
        let seconds = Int(max(0, interval))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m \(seconds % 60)s" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
