import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Central design token system for Pedef's brand identity.
/// All colors, typography, spacing, radii, shadows, and animations are defined here.
/// Adaptive colors use platform-specific dynamic providers for automatic light/dark switching.
enum PedefTheme {

    // MARK: - Brand Colors

    enum Brand {
        /// Indigo: dark #2D3561 / light-on-dark #7B8ABF for WCAG contrast
        static let indigo = Color.adaptive(
            light: Color(red: 0.176, green: 0.208, blue: 0.380),
            dark:  Color(red: 0.482, green: 0.541, blue: 0.749)
        )
        /// Purple: dark #6C3483 / light-on-dark #B07CC6 for WCAG contrast
        static let purple = Color.adaptive(
            light: Color(red: 0.424, green: 0.204, blue: 0.514),
            dark:  Color(red: 0.690, green: 0.486, blue: 0.776)
        )

        static let gradient = LinearGradient(
            colors: [indigo, purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Surface Colors (adaptive light/dark)

    enum Surface {
        /// Main window background — light warm gray / dark navy
        static let primary = Color.adaptive(
            light: Color(red: 0.980, green: 0.980, blue: 0.980),
            dark:  Color(red: 0.102, green: 0.102, blue: 0.180)
        )

        /// Cards, popovers — white / slightly lighter navy
        static let elevated = Color.adaptive(
            light: Color(red: 1.000, green: 1.000, blue: 1.000),
            dark:  Color(red: 0.133, green: 0.133, blue: 0.220)
        )

        /// Sidebar background
        static let sidebar = Color.adaptive(
            light: Color(red: 0.961, green: 0.961, blue: 0.973),
            dark:  Color(red: 0.086, green: 0.086, blue: 0.165)
        )

        /// Toolbars, bars
        static let bar = Color.adaptive(
            light: Color(red: 0.973, green: 0.973, blue: 0.980),
            dark:  Color(red: 0.110, green: 0.110, blue: 0.192)
        )

        /// Hover states
        static let hover = Color.adaptive(
            light: Color(red: 0.937, green: 0.937, blue: 0.953),
            dark:  Color(red: 0.157, green: 0.157, blue: 0.247)
        )

        /// Selected states (brand indigo tint)
        static let selected = Color.adaptive(
            light: Color(red: 0.176, green: 0.208, blue: 0.380, opacity: 0.12),
            dark:  Color(red: 0.361, green: 0.404, blue: 0.592, opacity: 0.15)
        )
    }

    // MARK: - Text Colors (adaptive light/dark)

    enum TextColor {
        /// Near-black / near-white
        static let primary = Color.adaptive(
            light: Color(red: 0.090, green: 0.090, blue: 0.110),
            dark:  Color(red: 0.945, green: 0.945, blue: 0.961)
        )

        /// Mid-gray
        static let secondary = Color.adaptive(
            light: Color(red: 0.420, green: 0.420, blue: 0.460),
            dark:  Color(red: 0.620, green: 0.620, blue: 0.680)
        )

        /// Light gray / dark gray
        static let tertiary = Color.adaptive(
            light: Color(red: 0.580, green: 0.580, blue: 0.620),
            dark:  Color(red: 0.440, green: 0.440, blue: 0.500)
        )

        static let onBrand = Color.white
    }

    // MARK: - Semantic Colors (adaptive light/dark)

    enum Semantic {
        static let success = Color.adaptive(
            light: Color(red: 0.133, green: 0.722, blue: 0.443),
            dark:  Color(red: 0.204, green: 0.827, blue: 0.600)
        )

        /// Amber tone for better contrast on both light and dark backgrounds
        static let warning = Color.adaptive(
            light: Color(red: 0.820, green: 0.580, blue: 0.059),
            dark:  Color(red: 0.961, green: 0.780, blue: 0.259)
        )

        static let error = Color.adaptive(
            light: Color(red: 0.973, green: 0.443, blue: 0.443),
            dark:  Color(red: 0.945, green: 0.494, blue: 0.494)
        )

        static let info = Color.adaptive(
            light: Color(red: 0.376, green: 0.647, blue: 0.980),
            dark:  Color(red: 0.443, green: 0.698, blue: 0.961)
        )
    }

    // MARK: - Typography

    enum Typography {
        static let title = Font.system(size: 26, weight: .bold, design: .default)
        static let title2 = Font.system(size: 22, weight: .semibold, design: .default)
        static let title3 = Font.system(size: 18, weight: .semibold, design: .default)
        static let headline = Font.system(size: 15, weight: .semibold, design: .default)
        static let body = Font.system(size: 14, weight: .regular, design: .default)
        static let callout = Font.system(size: 13, weight: .regular, design: .default)
        static let subheadline = Font.system(size: 12, weight: .medium, design: .default)
        static let footnote = Font.system(size: 11, weight: .regular, design: .default)
        static let caption = Font.system(size: 11, weight: .medium, design: .default)
        static let caption2 = Font.system(size: 10, weight: .medium, design: .default)
    }

    // MARK: - Spacing (4pt grid)

    enum Spacing {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        static let xxxxl: CGFloat = 40
    }

    // MARK: - Corner Radii

    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let pill: CGFloat = 100
    }

    // MARK: - Shadows

    enum Shadow {
        static let sm = ShadowStyle(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
        static let md = ShadowStyle(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        static let lg = ShadowStyle(color: .black.opacity(0.10), radius: 12, x: 0, y: 4)
        static let card = ShadowStyle(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    // MARK: - Animation

    enum Animation {
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let spring = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.7)
        static let gentle = SwiftUI.Animation.easeOut(duration: 0.35)
    }

    // MARK: - Annotation Palette (Tailwind-inspired, cohesive)

    enum AnnotationPalette {
        static let yellow = "#F5C842"
        static let green = "#34D399"
        static let blue = "#60A5FA"
        static let pink = "#F472B6"
        static let purple = "#A78BFA"
        static let orange = "#FB923C"
        static let red = "#F87171"
    }

    // MARK: - Collection Palette

    enum CollectionPalette {
        static let colors: [(name: String, hex: String)] = [
            ("Indigo", "#2D3561"),
            ("Purple", "#6C3483"),
            ("Blue", "#3B82F6"),
            ("Teal", "#14B8A6"),
            ("Green", "#22C55E"),
            ("Yellow", "#EAB308"),
            ("Orange", "#F97316"),
            ("Pink", "#EC4899"),
            ("Gray", "#6B7280"),
        ]
    }

    // MARK: - Tag Palette

    enum TagPalette {
        static let colors: [String] = [
            "#6366F1",  // Indigo
            "#8B5CF6",  // Violet
            "#EC4899",  // Pink
            "#F43F5E",  // Rose
            "#EF4444",  // Red
            "#F97316",  // Orange
            "#EAB308",  // Yellow
            "#22C55E",  // Green
            "#14B8A6",  // Teal
            "#3B82F6",  // Blue
        ]
    }
}

// MARK: - Shadow Style Helper

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - NSColor Adaptive Helper

#if os(macOS)
extension NSColor {
    /// Creates an adaptive NSColor that automatically switches between light and dark variants.
    static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return dark
            }
            return light
        })
    }
}
#endif
