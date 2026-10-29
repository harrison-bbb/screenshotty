import ScreenshottyCore
import SwiftUI

struct InspectorView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                InspectorSection("Style") {
                    StylePicker(model: model)
                }

                InspectorSection("Background") {
                    BackgroundPickerView(background: $model.settings.background,
                                         smartVariant: $model.settings.smartBackground,
                                         smartSuggestions: model.smartSuggestions)
                }

                InspectorSection("Frame") {
                    TilePicker(title: "Mockup", selection: $model.settings.device,
                               options: DeviceStyle.allCases, label: \.title, symbol: \.symbol)
                    WindowControl(settings: $model.settings, isTyping: $model.isTyping)
                    LabeledPicker(title: "Shadow", selection: $model.settings.shadow)
                    if model.settings.device == .none {
                        CornerRadiusControl(settings: $model.settings)
                        LabeledPicker(title: "Border", selection: $model.settings.frame)
                    }
                }

                InspectorSection("Watermark") {
                    WatermarkControl(settings: $model.settings, isTyping: $model.isTyping)
                }

                InspectorSection("Layout") {
                    AspectRatioGrid(selection: $model.settings.aspectRatio)
                    LabeledSlider(title: "Padding", value: $model.settings.padding,
                                  range: CompositionSettings.paddingRange)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Export width").font(.callout)
                        CompactTabBar(selection: $model.settings.exportWidth,
                                      options: CompositionSettings.exportWidthOptions,
                                      title: \.exportWidthTitle)
                    }
                    .help("Exact width of the exported image. Original keeps the screenshot's own resolution.")
                }

                InspectorSection("Screenshot", showsDivider: false) {
                    Toggle("Auto-trim and balance margins", isOn: $model.settings.autoTrim)
                        .help("Removes uneven borders, slivers and cut-off content so the content is perfectly centred")
                    // Only shown when it does something: screenshots of content on a plain background.
                    if model.settings.autoTrim, model.hasPlainBackground {
                        LabeledSlider(title: "Inner margin", value: $model.settings.innerPadding,
                                      range: CompositionSettings.innerPaddingRange)
                            .help("Even space around the content, in the screenshot's own background colour")
                    }
                }

                Button("Reset to Defaults") { model.resetStyle() }
                    .buttonStyle(.link)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 38)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    let showsDivider: Bool
    @ViewBuilder let content: Content

    init(_ title: String, showsDivider: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.showsDivider = showsDivider
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            content
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            if showsDivider { Divider() }
        }
    }
}

/// A row of tiles with an icon and a label, like the aspect ratio picker.
struct TilePicker<Option: Hashable>: View {
    let title: String
    @Binding var selection: Option
    let options: [Option]
    let label: KeyPath<Option, String>
    let symbol: KeyPath<Option, String>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout)
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    let selected = option == selection
                    Button { selection = option } label: {
                        VStack(spacing: 4) {
                            Image(systemName: option[keyPath: symbol])
                                .font(.system(size: 16, weight: .regular))
                                .frame(height: 20)
                            Text(option[keyPath: label])
                                .font(.system(size: 11, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(selected ? Color.accentColor : Color.primary)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option[keyPath: label])
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}

extension DeviceStyle {
    var symbol: String {
        switch self {
        case .none: "rectangle.dashed"
        case .macbook: "laptopcomputer"
        case .iphone: "iphone"
        }
    }
}

extension WindowChromeStyle.Kind {
    var symbol: String {
        switch self {
        case .none: "rectangle.dashed"
        case .macOS: "macwindow"
        case .browser: "safari"
        }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            Slider(value: $value, in: range)
                .controlSize(.small)
        }
    }
}

protocol TitledOption: CaseIterable, Identifiable, Hashable where AllCases: RandomAccessCollection {
    var title: String { get }
}

extension ShadowStyle: TitledOption {}
extension DeviceStyle: TitledOption {}

extension Optional where Wrapped == Int {
    var exportWidthTitle: String { map { "\($0)" } ?? "Original" }
}

/// Window chrome: none, a macOS title bar, or a browser with an address bar, in light or dark.
struct WindowControl: View {
    @Binding var settings: CompositionSettings
    @Binding var isTyping: Bool
    @FocusState private var addressFocused: Bool

    var body: some View {
        let chrome = settings.windowChrome
        VStack(alignment: .leading, spacing: 6) {
            TilePicker(title: "Window",
                       selection: Binding(get: { chrome.kind },
                                          set: { settings.windowChrome = WindowChromeStyle(kind: $0, dark: chrome.isDark) }),
                       options: WindowChromeStyle.Kind.allCases, label: \.title, symbol: \.symbol)
            if chrome.kind != .none {
                CompactTabBar(selection: Binding(get: { chrome.isDark },
                                                 set: { settings.windowChrome = WindowChromeStyle(kind: chrome.kind, dark: $0) }),
                              options: [false, true], title: \.appearanceTitle)
            }
            if chrome.kind == .browser {
                TextField("Address, e.g. yourapp.com", text: $settings.browserURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .focused($addressFocused)
                    .onChange(of: addressFocused) { _, focused in isTyping = focused }
            }
        }
    }
}

private extension Bool {
    var appearanceTitle: String { self ? "Dark" : "Light" }
}
extension FrameStyle: TitledOption {}

struct LabeledPicker<Option: TitledOption>: View {
    let title: String
    @Binding var selection: Option

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout)
            CompactTabBar(selection: $selection, options: Array(Option.allCases), title: \.title)
        }
    }
}

struct AspectRatioGrid: View {
    @Binding var selection: AspectRatio

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(AspectRatio.allCases) { aspect in
                Button {
                    selection = aspect
                } label: {
                    VStack(spacing: 2) {
                        AspectGlyph(ratio: aspect.ratio)
                            .frame(height: 18)
                        Text(aspect.title)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(selection == aspect ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(selection == aspect ? Color.accentColor : .clear, lineWidth: 1.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(aspect.subtitle)
            }
        }
    }
}

private struct AspectGlyph: View {
    let ratio: Double?

    var body: some View {
        GeometryReader { geo in
            let maxSide = geo.size.height
            let r = ratio ?? 1.3
            let w = r >= 1 ? maxSide * 1.3 : maxSide * 1.3 * r
            let h = r >= 1 ? maxSide * 1.3 / r : maxSide * 1.3
            let scale = min(1, maxSide / h)
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.3, dash: ratio == nil ? [2, 2] : []))
                .frame(width: w * scale, height: h * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(.secondary)
    }
}

/// A segmented control that always fits its container (the system one has a fixed minimum width).
struct CompactTabBar<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: KeyPath<Option, String>

    var body: some View {
        let fontSize: CGFloat = options.count >= 6 ? 11 : 12
        SharedWidthLayout(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(option[keyPath: title])
                        .font(.system(size: fontSize, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(selected ? Color(nsColor: .controlBackgroundColor) : .clear)
                            .shadow(color: .black.opacity(selected ? 0.15 : 0), radius: 1, y: 0.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)))
    }
}

/// Lays children out in a row: each gets its natural width plus an equal share of the space left,
/// so every label stays whole and the same size, and the row still fills its container.
struct SharedWidthLayout: Layout {
    var spacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let natural = ideal.map(\.width).reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0))
        return CGSize(width: proposal.width ?? natural, height: ideal.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        let gaps = spacing * CGFloat(max(subviews.count - 1, 0))
        let extra = (bounds.width - gaps - ideal.reduce(0, +)) / CGFloat(max(subviews.count, 1))
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            let width = max(ideal[index] + extra, 0)
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }
}

/// Corner radius slider. With a window title bar the range tops out at a realistic macOS radius,
/// so the title bar and traffic lights are never cut off. The user's own value is kept for later.
struct CornerRadiusControl: View {
    @Binding var settings: CompositionSettings

    var body: some View {
        let limited = settings.windowChrome != .none
        let maximum = limited ? CompositionSettings.maxChromeCornerRadius : CompositionSettings.cornerRadiusRange.upperBound
        VStack(alignment: .leading, spacing: 4) {
            LabeledSlider(title: "Corner radius",
                          value: Binding(get: { settings.effectiveCornerRadius },
                                         set: { settings.cornerRadius = $0 }),
                          range: 0...maximum)
            if limited, settings.cornerRadius > CompositionSettings.maxChromeCornerRadius {
                Text("Capped at \(Int(maximum)) while the window title bar is on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Turns the watermark on from the brand kit, and adjusts what it shows and where.
struct WatermarkControl: View {
    @Binding var settings: CompositionSettings
    @Binding var isTyping: Bool
    @ObservedObject private var prefs = Preferences.shared
    @FocusState private var textFocused: Bool

    var body: some View {
        let kit = prefs.brandKit
        Toggle("Show watermark", isOn: Binding(
            get: { settings.watermark != nil },
            set: { on in
                if on {
                    var mark = kit.watermark
                    if mark.isEmpty { mark.text = "yourapp.com" }
                    settings.watermark = mark
                } else {
                    settings.watermark = nil
                }
            }))
        if kit.logoPath == nil && kit.name.isEmpty {
            Button("Add your logo and name in Settings…") { WindowManager.shared.showSettings() }
                .buttonStyle(.link)
                .font(.callout)
        }
        if let mark = settings.watermark {
            if kit.logoPath != nil {
                Toggle("Logo", isOn: Binding(get: { mark.logoPath != nil },
                                             set: { settings.watermark?.logoPath = $0 ? kit.logoPath : nil }))
            }
            TextField("Text", text: Binding(get: { settings.watermark?.text ?? "" },
                                            set: { settings.watermark?.text = $0 }),
                      prompt: Text("Name, handle or URL"))
                .textFieldStyle(.roundedBorder)
                .focused($textFocused)
                .onChange(of: textFocused) { _, focused in isTyping = focused }
            VStack(alignment: .leading, spacing: 6) {
                Text("Position").font(.callout)
                CompactTabBar(selection: Binding(get: { mark.position }, set: { settings.watermark?.position = $0 }),
                              options: Watermark.Position.allCases, title: \.shortTitle)
            }
            LabeledSlider(title: "Size", value: Binding(get: { mark.size }, set: { settings.watermark?.size = $0.rounded() }),
                          range: Watermark.sizeRange)
        }
    }
}

extension Watermark.Position {
    var shortTitle: String {
        switch self {
        case .topLeft: "↖"
        case .topRight: "↗"
        case .bottomLeft: "↙"
        case .bottomCenter: "↓"
        case .bottomRight: "↘"
        }
    }
}
