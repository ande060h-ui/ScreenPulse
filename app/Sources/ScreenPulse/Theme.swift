// The ScreenPulse look for SwiftUI windows (see docs/BRAND.md): aluminium and keycap colours that
// follow the Mac's light and dark appearance, Schibsted Grotesk, buttons drawn as keys and the
// green LED used only at dot size.

import SwiftUI
import AppKit
import CoreText

// MARK: Font

enum SPFont {
    static let family = "Schibsted Grotesk"
    private static var registered = false

    /// Makes the bundled font available to this process. Safe to call more than once.
    static func register() {
        guard !registered else { return }
        registered = true
        guard let url = Bundle.main.url(forResource: "SchibstedGrotesk", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    /// The brand font, or the system font if the bundled file is missing.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if NSFont(name: family, size: size) != nil || NSFontManager.shared.availableMembers(ofFontFamily: family) != nil {
            return Font.custom(family, size: size).weight(weight)
        }
        return Font.system(size: size, weight: weight)
    }
}

// MARK: Colours

enum SP {
    /// A colour with one value for the light appearance and one for the dark.
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return rgb(isDark ? dark : light)
        })
    }
    static func rgb(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }

    static let window = dyn(0xe3e5e8, 0x131417)        // aluminium / keycap black
    static let windowNS = NSColor(name: nil) { a in rgb(a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 0x131417 : 0xe3e5e8) }
    static let plate = dyn(0xf4f5f6, 0x1a1b1e)         // raised panels
    static let rule = dyn(0xcfd2d7, 0x2c2e33)
    static let ink = dyn(0x131417, 0xe9eaec)
    static let muted = dyn(0x555961, 0x9a9ea6)
    static let link = dyn(0x0d7a3a, 0x2fd671)
    static let field = dyn(0xffffff, 0x0f1012)
    static let fieldBorder = dyn(0xcfd2d7, 0x3a3d43)
    static let ledOff = dyn(0xb9bdc4, 0x3a3d43)
    static let led = Color(nsColor: rgb(0x2fd671))
    static let error = dyn(0xc8322b, 0xff6b62)
    static let attention = dyn(0xb86a00, 0xf0a33a)

    // Keys: a plain key and the one main action per screen
    static let key = dyn(0xf4f5f6, 0x2c2e33)
    static let keyEdge = dyn(0xb9bdc4, 0x0b0c0e)
    static let keyText = dyn(0x131417, 0xe9eaec)
    static let keyMain = dyn(0x1a1b1e, 0xe3e5e8)
    static let keyMainEdge = dyn(0x000000, 0x9a9ea6)
    static let keyMainText = dyn(0xe9eaec, 0x131417)
}

// MARK: Pieces

/// The green LED. Off is a grey dot.
struct LED: View {
    var on: Bool
    var size: CGFloat = 8
    var body: some View {
        Circle()
            .fill(on ? SP.led : SP.ledOff)
            .frame(width: size, height: size)
            .shadow(color: on ? SP.led.opacity(0.8) : .clear, radius: on ? size * 0.45 : 0)
            .accessibilityHidden(true)
    }
}

/// A dot in another colour, for states that are not "on" (an error, something missing).
struct StatusDot: View {
    var color: Color
    var size: CGFloat = 8
    var body: some View {
        Circle().fill(color).frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// A button drawn as a keycap: a hard bottom edge that disappears when it is pressed.
/// `latched` shows it pressed (a selected tab or mode); `led` adds the indicator dot.
struct KeyButtonStyle: ButtonStyle {
    var main = false
    var small = false
    var led: Bool? = nil
    var latched = false
    var minWidth: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        KeyCap(configuration: configuration, main: main, small: small, led: led, latched: latched, minWidth: minWidth)
    }

    private struct KeyCap: View {
        let configuration: ButtonStyleConfiguration
        let main: Bool, small: Bool
        let led: Bool?
        let latched: Bool
        let minWidth: CGFloat?
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let down = configuration.isPressed || latched
            HStack(spacing: 8) {
                if let led { LED(on: led, size: 6) }
                configuration.label
            }
            .font(SPFont.font(13, .medium))
            .foregroundStyle(main ? SP.keyMainText : SP.keyText)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minWidth: minWidth)
            .frame(height: small ? 30 : 34)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(main ? SP.keyMain : SP.key))
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(main ? SP.keyMainEdge : SP.keyEdge).offset(y: down ? 1 : 3))
            .offset(y: down ? 2 : 0)
            .padding(.bottom, 3)
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.08), value: down)
        }
    }
}

/// An on/off switch drawn as a small key with an LED and ON/OFF.
struct LEDToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 16) {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { configuration.isOn.toggle() } label: {
                HStack(spacing: 7) {
                    LED(on: configuration.isOn)
                    Text(configuration.isOn ? "ON" : "OFF")
                        .font(SPFont.font(11, .semibold)).tracking(0.5)
                        .foregroundStyle(SP.muted)
                }
                .frame(width: 34, alignment: .leading)
            }
            .buttonStyle(KeyButtonStyle(small: true, latched: configuration.isOn))
        }
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// Title and an optional explanation, for the left side of a row.
struct RowLabel: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(SPFont.font(14, .medium))
            if let detail {
                Text(detail).font(SPFont.font(12.5)).foregroundStyle(SP.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A raised panel with a small upper-case heading.
struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(SPFont.font(11.5, .semibold)).tracking(0.9)
                .foregroundStyle(SP.muted)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 14, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(SP.plate))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(SP.rule, lineWidth: 1))
    }
}

/// A hairline between rows.
struct Rule: View {
    var body: some View { Rectangle().fill(SP.rule).frame(height: 1) }
}

/// Small grey explanatory text.
struct Note: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    init(verbatim: String) { self.text = LocalizedStringKey(verbatim) }
    var body: some View {
        Text(text).font(SPFont.font(12.5)).foregroundStyle(SP.muted)
            .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
    }
}

/// A text field with the brand's border and radius.
struct SPFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(SPFont.font(14))
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(SP.field))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(SP.fieldBorder, lineWidth: 1))
    }
}

/// A slider drawn as a row of dots with a small key as the handle. The left end is `range.upperBound`
/// and the right end `range.lowerBound`, so dragging right makes the value smaller.
struct DotSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let label: String
    private let dots = 21
    private let thumb: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let span = range.upperBound - range.lowerBound
            let p = CGFloat((range.upperBound - value) / span)
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(0..<dots, id: \.self) { i in
                        Circle()
                            .fill(CGFloat(i) / CGFloat(dots - 1) <= p + 0.001 ? SP.ink : SP.rule)
                            .frame(width: 6, height: 6)
                        if i < dots - 1 { Spacer(minLength: 0) }
                    }
                }
                .padding(.horizontal, thumb / 2 - 3)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(SP.keyMain)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(SP.keyMainEdge).offset(y: 2))
                    .frame(width: thumb, height: 20)
                    .offset(x: p * (w - thumb))
            }
            .frame(height: 26)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let f = min(max((g.location.x - thumb / 2) / max(w - thumb, 1), 0), 1)
                let raw = range.upperBound - Double(f) * span
                let stepped = (raw / step).rounded() * step
                value = min(max(stepped, range.lowerBound), range.upperBound)
            })
        }
        .frame(height: 26)
        .accessibilityRepresentation {
            Slider(value: $value, in: range, step: step) { Text(label) }
        }
    }
}
