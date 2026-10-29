import AppKit
import ScreenshottyCore
import SwiftUI

/// One-click looks, shown as cards that preview this screenshot in each style.
struct StylePicker: View {
    @ObservedObject var model: EditorModel
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        let active = model.activeStyle?.id
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(prefs.allStyles) { style in
                StyleCard(style: style, thumbnail: model.styleThumbnails[style.id], selected: active == style.id) {
                    model.apply(style)
                }
                .contextMenu {
                    if !style.isBuiltIn {
                        Button("Update to Current Look") { update(style) }
                        Button("Rename…") { rename(style) }
                        Divider()
                        Button("Delete", role: .destructive) { prefs.savedStyles.removeAll { $0.id == style.id } }
                    }
                }
            }
            SaveStyleCard(enabled: active == nil, action: save)
        }
    }

    private func save() {
        guard let name = Self.askForName(title: "Save Style", message: "Give this look a name so you can reuse it with one click.",
                                         defaultValue: "My style") else { return }
        prefs.savedStyles.append(Style(name: name, settings: model.settings))
    }

    private func update(_ style: Style) {
        guard let index = prefs.savedStyles.firstIndex(where: { $0.id == style.id }) else { return }
        prefs.savedStyles[index].settings = model.settings
    }

    private func rename(_ style: Style) {
        guard let index = prefs.savedStyles.firstIndex(where: { $0.id == style.id }),
              let name = Self.askForName(title: "Rename Style", message: "", defaultValue: style.name) else { return }
        prefs.savedStyles[index].name = name
    }

    static func askForName(title: String, message: String, defaultValue: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }
}

/// A style: a live preview of the screenshot in that look, with its name and size.
private struct StyleCard: View {
    let style: Style
    let thumbnail: CGImage?
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05))
                    if let thumbnail {
                        Image(decorative: thumbnail, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(6)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(height: 78)
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(5)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(style.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(style.shortSummary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 11)
                .fill(selected ? Color.accentColor.opacity(0.12) : hovering ? Color.primary.opacity(0.05) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 11)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(style.summary)
        .accessibilityLabel(style.name)
    }
}

private struct SaveStyleCard: View {
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                Text("Save current look")
                    .font(.system(size: 11.5, weight: .medium))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(enabled ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 124)
            .background(RoundedRectangle(cornerRadius: 11)
                .strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(enabled ? "Save these settings as a reusable style" : "This look is already a style")
    }
}

extension Style {
    /// "16:9 · 1600 px"
    var shortSummary: String {
        let shape = settings.aspectRatio == .auto ? "Any size" : settings.aspectRatio.title
        return settings.exportWidth.map { "\(shape) · \($0) px" } ?? shape
    }

    /// "16:9 · 1600 px · Browser"
    var summary: String {
        var parts: [String] = [settings.aspectRatio == .auto ? "Auto size" : settings.aspectRatio.title]
        if let width = settings.exportWidth { parts.append("\(width) px wide") }
        if settings.device != .none { parts.append(settings.device.title) }
        if settings.windowChrome != .none { parts.append(settings.windowChrome.title + " window") }
        if settings.smartBackground != nil { parts.append("matched colours") }
        return parts.joined(separator: " · ")
    }
}

/// Lays out children left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
