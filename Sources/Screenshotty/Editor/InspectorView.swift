import ScreenshottyCore
import SwiftUI

struct InspectorView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                InspectorSection("Background") {
                    BackgroundPickerView(background: $model.settings.background)
                }

                InspectorSection("Canvas") {
                    AspectRatioGrid(selection: $model.settings.aspectRatio)
                    LabeledSlider(title: "Padding", value: $model.settings.padding,
                                  range: CompositionSettings.paddingRange)
                }

                InspectorSection("Screenshot") {
                    Toggle("Auto-trim and balance margins", isOn: $model.settings.autoTrim)
                        .help("Removes uneven plain borders so the content is perfectly centred")
                    if model.settings.autoTrim {
                        LabeledSlider(title: "Inner margin", value: $model.settings.innerPadding,
                                      range: CompositionSettings.innerPaddingRange)
                            .disabled(!model.hasPlainBackground)
                            .help(model.hasPlainBackground
                                  ? "Even space around the content, in the screenshot's own background colour"
                                  : "Only applies to screenshots with a plain background, such as text")
                    }
                    LabeledSlider(title: "Corner radius", value: $model.settings.cornerRadius,
                                  range: CompositionSettings.cornerRadiusRange)
                    LabeledPicker(title: "Shadow", selection: $model.settings.shadow)
                    LabeledPicker(title: "Window", selection: $model.settings.windowChrome)
                    LabeledPicker(title: "Frame", selection: $model.settings.frame)
                }

                Button("Reset to Defaults") { model.resetStyle() }
                    .buttonStyle(.link)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 44)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            content
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
extension WindowChromeStyle: TitledOption {}
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
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(option[keyPath: title])
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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
