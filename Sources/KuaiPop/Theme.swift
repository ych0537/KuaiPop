import AppKit
import SwiftUI

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    /// Light / dark adaptive color.
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

/// Theme colors the user can choose (設定 › 表示と言語). Light/dark follows the system.
enum ThemePalette: String, CaseIterable, Identifiable {
    case blue, green, mono, lavender, sakura, orange
    var id: String { rawValue }

    var title: String {
        switch self {
        case .mono: return L("モノクロ")
        case .blue: return L("ライトブルー")
        case .green: return L("ライトグリーン")
        case .lavender: return L("ラベンダー")
        case .sakura: return L("さくら")
        case .orange: return L("オレンジ")
        }
    }

    static var current: ThemePalette {
        ThemePalette(rawValue: UserDefaults.standard.string(forKey: PrefKey.theme) ?? "") ?? .blue
    }

    /// (light, dark) pairs. Accents keep ≥ 4.5:1 contrast for text on white / dark surfaces.
    var accentHex: (UInt32, UInt32) {
        switch self {
        case .blue: return (0x2F5BD3, 0x7FA2FF)
        case .green: return (0x23794A, 0x6FD39A)
        case .mono: return (0x1D1F23, 0xECEEF2)
        case .lavender: return (0x6550C4, 0xA994FF)
        case .sakura: return (0xB8375F, 0xFF8FB1)
        case .orange: return (0xB25210, 0xFFA060)
        }
    }
    var strongHex: (UInt32, UInt32) {
        switch self {
        case .blue: return (0x1E3F9E, 0x9DB8FF)
        case .green: return (0x185C37, 0x9BE3B8)
        case .mono: return (0x111214, 0xFFFFFF)
        case .lavender: return (0x4C3A9E, 0xC4B5FF)
        case .sakura: return (0x8F2A4A, 0xFFB3CA)
        case .orange: return (0x8A3F0C, 0xFFC08F)
        }
    }
    var tintBgHex: (UInt32, UInt32) {
        switch self {
        case .blue: return (0xF3F6FD, 0x253047)
        case .green: return (0xEEF8F1, 0x1F3328)
        case .mono: return (0xF4F4F5, 0x2C2D31)
        case .lavender: return (0xF5F2FD, 0x2D2745)
        case .sakura: return (0xFDF1F5, 0x3A2430)
        case .orange: return (0xFDF4EC, 0x3A2A1D)
        }
    }
    var navHex: (UInt32, UInt32) {
        switch self {
        case .blue: return (0xDFE6F7, 0x2E3A55)
        case .green: return (0xDDF1E4, 0x284433)
        case .mono: return (0xE6E7EA, 0x3A3C42)
        case .lavender: return (0xE7E1FA, 0x3A3159)
        case .sakura: return (0xF8DCE6, 0x4A2D3B)
        case .orange: return (0xF8E3D2, 0x4A3423)
        }
    }
    /// Text/icon color on top of `accent` fills.
    var onAccentHex: (UInt32, UInt32) {
        self == .mono ? (0xFFFFFF, 0x1D1F23) : (0xFFFFFF, 0x14161A)
    }

    /// Swatch for the picker (light variant).
    var swatch: Color { Color(nsColor: NSColor(hex: accentHex.0)) }
}

/// Colors from the design canvas (選択アシスト · Mac ツール UI 設計), with dark-mode counterparts.
/// Accent-related colors follow the chosen ThemePalette.
enum Theme {
    private static var p: ThemePalette { .current }

    static let text = Color.dyn(0x1D1F23, 0xECEEF2)
    static let textSub = Color.dyn(0x3A3E46, 0xC9CED6)
    static let secondary = Color.dyn(0x5E636E, 0xA4AAB4)
    static let surface = Color.dyn(0xFFFFFF, 0x26282D)
    static let chip = Color.dyn(0xEEF1F5, 0x383B42)
    static let chipHover = Color.dyn(0xE1E6EE, 0x45484F)
    static let resultText = Color.dyn(0x2B3440, 0xDCE3EE)
    static let divider = Color.dyn(0xEEF0F3, 0x383B42)
    static let border = Color.dyn(0xE3E6EB, 0x44474F)
    static let footer = Color.dyn(0xF7F8FA, 0x202226)
    static let todayDue = Color.dyn(0xB4461B, 0xFF9A6B)
    static let sidebar = Color.dyn(0xF3F4F7, 0x1F2125)
    static let okBg = Color.dyn(0xEEF7F1, 0x1E3326)
    static let okText = Color.dyn(0x1F5A35, 0x8FD6A6)
    static let warnBg = Color.dyn(0xFDF2E7, 0x3A2A1A)
    static let warnText = Color.dyn(0x8A4B12, 0xF5B77A)

    static var accent: Color { .dyn(p.accentHex.0, p.accentHex.1) }
    static var accentStrong: Color { .dyn(p.strongHex.0, p.strongHex.1) }
    static var onAccent: Color { .dyn(p.onAccentHex.0, p.onAccentHex.1) }
    static var resultBg: Color { .dyn(p.tintBgHex.0, p.tintBgHex.1) }
    static var navSelected: Color { .dyn(p.navHex.0, p.navHex.1) }
    static var chipSelected: Color { accent }
    static var chipSelectedText: Color { onAccent }
}
