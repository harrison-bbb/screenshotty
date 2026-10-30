import AppKit
import ScreenshottyCore
import SwiftUI
import UniformTypeIdentifiers

struct SmartSuggestion: Identifiable, Equatable {
    var variant: SmartBackground.Variant
    var style: BackgroundStyle
    var id: SmartBackground.Variant { variant }
}

struct BackgroundPickerView: View {
    @Binding var background: BackgroundStyle
    /// Set while a smart (screenshot-matched) background is chosen.
    @Binding var smartVariant: SmartBackground.Variant?
    let smartSuggestions: [SmartSuggestion]
    @State private var tab: Tab = .smart
    /// Remembers the last custom image so switching tabs doesn't lose it.
    @State private var lastImage: ImageBackgroundSpec?

    enum Tab: String, CaseIterable, Identifiable {
        case smart = "Smart", gradient = "Gradient", wallpaper = "Mesh", solid = "Solid", image = "Image", none = "None"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CompactTabBar(selection: $tab, options: Tab.allCases, title: \.rawValue)
                .onChange(of: tab) { _, newTab in switchKind(to: newTab) }

            switch tab {
            case .smart: smartPanel
            case .gradient: gradientPanel
            case .wallpaper: presetGrid(Presets.wallpapers, columns: 4)
            case .solid: solidPanel
            case .image: imagePanel
            case .none:
                Text("No background. Exported PNGs keep transparency around the screenshot.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            tab = currentTab
            if case .image(let spec) = background { lastImage = spec }
        }
        // Follow changes made elsewhere (undo, a style card, Reset). Setting `tab` to the matching kind
        // makes switchKind a no-op.
        .onChange(of: background) { _, new in
            tab = currentTab
            if case .image(let spec) = new { lastImage = spec }
        }
        .onChange(of: smartVariant) { _, _ in tab = currentTab }
    }

    // MARK: Panels

    private var smartPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
                ForEach(smartSuggestions) { suggestion in
                    Button {
                        background = suggestion.style
                        smartVariant = suggestion.variant
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Group {
                                if let thumb = ThumbnailCache.shared.image(for: suggestion.style, key: "smart:\(suggestion.style.hashValue)") {
                                    Image(decorative: thumb, scale: 1).resizable()
                                } else {
                                    Color.gray
                                }
                            }
                            .frame(height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .overlay(selectionRing(smartVariant == suggestion.variant, radius: 7))
                            Text(suggestion.variant.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .help("Colours picked from this screenshot. While a smart look is selected, every new capture gets its own matching background.")
    }

    private var gradientPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            presetGrid(Presets.gradients, columns: 4)
            if case .linearGradient(let spec) = background {
                LabeledSlider(title: "Angle", value: Binding(
                    get: { spec.angle },
                    set: { var s = spec; s.angle = $0.rounded(); background = .linearGradient(s) }),
                    range: 0...360)
            }
        }
    }

    private var solidPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(Preferences.shared.brandKit.colors + Presets.solids.filter { !Preferences.shared.brandKit.colors.contains($0) },
                        id: \.self) { color in
                    Button { background = .solid(color) } label: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color.swiftUIColor)
                            .frame(height: 28)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)))
                            .overlay(selectionRing(background == .solid(color), radius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            ColorPicker("Custom colour", selection: Binding(
                get: { if case .solid(let c) = background { c.swiftUIColor } else { .white } },
                set: { background = .solid(RGBAColor($0)) }))
                .font(.callout)
        }
    }

    private var imagePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if case .image(let spec) = background {
                if let thumb = ThumbnailCache.shared.image(for: .image(ImageBackgroundSpec(path: spec.path)),
                                                           key: "image:\(spec.path)") {
                    Image(decorative: thumb, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 90)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                LabeledSlider(title: "Blur", value: Binding(
                    get: { spec.blur },
                    set: { var s = spec; s.blur = $0.rounded(); background = .image(s); lastImage = s }),
                    range: 0...100)
            } else {
                Text("Use any photo or wallpaper. Drop an image here or choose one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Choose Image…", action: chooseImage)
                Button("Use Desktop Wallpaper", action: useWallpaper)
            }
            .controlSize(.small)
            RecentImagesGrid(current: currentImagePath) { path in
                let spec = ImageBackgroundSpec(path: path, blur: lastImage?.blur ?? 0)
                lastImage = spec
                background = .image(spec)
                Preferences.shared.rememberBackgroundImage(path)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in setImage(url) }
            }
            return true
        }
    }

    // MARK: Helpers

    private func presetGrid(_ presets: [BackgroundPreset], columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
            ForEach(presets) { preset in
                Button { background = preset.style } label: {
                    Group {
                        if let thumb = ThumbnailCache.shared.image(for: preset.style, key: preset.id) {
                            Image(decorative: thumb, scale: 1).resizable()
                        } else {
                            Color.gray
                        }
                    }
                    .frame(height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(selectionRing(isSelected(preset), radius: 7))
                }
                .buttonStyle(.plain)
                .help(preset.name)
            }
        }
    }

    private func isSelected(_ preset: BackgroundPreset) -> Bool {
        switch (background, preset.style) {
        case (.linearGradient(let a), .linearGradient(let b)): a.stops == b.stops
        default: background == preset.style
        }
    }

    private func selectionRing(_ selected: Bool, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius + 2)
            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
            .padding(-3)
    }

    private func switchKind(to newTab: Tab) {
        if newTab == .smart {
            if smartVariant == nil, let first = smartSuggestions.first {
                background = first.style
                smartVariant = first.variant
            }
            return
        }
        smartVariant = nil
        guard Self.tab(for: background) != newTab else { return }
        switch newTab {
        case .smart: break
        case .gradient: background = Presets.gradients[5].style
        case .wallpaper: background = Presets.wallpapers[0].style
        case .solid: background = .solid(.white)
        case .image:
            if let lastImage { background = .image(lastImage) }
        case .none: background = .transparent
        }
    }

    private var currentTab: Tab { smartVariant != nil ? .smart : Self.tab(for: background) }

    private static func tab(for background: BackgroundStyle) -> Tab {
        switch background {
        case .linearGradient: .gradient
        case .mesh: .wallpaper
        case .solid: .solid
        case .image: .image
        case .transparent: .none
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a background image"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setImage(url)
    }

    private func useWallpaper() {
        guard let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return }
        setImage(url)
    }

    private var currentImagePath: String? {
        if case .image(let spec) = background { return spec.path }
        return nil
    }

    /// Copies the image into Application Support so the background keeps working later, and remembers
    /// it so it's one click away next time. Picking the same picture again reuses the earlier copy.
    private func setImage(_ url: URL) {
        guard ImageLoader.load(url) != nil else { return }
        let prefs = Preferences.shared
        let path: String
        if url.path.hasPrefix(Preferences.backgroundsFolder.path) {
            path = url.path
        } else if let existing = prefs.recentBackgroundImages.first(where: {
            FileManager.default.contentsEqual(atPath: $0, andPath: url.path)
        }) {
            path = existing
        } else {
            let destination = Preferences.backgroundsFolder
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(url.pathExtension.isEmpty ? "png" : url.pathExtension)
            path = (try? FileManager.default.copyItem(at: url, to: destination)) != nil ? destination.path : url.path
        }
        let spec = ImageBackgroundSpec(path: path, blur: lastImage?.blur ?? 0)
        lastImage = spec
        background = .image(spec)
        prefs.rememberBackgroundImage(path)
    }
}

/// Background images used before, so a favourite is one click away.
private struct RecentImagesGrid: View {
    @ObservedObject private var prefs = Preferences.shared
    let current: String?
    let select: (String) -> Void

    var body: some View {
        if !prefs.recentBackgroundImages.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(prefs.recentBackgroundImages, id: \.self) { path in
                        Button { select(path) } label: {
                            Group {
                                if let thumb = ThumbnailCache.shared.image(for: .image(ImageBackgroundSpec(path: path)),
                                                                           key: "image:\(path)",
                                                                           size: CGSize(width: 120, height: 80)) {
                                    Image(decorative: thumb, scale: 1).resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    Color.secondary.opacity(0.2)
                                }
                            }
                            .frame(height: 40)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(current == path ? Color.accentColor : Color.primary.opacity(0.1),
                                              lineWidth: current == path ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Remove from Recent") { prefs.forgetBackgroundImage(path) }
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
    }
}
