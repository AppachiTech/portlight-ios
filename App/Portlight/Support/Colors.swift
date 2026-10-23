import PortlightKit
import SwiftTerm
import SwiftUI
import UIKit

extension SwiftUI.Color {
    static let portlightNight = SwiftUI.Color(red: 0x10 / 255, green: 0x14 / 255, blue: 0x18 / 255)
    static let portlightGlass = SwiftUI.Color(red: 0x1B / 255, green: 0x2A / 255, blue: 0x36 / 255)
    static let portlightBrass = SwiftUI.Color(red: 0xF5 / 255, green: 0xA5 / 255, blue: 0x24 / 255)

    init(_ rgb: RGB) {
        self.init(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }
}

extension UIColor {
    convenience init(_ rgb: RGB) {
        self.init(red: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255, blue: CGFloat(rgb.blue) / 255, alpha: 1)
    }
}

extension TerminalTheme {
    var swiftTermColors: [SwiftTerm.Color] {
        ansi.map { SwiftTerm.Color(red8: UInt16($0.red), green8: UInt16($0.green), blue8: UInt16($0.blue)) }
    }
}

extension PortlightKit.CursorStyle {
    func swiftTerm(blink: Bool) -> SwiftTerm.CursorStyle {
        switch (self, blink) {
        case (.block, true): .blinkBlock
        case (.block, false): .steadyBlock
        case (.underline, true): .blinkUnderline
        case (.underline, false): .steadyUnderline
        case (.bar, true): .blinkBar
        case (.bar, false): .steadyBar
        }
    }
}
