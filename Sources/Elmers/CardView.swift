import AppKit
import SwiftUI
import WebKit
import ElmersCore

/// What a card draws differently as the panel resizes, rounded so that most steps of a drag change only the card's
/// frame and not its contents.
struct CardStyle: Equatable {
    var isCompact: Bool
    var headerHeight: CGFloat
    var iconSide: CGFloat
    /// Previews scale with the card; Paste's measurements were taken on the default 232-pt card.
    var scale: CGFloat
    init(_ metrics: PanelMetrics) {
        isCompact = metrics.isCompact; headerHeight = metrics.headerHeight.rounded()
        iconSide = (78 * metrics.iconScale).rounded(); scale = (metrics.cardSide / 232 * 50).rounded() / 50
    }
    static let standard = CardStyle(PanelMetrics(height: PanelMetrics.defaultHeight))
}

/// Equatable without its closures, so that while the panel is resized SwiftUI only lays cards out at their new size
/// instead of re-evaluating each one (a resize step cost about 10 ms of layout with every card re-evaluated).
struct CardView: View, Equatable {
    let item: ClipboardItem
    let selected: Bool
    /// Paste turns the selected card's ring gray while the pointer rests on a different card.
    var ringDimmed = false
    let index: Int
    /// Shown in the bottom-right corner while the Quick Paste modifier is held (Paste: "≡ 1" … "≡ 9").
    var quickPasteNumber: Int? = nil
    /// Renaming happens in place, in the title: Paste's "click the item's title and type a new one".
    var renaming = false
    var onRename: (String?) -> Void = { _ in }
    var onBeginRename: () -> Void = {}
    /// The card's layout follows the panel's height, as in Paste (Compact Mode below 300 pt); its size is set by the
    /// caller's frame.
    var style = CardStyle.standard
    private var metrics: CardStyle { style }
    private var scale: CGFloat { style.scale }
    static func == (a: CardView, b: CardView) -> Bool {
        a.item.id == b.item.id && a.item.fingerprint == b.item.fingerprint && a.item.title == b.item.title && a.item.copiedAt == b.item.copiedAt
            && a.item.boardIDs == b.item.boardIDs && a.item.linkPreview == b.item.linkPreview && a.item.sourceBundleID == b.item.sourceBundleID
            && a.item.screenshot == b.item.screenshot && a.selected == b.selected && a.ringDimmed == b.ringDimmed && a.index == b.index
            && a.quickPasteNumber == b.quickPasteNumber && a.renaming == b.renaming && a.style == b.style
    }
    static let cornerRadius: CGFloat = 16
    /// Pinboard colors in Display P3. Paste's red renders #FE3A3C, which no sRGB system red reaches; the other seven
    /// take Apple's light-mode system values as P3 components in the same way and are not yet compared with Paste.
    static let colors: [Color] = [(1, 0.23, 0.24), (1, 0.584, 0), (1, 0.8, 0), (0.204, 0.78, 0.349), (0, 0.478, 1),
                                  (0.686, 0.322, 0.871), (1, 0.176, 0.333), (0.557, 0.557, 0.576)]
        .map { Color(.displayP3, red: $0.0, green: $0.1, blue: $0.2) }
    private var accent: Color {
        // Screenshots are Elmers' own type; at the user's request their header is a system gray whatever app took them.
        if item.kind == .screenshot { return Color(nsColor: .systemGray) }
        if let id = item.sourceBundleID, let url = CardImageCache.shared.appURL(for: id),
           let color = CardImageCache.shared.color(for: id, url: url) { return color }
        switch item.kind {
        case .link: return Color(red: 0.19, green: 0.52, blue: 0.77)
        case .image, .screenshot: return Color(red: 0.57, green: 0.32, blue: 0.65)
        case .file: return Color(red: 0.77, green: 0.48, blue: 0.2)
        default: return Color(red: 0.08, green: 0.18, blue: 0.43)
        }
    }
    private var appIcon: NSImage? {
        guard let id = item.sourceBundleID, let url = CardImageCache.shared.appURL(for: id) else { return nil }
        return CardImageCache.shared.icon(for: id, url: url)
    }
    var body: some View {
        VStack(spacing: 0) {
            header.foregroundStyle(.white).frame(height: metrics.headerHeight)
                .background(accent) // Paste's header is a flat tint (#1C3EC3 top to bottom), not a gradient.
            if let color = HexColor(item.text), item.kind == .color {
                // Paste 6.3.11 fills the whole body with the color and centers the value in 18-pt monospaced type,
                // with no count footer.
                Text(color.display).font(.system(size: 18, design: .monospaced))
                    .foregroundStyle(color.prefersDarkText ? Color.black.opacity(0.85) : Color.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.sRGB, red: color.red, green: color.green, blue: color.blue))
                    .overlay(alignment: .bottomTrailing) {
                        quickPasteBadge.foregroundStyle(color.prefersDarkText ? Color.black.opacity(0.65) : Color.white.opacity(0.65))
                    }
            } else if item.kind.isImage, hasImageData(item) {
                // Paste fills the body with the picture down to the card's bottom edge and lays its size and number in
                // pills over it.
                CardThumbnail(item: item, quickPasteNumber: quickPasteNumber)
            } else if [.text, .other].contains(item.kind), !item.text.isEmpty {
                textBody
            } else {
                VStack(spacing: 0) {
                    // minHeight 0 lets a tall preview (a link's fixed-height image, title and two-line address) clip
                    // instead of overflowing the card, which would center the overflow and lift the header off the top.
                    preview
                        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                        .clipped()
                    if !metrics.isCompact || item.kind == .link || filePath != nil { footerRow }
                }
                .overlay(alignment: .bottomTrailing) { quickPasteBadge.foregroundStyle(Self.badgeInk) }
                .background(item.kind == .link && item.linkPreview == nil ? Self.linkBodyColor : Self.bodyColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        // Paste 6.3.11 draws the selection as a 4-pt ring hugging the outside of the card, with no gap and no
        // border on unselected cards.
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: Self.cornerRadius + 4, style: .continuous)
                    .strokeBorder(ringDimmed ? Color(nsColor: .systemGray) : Self.ringColor, lineWidth: 4).padding(-4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.kind.title), \(item.source), \(String(item.text.prefix(140)))")
        .accessibilityValue(selected ? String(localized: "Selected") : "")
        .help(index < 9 ? String(localized: "\(item.source) · \(item.kind.title) · ⌘\(index + 1) to paste") : "\(item.source) · \(item.kind.title)")
    }
    /// Paste's footer sits on the bottom edge: counts are centered on one line, link addresses are left-aligned and may
    /// wrap onto a second line that grows upward. Compact Mode drops the counts.
    private var footerRow: some View {
        HStack(alignment: .bottom, spacing: 5) {
            if !item.boardIDs.isEmpty { Image(systemName: "pin.fill").font(.system(size: 9)).padding(.bottom, 3) }
            if let path = filePath {
                // Paste 6.3.11 shows a single file's full path on up to two lines, cut without an ellipsis.
                Text(verbatim: path).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, maxHeight: Self.twoFooterLines, alignment: .topLeading).clipped()
                    .padding(.trailing, quickPasteNumber == nil ? 0 : Self.badgeWidth)
            } else if item.kind == .link {
                Text(footer).lineLimit(2).truncationMode(.tail).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, quickPasteNumber == nil ? 0 : Self.badgeWidth)
            } else {
                Text(footer).lineLimit(1).frame(maxWidth: .infinity)
            }
        }
        .font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 13).padding(.bottom, 9).padding(.top, 4)
    }
    /// Paste's text card (measured September 30 on a 211-pt card): the text starts 12 pt in and 10 pt under the header,
    /// runs on under the footer without an ellipsis, and fades out linearly over 35 pt, gone 16 pt above the bottom edge,
    /// level with the middle of the count.
    private var textBody: some View {
        ZStack(alignment: .bottom) {
            Text(String(item.text.prefix(1600)))
                .font(.system(size: 13)).foregroundStyle(Color(nsColor: .textColor))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, metrics.isCompact ? 11 : 12).padding(.trailing, metrics.isCompact ? 11 : 12).padding(.top, metrics.isCompact ? 5 : 10)
                // minHeight 0: the text keeps its full height and is cut by the card instead of growing it.
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .mask {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: metrics.isCompact ? 24 : 35)
                        Color.clear.frame(height: metrics.isCompact ? 0 : 16)
                    }
                }
            if !metrics.isCompact { footerRow }
        }
        .overlay(alignment: .bottomTrailing) { quickPasteBadge.foregroundStyle(Self.badgeInk) }
        .background(Self.bodyColor)
    }
    /// Paste's Compact Mode puts the title and a short time ("59m") on one line in a 36-pt header with a 22-pt app icon
    /// 6 pt from the card's edge. The text changes layout at once; the icon is one view in both layouts, so it shrinks
    /// and grows over a few frames, as Paste's did (its icon frame went 78, 63, 44, 37, 28, 22 pt).
    private var header: some View {
        Group {
            if metrics.isCompact {
                HStack(spacing: 4) {
                    title(size: 13)
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        Text(Self.shortTime(item.copiedAt, now: context.date)).font(.system(size: 12)).opacity(0.9).lineLimit(1).fixedSize()
                            .help(item.copiedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: -1) {
                    title(size: 15)
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        Text(Self.relativeTime(item.copiedAt, now: context.date)).font(.system(size: 12)).opacity(0.9).lineLimit(1)
                            .help(item.copiedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.leading, 12).padding(.trailing, metrics.isCompact ? 34 : 56)
        // Paste draws the app icon large and lets the header and the card's corner cut it: a 78-pt frame on a 232-pt
        // card (86 at 312), centered on the header's middle 23 pt from the right edge (measured from its accessibility
        // frames, September 30). In Compact Mode it is 22 pt, 17 pt in.
        .overlay(alignment: .trailing) {
            let side = metrics.isCompact ? 22 : metrics.iconSide
            icon(side: side).offset(x: side / 2 - (metrics.isCompact ? 17 : 23))
                .animation(.easeOut(duration: 0.15), value: metrics.isCompact)
        }
        .clipped()
    }
    @ViewBuilder private func title(size: CGFloat) -> some View {
        if renaming {
            TitleField(initial: item.title ?? "", placeholder: item.kind.title, size: size, commit: onRename)
        } else {
            Text(item.title ?? item.kind.title).font(.system(size: size, weight: .semibold)).lineLimit(1)
                .onTapGesture { if selected { onBeginRename() } }
        }
    }
    @ViewBuilder private func icon(side: CGFloat) -> some View {
        if let icon = appIcon { Image(nsImage: icon).resizable().frame(width: side, height: side) }
        // Without an app icon the type's symbol keeps its own size inside Paste's larger icon frame.
        else { Image(systemName: symbol).font(.system(size: min(28, side * 28 / 46))).frame(width: side, height: side).opacity(0.85) }
    }
    /// Measured on Paste 6.3.11: a 10-pt `text.justify.left` glyph, then the number on the footer's baseline, 12.5 pt in
    /// from the card's right edge, in 65 % ink (#ACACAC on a dark card, brighter than the 55 % footer). It sits over the
    /// centered count without moving it; a link address stops short of it.
    @ViewBuilder private var quickPasteBadge: some View {
        if let number = quickPasteNumber {
            HStack(spacing: 3.5) {
                Image(systemName: "text.justify.left").font(.system(size: 10))
                Text(verbatim: "\(number)").font(.system(size: 12)).monospacedDigit()
            }
            .padding(.trailing, 11.5).padding(.bottom, 10)
            .accessibilityHidden(true)
        }
    }
    static let badgeWidth: CGFloat = 30
    static let badgeInk = Color(nsColor: NSColor(name: nil) { appearance in
        NSColor(white: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 1 : 0, alpha: 0.65)
    })
    /// Paste's wording: "now", "30 seconds ago", "5 minutes ago", "3 hours ago", "yesterday", "2 weeks ago".
    static func relativeTime(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 30 { return String(localized: "now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full; formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }
    /// Compact Mode's time: Paste showed three characters for an item copied 59 minutes before ("59m") and two for
    /// five days ("5d").
    static func shortTime(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return String(localized: "now") }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated; formatter.maximumUnitCount = 1
        formatter.allowedUnits = [.minute, .hour, .day, .weekOfMonth, .month, .year]
        return formatter.string(from: seconds) ?? ""
    }
    /// Paste's ring is a Display P3 blue (renders #016EFE), more saturated than the sRGB system accent.
    static let ringColor = Color(.displayP3, red: 0.004, green: 0.431, blue: 0.996)
    /// Card bodies are white in light mode and #141414 in dark mode (measured on Paste 6.3.11).
    static let bodyColor = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 0.078, alpha: 1) : .white
    })
    /// Paste's link placeholder body is a cool light gray (#F3F4F7) rather than white.
    static let linkBodyColor = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 0.14, alpha: 1) : NSColor(red: 0.953, green: 0.957, blue: 0.969, alpha: 1)
    })
    static let twoFooterLines = NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: 12)) * 2
    private var symbol: String { item.kind.symbolName }
    private var filePath: String? {
        guard item.kind == .file else { return nil }
        let urls = item.payload.fileURLs
        return urls.count == 1 ? urls[0].path : nil
    }
    private var footer: String {
        switch item.kind {
        case .text: return String(localized: "\(item.text.count) characters") // Paste: "1 character", "41 characters" (plural rules)
        case .link:
            // Paste shows the address without its scheme: "pasteapp.io/help".
            guard let url = URL(string: item.text.components(separatedBy: "\n").first ?? item.text), let host = url.host else { return "Link" }
            let path = url.path == "/" ? "" : url.path
            return host + path + (url.query.map { "?" + $0 } ?? "")
        case .file: return String(localized: "\(item.payload.itemCount) files")
        default: return ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file)
        }
    }
    @ViewBuilder private var preview: some View {
        if item.kind.isImage, hasImageData(item) {
            CardThumbnail(item: item)
        } else if item.kind == .link, let preview = item.linkPreview, preview.title != nil || preview.image != nil {
            VStack(alignment: .leading, spacing: 0) {
                if let data = preview.image, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFill().frame(maxWidth: .infinity).frame(height: (preview.title == nil ? 154 : 108) * scale).clipped()
                }
                if let title = preview.title {
                    Text(title).font(.system(size: 13, weight: .medium)).lineLimit(preview.image == nil ? 5 : 2).padding(13)
                }
            }
        } else if item.kind == .link {
            Image(systemName: "safari").font(.system(size: 34, weight: .thin)).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if item.kind == .file, let url = item.payload.fileURLs.first {
            // Measured on Paste 6.3.11: centered, the page's top 16.5 pt below the header.
            CardFileThumbnail(url: url)
                .frame(maxWidth: ThumbnailCache.fileThumbnailSide * scale, maxHeight: ThumbnailCache.fileThumbnailSide * scale)
                .frame(maxWidth: .infinity).padding(.top, metrics.isCompact ? 6 : 10)
        } else if item.kind == .file {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "doc.fill").font(.system(size: 40)).foregroundStyle(.orange)
                Text(item.text.components(separatedBy: "\n").compactMap { URL(string: $0)?.lastPathComponent }.joined(separator: "\n"))
                    .font(.system(size: 13, weight: .medium)).lineLimit(4)
            }.padding(13)
        } else {
            if item.text.isEmpty { PreviewUnavailable(compact: true) }
            else {
                Text(String(item.text.prefix(1600)))
                    .font(.system(size: 13)).foregroundStyle(Color(nsColor: .textColor))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    // Compact Mode starts the text just under the header, 11 pt in from the sides.
                    .padding(.horizontal, metrics.isCompact ? 11 : 13).padding(.top, metrics.isCompact ? 5 : 13).padding(.bottom, 13)
            }
        }
    }
}

/// Whether the payload has an image, known without reading bytes that may still be in the database.
func hasImageData(_ item: ClipboardItem) -> Bool { !item.payload.types.isDisjoint(with: ["public.png", "public.tiff"]) }

/// The first image representation in the payload. For a stored item this may read the database, so keep it off
/// the main thread where possible.
func imageData(of item: ClipboardItem) -> Data? {
    for representations in item.payload.items {
        for type in ["public.png", "public.tiff"] {
            if let data = representations[type] { return data }
        }
    }
    return nil
}

/// A file card's Quick Look thumbnail, made off the main thread.
private struct CardFileThumbnail: View {
    let url: URL
    @State private var loaded: NSImage?
    var body: some View {
        ZStack {
            if let image = loaded ?? ThumbnailCache.shared.cached(fileAt: url) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            }
        }
        .task(id: url) { loaded = await ThumbnailCache.shared.thumbnail(forFileAt: url) }
    }
}

/// Full-resolution image for previews, sharing and drags; cards use `CardThumbnail` instead.
func imagePreview(_ item: ClipboardItem) -> NSImage? { imageData(of: item).flatMap(NSImage.init(data:)) }

/// A card's image, drawn from a downsampled thumbnail that is decoded off the main thread.
private struct CardThumbnail: View {
    let item: ClipboardItem
    var quickPasteNumber: Int? = nil
    var body: some View {
        // Reading `ready` makes this view redraw when the thumbnail arrives.
        let image = ThumbnailCache.shared.ready.keys.contains(item.fingerprint) ? ThumbnailCache.shared.cached(item) : ThumbnailCache.shared.cached(item)
        Color.clear
            .overlay {
                if let image { Image(nsImage: image).resizable().interpolation(.high).scaledToFill() }
            }
            .clipped()
            .background(CardView.bodyColor)
            // Measured on Paste 6.3.11 (211-pt card): a 19-pt pill with the size in pixels ("600 × 400") centered 8 pt
            // above the bottom edge, and the Quick Paste number in a matching pill 8 pt from the right.
            .overlay(alignment: .bottom) {
                if image != nil, let size = ThumbnailCache.shared.pixelSize(of: item) {
                    Self.pill { Text(verbatim: "\(Int(size.width)) × \(Int(size.height))") }.padding(.bottom, 8)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let number = quickPasteNumber {
                    Self.pill {
                        HStack(spacing: 3.5) {
                            Image(systemName: "text.justify.left").font(.system(size: 10))
                            Text(verbatim: "\(number)").monospacedDigit()
                        }
                    }
                    .padding([.bottom, .trailing], 8).accessibilityHidden(true)
                }
            }
            .task(id: item.fingerprint) { _ = await ThumbnailCache.shared.thumbnail(for: item) }
    }
    /// Paste's pill: about 42 % black over the picture (it measured #007C7C over #62D9D8, #423C85 over #6262D9), with
    /// light 12-pt text.
    static func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 6).frame(height: 19)
            .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct ItemPreview: View {
    let item: ClipboardItem
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(item.title ?? item.kind.title).font(.title2.bold()); Spacer(); Text(item.source).foregroundStyle(.secondary) }
            Divider()
            if item.kind == .link, let url = URL(string: item.text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                LinkBrowser(url: url).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let image = imagePreview(item) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                if let text = item.recognizedText, !text.isEmpty {
                    Text("Recognized text").font(.caption.bold()).foregroundStyle(.secondary)
                    ScrollView { Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 120)
                }
            }
            else if item.text.isEmpty { PreviewUnavailable(compact: false) }
            else { ScrollView { Text(item.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } }
            Text(item.copiedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(minWidth: 480, minHeight: 320)
    }
}

/// The card title while renaming: typed in place in the header, saved with Return, cancelled with Escape (routed by the
/// panel) or by clicking elsewhere. An empty title returns the card to its type name.
private struct TitleField: View {
    let initial: String
    let placeholder: String
    var size: CGFloat = 15
    let commit: (String?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        TextField(text: $text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.55))) { Text(placeholder) }
            .textFieldStyle(.plain).font(.system(size: size, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            .focused($focused)
            .onAppear { text = initial; DispatchQueue.main.async { focused = true } }
            .onSubmit { commit(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .onChange(of: focused) { _, isFocused in if !isFocused { commit(text.trimmingCharacters(in: .whitespacesAndNewlines)) } }
            .accessibilityLabel(String(localized: "Title"))
    }
}

/// The Space preview of a link: Paste opens links "in a built-in browser, so you can preview them without leaving
/// Paste". The page loads only when the preview opens, with a private, non-persistent store, so no cookies or site data
/// outlive the preview.
struct LinkBrowser: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setAccessibilityLabel(url.absoluteString)
        if ["http", "https"].contains(url.scheme?.lowercased() ?? "") { view.load(URLRequest(url: url)) }
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
}

/// Paste 6.3.11's wording for content it keeps but cannot draw: "Preview unavailable" / "Preview can't be shown, but the
/// content is saved, and you're able to paste it". Paste's layout for this state has not been seen.
struct PreviewUnavailable: View {
    let compact: Bool
    var body: some View {
        VStack(spacing: compact ? 4 : 8) {
            Text("Preview unavailable").font(.system(size: compact ? 13 : 17, weight: .semibold))
            Text("Preview can’t be shown, but the\u{00A0}content is saved, and\u{00A0}you’re able to\u{00A0}paste it")
                .font(.system(size: compact ? 12 : 13)).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center).padding(compact ? 13 : 24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Source icons are independent of selection state. Avoid Launch Services/icon I/O on every redraw.
final class CardImageCache {
    static let shared = CardImageCache()
    private let icons = NSCache<NSString, NSImage>()
    private var colors: [String: Color?] = [:]
    private var urls: [String: URL?] = [:]
    /// Launch Services is asked once per app: cards read this on every evaluation, which a resize repeats per frame.
    func appURL(for id: String) -> URL? {
        if let cached = urls[id] { return cached }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        urls[id] = url
        return url
    }
    func icon(for id: String, url: URL) -> NSImage {
        if let icon = icons.object(forKey: id as NSString) { return icon }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons.setObject(icon, forKey: id as NSString)
        return icon
    }
    /// The card header takes the source app's dominant icon color, as Paste does (Brave is orange, Safari blue).
    func color(for id: String, url: URL) -> Color? {
        if let cached = colors[id] { return cached }
        let color = Self.dominantColor(of: icon(for: id, url: url)).map(Color.init)
        colors[id] = color
        return color
    }
    /// Paste's header color for an app (`HeaderPalette`): the icon's dominant colorful hue, matched to Paste's palette,
    /// or gray or black for an icon with almost no color. Checked against 12 apps: 10 match Paste exactly.
    private static func dominantColor(of image: NSImage) -> NSColor? {
        let size = 32
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        var hues: [Int: (count: Int, hue: CGFloat, saturation: CGFloat, brightness: CGFloat)] = [:]
        var opaque = 0, grays = 0, grayBrightness: CGFloat = 0
        for y in 0..<size { for x in 0..<size {
            guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), pixel.alphaComponent > 0.9 else { continue }
            opaque += 1
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
            pixel.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
            guard s >= 0.3, v >= 0.25 else {
                if v < 0.92 { grays += 1; grayBrightness += v }
                continue
            }
            var bucket = hues[Int(h * 24) % 24] ?? (0, 0, 0, 0)
            bucket.count += 1; bucket.hue += h; bucket.saturation += s; bucket.brightness += v
            hues[Int(h * 24) % 24] = bucket
        } }
        let colorful = hues.values.reduce(0) { $0 + $1.count }
        let rgb: HeaderPalette.RGB
        if let best = hues.values.max(by: { $0.count < $1.count }), Double(colorful) >= Double(opaque) * HeaderPalette.colorfulShare {
            let n = CGFloat(best.count)
            let average = NSColor(hue: best.hue / n, saturation: best.saturation / n, brightness: best.brightness / n, alpha: 1)
            rgb = HeaderPalette.color(dominant: .init(Double(average.redComponent), Double(average.greenComponent), Double(average.blueComponent)))
        } else if grays > 0 {
            rgb = HeaderPalette.color(grayBrightness: Double(grayBrightness) / Double(grays))
        } else { return nil }
        return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
}

extension ContentKind {
    /// The type's name on cards, in filters and in menus, in the user's language.
    var title: String {
        switch self {
        case .text: return String(localized: "Text")
        case .link: return String(localized: "Link")
        case .image: return String(localized: "Image")
        case .screenshot: return String(localized: "Screenshot")
        case .file: return String(localized: "File")
        case .color: return String(localized: "Color")
        case .other: return String(localized: "Unknown")
        }
    }
    /// SF Symbol used for this type on cards and in the search field's type filter.
    var symbolName: String {
        switch self { case .text: return "text.alignleft"; case .link: return "link"; case .image: return "photo"; case .screenshot: return "viewfinder"; case .file: return "doc"; case .color: return "paintpalette"; case .other: return "doc.on.clipboard" }
    }
    /// Lowercase plural for the search placeholder: "Search images".
    var searchNoun: String {
        switch self { case .text: return "text"; case .other: return "content"; default: return rawValue.lowercased() + "s" }
    }
}
