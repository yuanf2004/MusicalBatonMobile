import SwiftUI

/// Product-app colors are adaptive asset colors; debug UI keeps its own styling.
enum BatonTheme {
    static let ultramarine = Color("AccentColor")
    static let canvas = Color("Canvas")
    static let surface = Color("Surface")

    static func serif(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom("InstrumentSerif-Regular", size: size, relativeTo: style)
    }
}
