import AppKit
import ScreenshottyCore
import SwiftUI

/// One-click looks: built-in styles for common destinations, plus the user's own saved styles.
struct StylePicker: View {
    @ObservedObject var model: EditorModel
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        let active = model.activeStyle?.id
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6) {
                ForEach(prefs.allStyles) { style in
                    Button { model.apply(style) } label: {
                        Text(style.name)
                            .font(.system(size: 12, weight: active == style.id ? .semibold : .regular))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(active == style.id ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06)))
                            .overlay(Capsule().strokeBorder(active == style.id ? Color.accentColor : .clear, lineWidth: 1.5))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(style.summary)
                    .contextMenu {
                        if !style.isBuiltIn {
                            Button("Update to Current Look") { update(style) }
                            Button("Rename…") { rename(style) }
                            Divider()
                            Button("Delete", role: .destructive) { prefs.savedStyles.removeAll { $0.id == style.id } }
                        }
                    }
                }
            }
            Button {
                save()
            } label: {
                Label("Save Current Look as Style…", systemImage: "plus")
            }
            .buttonStyle(.link)
            .font(.callout)
            .disabled(active != nil)
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

extension Style {
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
