import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Platform Type Aliases

#if os(macOS)
/// Native image type for macOS.
public typealias PlatformImage = NSImage
/// Native color type for macOS.
public typealias PlatformColor = NSColor
#else
/// Native image type for iOS/iPadOS.
public typealias PlatformImage = UIImage
/// Native color type for iOS/iPadOS.
public typealias PlatformColor = UIColor
#endif

// MARK: - Cross-Platform Image Extensions

extension Image {
    /// Creates a SwiftUI Image from the platform-native image type.
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

// MARK: - Cross-Platform Color Extensions

extension Color {
    /// Creates an adaptive SwiftUI Color that automatically switches between light and dark variants.
    /// Uses platform-specific dynamic color providers under the hood.
    static func adaptive(light: Color, dark: Color) -> Color {
        #if os(macOS)
        Color(nsColor: NSColor.adaptive(
            light: NSColor(light),
            dark: NSColor(dark)
        ))
        #else
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
        #endif
    }
}

// MARK: - Cross-Platform Pasteboard

enum PlatformPasteboard {
    /// Copies a string to the system pasteboard.
    static func copy(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }
}

// MARK: - Cross-Platform File Reveal

enum PlatformFileActions {
    /// Reveals a file in the system file browser (Finder on macOS).
    /// On iOS, this is a no-op since there is no Finder equivalent.
    static func revealInFileBrowser(url: URL) {
        #if os(macOS)
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        #else
        // iOS: No direct equivalent. Could present UIDocumentInteractionController if needed.
        #endif
    }

    /// Opens a directory in the system file browser.
    static func openDirectory(url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        // iOS: No direct equivalent for opening directories.
        #endif
    }
}

