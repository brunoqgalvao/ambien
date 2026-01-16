//
//  BrandAssets.swift
//  MeetingRecorder
//
//  Design tokens from Brandbook v6 (Playful Pop)
//

import SwiftUI

// MARK: - Brand Colors

extension Color {
    static let brandViolet = Color(hex: "8B5CF6")
    static let brandVioletBright = Color(hex: "A78BFA")
    static let brandVioletDeep = Color(hex: "6D28D9")
    static let brandCream = Color(hex: "FAF7F2")
    static let brandCreamDark = Color(hex: "F0EBE0")
    static let brandInk = Color(hex: "0F0F11")
    static let brandCoral = Color(hex: "FF6B6B")
    static let brandCoralPop = Color(hex: "FF8787")
    static let brandMint = Color(hex: "4ADE80")
    static let brandYellow = Color(hex: "FBBF24")
    static let brandAmber = Color(hex: "F59E0B")
    
    // Semantic aliases
    static let brandBackground = brandCream
    static let brandSurface = Color.white
    static let brandTextPrimary = brandInk
    static let brandTextSecondary = brandInk.opacity(0.6)
    static let brandBorder = brandInk.opacity(0.1)
    
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Brand Corner Radius

struct BrandRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 16
    static let large: CGFloat = 32
    static let pill: CGFloat = 999
}

// MARK: - Brand Fonts

extension Font {
    // Using system fonts as fallback since custom fonts might not be loaded
    // Syne -> System Display (Rounded if possible)
    // Instrument Serif -> System Serif
    // DM Mono -> System Monospaced
    
    static func brandDisplay(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        return .system(size: size, weight: weight, design: .rounded)
    }
    
    static func brandSerif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return .system(size: size, weight: weight, design: .serif)
    }
    
    static func brandMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return .system(size: size, weight: weight, design: .monospaced)
    }
}
