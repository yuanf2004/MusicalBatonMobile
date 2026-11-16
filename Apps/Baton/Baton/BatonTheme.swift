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

/// Visible touch feedback for custom cards and icons without changing their layout.
struct BatonPressStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed && isEnabled ? -0.12 : 0)
    }
}
