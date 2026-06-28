import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Fonts & helpers

enum FontFamily: String, CaseIterable, Identifiable {
    case newYork = "New York"
    case sfPro   = "SF Pro"
    case sfMono  = "SF Mono"
    var id: String { rawValue }
}

func bodyNSFont(_ family: FontFamily = .newYork, size: CGFloat = 17) -> NSFont {
    switch family {
    case .newYork:
        let base = NSFont.systemFont(ofSize: size)
        let d = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        return NSFont(descriptor: d, size: size) ?? base
    case .sfPro:  return NSFont.systemFont(ofSize: size)
    case .sfMono: return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

// Turn an NSFont familyName (often an internal name like ".New York" or
// ".AppleSystemUIFont") into a clean display name for the toolbar.
func displayFontName(_ raw: String?) -> String {
    guard var n = raw else { return "—" }
    if n.hasPrefix(".") { n.removeFirst() }
    switch n {
    case "AppleSystemUIFontMonospaced", "SF NS Mono", "SFMono-Regular": return "SF Mono"
    case "AppleSystemUIFontSerif", "NewYork": return "New York"
    case "AppleSystemUIFont", "SF NS", "SFNS-Regular": return "SF Pro"
    default: return n
    }
}

func defaultParagraphStyle() -> NSMutableParagraphStyle {
    let ps = NSMutableParagraphStyle()
    ps.lineSpacing = 2
    ps.paragraphSpacing = 3
    return ps
}

func shortRelative(_ date: Date) -> String {
    let s = Date().timeIntervalSince(date)
    if s < 60 { return "Just now" }
    if s < 3600 { return "\(Int(s / 60))m ago" }
    if s < 86400 { return "\(Int(s / 3600))h ago" }
    if s < 604800 { return "\(Int(s / 86400))d ago" }
    let f = DateFormatter(); f.dateFormat = "MMM d"
    return f.string(from: date)
}

struct Theme: Identifiable {
    let name: String
    let accent: (Double, Double, Double)
    let paperLight: (Double, Double, Double)?   // custom light-mode page tint; nil = system
    var id: String { name }
}

enum Palette {
    // One theme only — Ocean (Apple Action Blue #0066cc).
    static let themes: [Theme] = [
        Theme(name: "Ocean", accent: (0.0, 0.40, 0.80), paperLight: nil),
    ]

    static var current: Theme { themes[0] }

    static func accent() -> Color { let a = current.accent; return Color(red: a.0, green: a.1, blue: a.2) }
    static func accentDark() -> Color { let a = current.accent; return Color(red: a.0 * 0.74, green: a.1 * 0.74, blue: a.2 * 0.80) }
    static func accentNS() -> NSColor { let a = current.accent; return NSColor(calibratedRed: a.0, green: a.1, blue: a.2, alpha: 1) }

    // Cards / surfaces — Apple: pure white in light, faint tinted dark in dark mode.
    static func paper(_ scheme: ColorScheme) -> Color {
        let a = current.accent
        if scheme == .dark { return Color(red: 0.10 + 0.05 * a.0, green: 0.10 + 0.05 * a.1, blue: 0.11 + 0.05 * a.2) }
        if let p = current.paperLight { return Color(red: p.0, green: p.1, blue: p.2) }
        return .white
    }

    // The canvas behind everything — Apple parchment (#f5f5f7) in light mode.
    static func surround(_ scheme: ColorScheme) -> Color {
        let a = current.accent
        if scheme == .dark { return Color(red: 0.05 + 0.11 * a.0, green: 0.05 + 0.11 * a.1, blue: 0.06 + 0.11 * a.2) }
        if let p = current.paperLight { return Color(red: p.0 * 0.95, green: p.1 * 0.94, blue: p.2 * 0.90) }
        return Color(red: 0.961, green: 0.961, blue: 0.965)
    }
}

// MARK: - Export

enum ExportFormat: String, CaseIterable, Identifiable {
    case markdown = "Markdown (.md)"
    case fountain = "Fountain (.fountain)"
    case text     = "Plain Text (.txt)"
    case rtf      = "Rich Text (.rtf)"
    case docx     = "Word (.docx)"
    case doc      = "Word 97 (.doc)"
    case html     = "Web Page (.html)"
    case odt      = "OpenDocument (.odt)"
    case rtfd     = "Rich Text Bundle (.rtfd)"
    case wordml   = "Word XML (.xml)"
    case pdf      = "PDF (.pdf)"
    var id: String { rawValue }

    var ext: String {
        switch self {
        case .markdown: return "md"; case .fountain: return "fountain"; case .text: return "txt"; case .rtf: return "rtf"
        case .docx: return "docx"; case .doc: return "doc"; case .html: return "html"
        case .odt: return "odt"; case .rtfd: return "rtfd"; case .wordml: return "xml"; case .pdf: return "pdf"
        }
    }

    @MainActor func data(from attr: NSAttributedString) -> Data? {
        let full = NSRange(location: 0, length: attr.length)
        func doc(_ type: NSAttributedString.DocumentType) -> Data? {
            try? attr.data(from: full, documentAttributes: [.documentType: type])
        }
        switch self {
        case .text, .fountain: return attr.string.data(using: .utf8)
        case .markdown: return ExportFormat.markdown(attr).data(using: .utf8)
        case .rtf:      return attr.rtf(from: full, documentAttributes: [:])
        case .rtfd:     return doc(.rtfd)
        case .html:     return doc(.html)
        case .doc:      return doc(.docFormat)
        case .docx:     return doc(.officeOpenXML)
        case .odt:      return doc(.openDocument)
        case .wordml:   return doc(.wordML)
        case .pdf:      return ExportFormat.pdf(attr)
        }
    }

    // Light Markdown: paragraph headings by font size + inline bold/italic.
    private static func markdown(_ attr: NSAttributedString) -> String {
        let ns = attr.string as NSString
        var out = ""
        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length), options: []) { attrs, range, _ in
            let piece = ns.substring(with: range)
            if piece.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out += piece; return }
            var s = piece
            if let f = attrs[.font] as? NSFont {
                let tr = NSFontManager.shared.traits(of: f)
                if tr.contains(.boldFontMask) { s = "**\(s)**" }
                if tr.contains(.italicFontMask) { s = "_\(s)_" }
            }
            out += s
        }
        return out
    }

    private static func pdf(_ attr: NSAttributedString) -> Data? {
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 200))   // US Letter width
        tv.appearance = NSAppearance(named: .aqua)   // resolve dynamic colours to light (black text)
        tv.textContainerInset = NSSize(width: 48, height: 56)
        tv.drawsBackground = true; tv.backgroundColor = .white
        tv.textStorage?.setAttributedString(attr)
        tv.sizeToFit()
        if let lm = tv.layoutManager, let tc = tv.textContainer { lm.ensureLayout(for: tc) }
        return tv.dataWithPDF(inside: tv.bounds)
    }
}

@MainActor func penwickSave(_ store: PenwickStore, _ editor: EditorController) {
    guard let ch = store.selectedChapter else { return }
    let attr = editor.textView?.attributedString() ?? ch.text
    store.save(url: ch.url, text: attr)
}

// Tracks the chapter checkboxes + format popup and keeps the filename in sync.
final class ExportActions: NSObject {
    let panel: NSSavePanel; let format: NSPopUpButton
    let checks: [NSButton]; let chapters: [Chapter]; let projectName: String; let exts: [String]
    init(panel: NSSavePanel, format: NSPopUpButton, checks: [NSButton], chapters: [Chapter], projectName: String, exts: [String]) {
        self.panel = panel; self.format = format; self.checks = checks
        self.chapters = chapters; self.projectName = projectName; self.exts = exts
    }
    var selected: [Chapter] { zip(checks, chapters).filter { $0.0.state == .on }.map { $0.1 } }
    @objc func selectAll() { checks.forEach { $0.state = .on }; update() }
    @objc func update() {
        let sel = selected
        let base = sel.count == 1 ? sel[0].title : projectName
        let ext = exts[max(0, min(format.indexOfSelectedItem, exts.count - 1))]
        panel.nameFieldStringValue = "\(base).\(ext)"
    }
}

@MainActor func penwickExport(_ store: PenwickStore, _ editor: EditorController) {
    guard let chapter = store.selectedChapter else { return }
    let project = store.currentProject
    let chapters = project?.chapters ?? [chapter]
    let liveCurrent = editor.textView?.attributedString() ?? chapter.text
    let formats = ExportFormat.allCases

    let panel = NSSavePanel()
    panel.title = "Export"; panel.canCreateDirectories = true

    // Checklist of chapters (current chapter pre-checked).
    let rowH: CGFloat = 22
    let docHeight = max(CGFloat(chapters.count) * rowH, rowH)
    let docView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: docHeight))
    var checks: [NSButton] = []
    for (i, ch) in chapters.enumerated() {
        let b = NSButton(checkboxWithTitle: "Chapter \(i + 1): \(ch.title)", target: nil, action: nil)
        b.frame = NSRect(x: 6, y: docHeight - CGFloat(i + 1) * rowH, width: 308, height: 20)
        b.state = (ch.url == chapter.url) ? .on : .off
        docView.addSubview(b); checks.append(b)
    }
    let listHeight = min(docHeight, 160)
    let scroll = NSScrollView(frame: NSRect(x: 14, y: 50, width: 344, height: listHeight))
    scroll.hasVerticalScroller = true; scroll.documentView = docView
    scroll.drawsBackground = false; scroll.borderType = .bezelBorder

    let listLabel = NSTextField(labelWithString: "Include chapters:")
    listLabel.frame = NSRect(x: 14, y: 52 + listHeight, width: 160, height: 18)
    let selectAll = NSButton(title: "Select All", target: nil, action: nil)
    selectAll.bezelStyle = .inline; selectAll.frame = NSRect(x: 268, y: 50 + listHeight, width: 90, height: 22)

    let formatPopup = NSPopUpButton(frame: NSRect(x: 84, y: 12, width: 274, height: 26))
    formatPopup.addItems(withTitles: formats.map { $0.rawValue })
    if let i = formats.firstIndex(of: .pdf) { formatPopup.selectItem(at: i) }
    let formatLabel = NSTextField(labelWithString: "Format:"); formatLabel.frame = NSRect(x: 14, y: 16, width: 64, height: 20)

    let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 372, height: 84 + listHeight))
    [formatLabel, formatPopup, scroll, listLabel, selectAll].forEach { accessory.addSubview($0) }
    panel.accessoryView = accessory

    let actions = ExportActions(panel: panel, format: formatPopup, checks: checks,
                                chapters: chapters, projectName: project?.name ?? "Manuscript",
                                exts: formats.map { $0.ext })
    checks.forEach { $0.target = actions; $0.action = #selector(ExportActions.update) }
    formatPopup.target = actions; formatPopup.action = #selector(ExportActions.update)
    selectAll.target = actions; selectAll.action = #selector(ExportActions.selectAll)
    actions.update()

    panel.begin { resp in
        guard resp == .OK, var url = panel.url else { _ = actions; return }
        MainActor.assumeIsolated {
            let fmt = formats[max(0, formatPopup.indexOfSelectedItem)]
            if url.pathExtension.lowercased() != fmt.ext { url.deletePathExtension(); url.appendPathExtension(fmt.ext) }
            var chosen = actions.selected
            if chosen.isEmpty { chosen = [chapter] }
            let m = NSMutableAttributedString()
            for (i, ch) in chosen.enumerated() {
                if i > 0 { m.append(NSAttributedString(string: "\n\n")) }
                m.append(ch.url == chapter.url ? liveCurrent : ch.text)
            }
            if let data = fmt.data(from: m) { try? data.write(to: url) }
        }
        _ = actions
    }
}

@MainActor func penwickShare(_ store: PenwickStore, _ editor: EditorController) {
    guard let chapter = store.selectedChapter else { return }
    let attr = editor.textView?.attributedString() ?? chapter.text
    presentPicker(items: [attr.string])
}

// Invite people to co-write: shares the project's iCloud Drive folder, which
// surfaces the system "Collaborate" option so edits sync through iCloud.
@MainActor func penwickCollaborate(_ store: PenwickStore) {
    guard let project = store.currentProject else { return }
    presentPicker(items: [project.url])
}

// Open/link any folder as a project — e.g. a shared project folder a collaborator
// sent you (which lands in iCloud Drive → Shared, outside the app's own folder).
@MainActor func penwickOpenProject(_ store: PenwickStore) {
    let panel = NSOpenPanel()
    panel.title = "Open Project Folder"
    panel.message = "Pick a Penwick project folder (e.g. a shared folder someone sent you)."
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Open"
    panel.begin { resp in
        guard resp == .OK, let url = panel.url else { return }
        MainActor.assumeIsolated { store.openExternalProject(url) }
    }
}

@MainActor func penwickAddComment(_ store: PenwickStore, _ editor: EditorController) {
    guard let tv = editor.textView, let url = store.selection else { return }
    let r = tv.selectedRange()
    guard r.length > 0 else {
        let a = NSAlert(); a.messageText = "Select some text first"
        a.informativeText = "Highlight the words you want to comment on, then choose Add Comment."
        a.runModal(); return
    }
    let quote = (tv.string as NSString).substring(with: r)
    let alert = NSAlert(); alert.messageText = "Add a comment"
    let shown = quote.count > 70 ? String(quote.prefix(70)) + "…" : quote
    alert.informativeText = "On: “\(shown)”"
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
    field.placeholderString = "Your note…"
    alert.accessoryView = field
    alert.addButton(withTitle: "Add"); alert.addButton(withTitle: "Cancel")
    if alert.runModal() == .alertFirstButtonReturn {
        let t = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { store.addComment(t, range: r, quote: quote, for: url) }
    }
}

@MainActor func penwickInsertImage(_ editor: EditorController) {
    let panel = NSOpenPanel()
    panel.title = "Insert Image"
    panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .heic, .bmp, .image]
    panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
    panel.begin { resp in
        guard resp == .OK, let url = panel.url, let img = NSImage(contentsOf: url) else { return }
        MainActor.assumeIsolated { editor.insertImage(img) }
    }
}

@MainActor func penwickContinueWithAI(_ store: PenwickStore, _ editor: EditorController) {
    guard AIClient.isConfigured else {
        let a = NSAlert(); a.messageText = "No AI linked"
        a.informativeText = "Open Settings → AI to link your API key or a local Ollama model."
        a.runModal(); return
    }
    guard let tv = editor.textView else { return }
    let tail = String(tv.string.suffix(2000))
    Task {
        do {
            let out = try await AIClient.complete(
                system: "You are a writing assistant. Continue the user's manuscript naturally, in the same voice and tense. Return only the continuation prose — no preamble or quotes.",
                prompt: tail.isEmpty ? "Write a compelling opening paragraph." : tail)
            await MainActor.run {
                editor.appendAtEnd(NSAttributedString(string: out.trimmingCharacters(in: .whitespacesAndNewlines),
                    attributes: [.font: bodyNSFont(), .foregroundColor: NSColor(white: 0.12, alpha: 1), .paragraphStyle: defaultParagraphStyle()]))
            }
        } catch {
            await MainActor.run { let a = NSAlert(); a.messageText = "AI error"; a.informativeText = error.localizedDescription; a.runModal() }
        }
    }
}

@MainActor func penwickSetName(_ store: PenwickStore) {
    let alert = NSAlert()
    alert.messageText = "Your Name"
    alert.informativeText = "Shown to people you write with."
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    field.stringValue = store.authorName
    field.placeholderString = "e.g. Alex"
    alert.accessoryView = field
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")
    if alert.runModal() == .alertFirstButtonReturn {
        let n = field.stringValue.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { store.authorName = n; store.writePresence(); store.readRoster() }
    }
}

@MainActor private func presentPicker(items: [Any]) {
    let picker = NSSharingServicePicker(items: items)
    if let win = NSApp.keyWindow, let cv = win.contentView {
        let rect = NSRect(x: cv.bounds.maxX - 220, y: cv.bounds.maxY - 6, width: 1, height: 1)
        picker.show(relativeTo: rect, of: cv, preferredEdge: .maxY)
    }
}

extension Notification.Name {
    static let openPenwickSettings = Notification.Name("openPenwickSettings")
    static let openPenwickGenerator = Notification.Name("openPenwickGenerator")
    static let openPenwickHistory = Notification.Name("openPenwickHistory")
    static let openPenwickExport = Notification.Name("openPenwickExport")
    static let openPenwickCollaborate = Notification.Name("openPenwickCollaborate")
    static let openPenwickNewProject = Notification.Name("openPenwickNewProject")
    static let penwickJoinRequest = Notification.Name("penwickJoinRequest")
    static let openPenwickAIChat = Notification.Name("openPenwickAIChat")
}

// MARK: - AI (optional: link your own API key, or a local Ollama)

enum AIProvider: String, CaseIterable, Identifiable {
    case off = "Off"
    case ollama = "Ollama (local, free)"
    case anthropic = "Anthropic (Claude)"
    case openai = "OpenAI (ChatGPT)"
    var id: String { rawValue }
    var defaultModel: String {
        switch self {
        case .off: return ""
        case .ollama: return "llama3.2"
        case .anthropic: return "claude-3-5-sonnet-latest"
        case .openai: return "gpt-4o-mini"
        }
    }
    var needsKey: Bool { self == .anthropic || self == .openai }
    var keyId: String {   // stable per-provider id for separate key/model storage
        switch self { case .off: return "off"; case .ollama: return "ollama"; case .anthropic: return "anthropic"; case .openai: return "openai" }
    }
    var shortName: String {
        switch self { case .off: return "Off"; case .ollama: return "Ollama"; case .anthropic: return "Claude"; case .openai: return "ChatGPT" }
    }
}

enum AIClient {
    static var provider: AIProvider { AIProvider(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? "Off") ?? .off }
    // Keys & models are stored PER provider, so switching between Claude/ChatGPT keeps each its own.
    static var key: String { UserDefaults.standard.string(forKey: "aiKey_\(provider.keyId)") ?? "" }
    static var model: String {
        let m = UserDefaults.standard.string(forKey: "aiModel_\(provider.keyId)") ?? ""
        return m.isEmpty ? provider.defaultModel : m
    }
    static var ollamaURL: String {
        let u = UserDefaults.standard.string(forKey: "aiOllamaURL") ?? ""
        return u.isEmpty ? "http://localhost:11434" : u
    }
    static var isConfigured: Bool { provider != .off && (!provider.needsKey || !key.isEmpty) }

    // Installed Ollama models (nil = couldn't reach Ollama; [] = running but empty).
    static func ollamaModels() async -> [String]? {
        guard let url = URL(string: "\(ollamaURL)/api/tags") else { return nil }
        var r = URLRequest(url: url); r.timeoutInterval = 4
        guard let (data, resp) = try? await URLSession.shared.data(for: r),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = j["models"] as? [[String: Any]] else { return nil }
        return arr.compactMap { $0["name"] as? String }
    }
    // Is the Ollama CLI/app installed on this Mac?
    static var ollamaInstalled: Bool {
        ["/usr/local/bin/ollama", "/opt/homebrew/bin/ollama", "/Applications/Ollama.app"].contains { FileManager.default.fileExists(atPath: $0) }
    }
    // Launch the Ollama app (which starts its local server).
    @discardableResult static func startOllamaApp() -> Bool {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = ["-ga", "Ollama"]
        do { try p.run(); return true } catch { return false }
    }

    enum AIError: LocalizedError { case notConfigured, badResponse(String)
        var errorDescription: String? {
            switch self { case .notConfigured: return "No AI is linked. Open Settings → AI."
            case .badResponse(let s): return s } }
    }

    static func complete(system: String, prompt: String, maxTokens: Int = 700) async throws -> String {
        let p = provider
        guard p != .off else { throw AIError.notConfigured }
        var req: URLRequest
        switch p {
        case .anthropic:
            guard !key.isEmpty else { throw AIError.notConfigured }
            req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.httpMethod = "POST"
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": model, "max_tokens": maxTokens, "system": system,
                "messages": [["role": "user", "content": prompt]]])
        case .openai:
            guard !key.isEmpty else { throw AIError.notConfigured }
            req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            req.httpMethod = "POST"
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": model, "max_tokens": maxTokens,
                "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]]])
        case .ollama:
            req = URLRequest(url: URL(string: "\(ollamaURL)/api/chat")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": model, "stream": false,
                "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]]])
        case .off: throw AIError.notConfigured
        }
        req.timeoutInterval = 60
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIError.badResponse("Error \(http.statusCode): \(body.prefix(200))")
        }
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIError.badResponse("Unexpected response.") }
        switch p {
        case .anthropic:
            if let content = j["content"] as? [[String: Any]], let t = content.first?["text"] as? String { return t }
        case .openai:
            if let ch = j["choices"] as? [[String: Any]], let m = ch.first?["message"] as? [String: Any], let t = m["content"] as? String { return t }
        case .ollama:
            if let m = j["message"] as? [String: Any], let t = m["content"] as? String { return t }
        case .off: break
        }
        throw AIError.badResponse("Couldn't read the reply.")
    }
}

// MARK: - Settings (in-app panel, opened via ⌘, or the gear button)

struct SettingsView: View {
    @EnvironmentObject var store: PenwickStore
    @AppStorage("appearance") private var appearance = "auto"
    @AppStorage("aiProvider") private var aiProvider = "Off"
    @AppStorage("aiOllamaURL") private var aiOllamaURL = ""
    @State private var aiTesting = false
    @State private var aiTestResult = ""
    var onClose: () -> Void = {}

    private var providerObj: AIProvider { AIProvider(rawValue: aiProvider) ?? .off }
    // Per-provider key & model — switching providers shows that provider's own values.
    private var keyBinding: Binding<String> {
        let k = "aiKey_\(providerObj.keyId)"
        return Binding(get: { UserDefaults.standard.string(forKey: k) ?? "" }, set: { UserDefaults.standard.set($0, forKey: k) })
    }
    private var modelBinding: Binding<String> {
        let k = "aiModel_\(providerObj.keyId)"
        return Binding(get: { UserDefaults.standard.string(forKey: k) ?? "" }, set: { UserDefaults.standard.set($0, forKey: k) })
    }

    private func testAI() {
        aiTesting = true; aiTestResult = ""
        Task {
            do {
                let r = try await AIClient.complete(system: "Reply with the single word OK.", prompt: "Say OK", maxTokens: 10)
                let ok = !r.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                await MainActor.run { aiTestResult = ok ? "Connected" : "Empty reply"; aiTesting = false }
            } catch {
                await MainActor.run { aiTestResult = error.localizedDescription; aiTesting = false }
            }
        }
    }
    // Auto-set-up Ollama: detect models, launch the app if needed, pick a model for you.
    private func setupOllama() {
        aiTesting = true; aiTestResult = ""
        Task {
            func finish(_ models: [String]) {
                if modelBinding.wrappedValue.isEmpty { modelBinding.wrappedValue = models[0] }
                aiTestResult = "Connected — using \(AIClient.model)"; aiTesting = false
            }
            if let m = await AIClient.ollamaModels() {
                if m.isEmpty { await MainActor.run { aiTestResult = "Ollama is running but has no models. In Terminal run:  ollama pull llama3.2"; aiTesting = false } }
                else { await MainActor.run { finish(m) } }
                return
            }
            // Not reachable — try to launch the Ollama app, then retry.
            if AIClient.ollamaInstalled {
                await MainActor.run { aiTestResult = "Starting Ollama…" }
                AIClient.startOllamaApp()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if let m = await AIClient.ollamaModels(), !m.isEmpty { await MainActor.run { finish(m) }; return }
                await MainActor.run { aiTestResult = "Ollama started but has no models yet. Run:  ollama pull llama3.2"; aiTesting = false }
            } else {
                await MainActor.run { aiTestResult = "Ollama isn't installed. Get it free at ollama.com, then click again."; aiTesting = false }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(colors: [Palette.accent(), Palette.accentDark()], startPoint: .top, endPoint: .bottom))
                    .frame(width: 34, height: 34)
                    .overlay(Image(systemName: "gearshape.fill").foregroundStyle(.white).font(.system(size: 15)))
                Text("Settings").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            Divider()

            Form {
                Section("You") {
                    TextField("Your name", text: Binding(get: { store.authorName }, set: { store.authorName = $0 }))
                    Text("Shown to people you collaborate with.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag("auto"); Text("Light").tag("light"); Text("Dark").tag("dark")
                    }
                }
                Section("AI assistant") {
                    Picker("Provider", selection: $aiProvider) {
                        ForEach(AIProvider.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    .onChange(of: aiProvider) { _, new in
                        aiTestResult = ""
                        if new == AIProvider.ollama.rawValue { setupOllama() }   // auto set up on select
                    }
                    if providerObj.needsKey {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Connect your \(providerObj.shortName) account").font(.system(size: 13, weight: .medium))
                                Spacer()
                                if !keyBinding.wrappedValue.isEmpty {
                                    Label("Linked", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green).labelStyle(.titleAndIcon)
                                }
                            }
                            SecureField("Paste your secret key here", text: keyBinding).id("key-\(aiProvider)")
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                                Text("Kept only on this Mac — never sent anywhere but \(providerObj.shortName).").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Link("Get a key ↗", destination: URL(string: providerObj == .anthropic ? "https://console.anthropic.com/settings/keys" : "https://platform.openai.com/api-keys")!).font(.caption)
                            }
                        }
                    }
                    if aiProvider != "Off" {
                        LabeledContent("Model") {
                            TextField("Model", text: modelBinding, prompt: Text(providerObj.defaultModel)).id("model-\(aiProvider)").multilineTextAlignment(.trailing)
                        }
                        if aiProvider == AIProvider.ollama.rawValue {
                            LabeledContent("Ollama address") {
                                TextField("Ollama URL", text: $aiOllamaURL, prompt: Text("http://localhost:11434")).multilineTextAlignment(.trailing)
                            }
                        }
                        HStack {
                            if aiProvider == AIProvider.ollama.rawValue {
                                Button(aiTesting ? "Setting up…" : "Set up & test") { setupOllama() }.buttonStyle(.borderedProminent).tint(Palette.accent()).disabled(aiTesting)
                            } else {
                                Button(aiTesting ? "Checking…" : "Test connection") { testAI() }.buttonStyle(.borderedProminent).tint(Palette.accent()).disabled(aiTesting)
                            }
                            if !aiTestResult.isEmpty {
                                Label(aiTestResult, systemImage: aiTestResult.hasPrefix("Connected") ? "checkmark.circle.fill" : "info.circle")
                                    .font(.caption).foregroundStyle(aiTestResult.hasPrefix("Connected") ? .green : .secondary).labelStyle(.titleAndIcon)
                            }
                        }
                        Text(aiProvider == AIProvider.ollama.rawValue
                             ? "Ollama runs a model right on your Mac — completely free, no key, fully private."
                             : "A Claude.ai / ChatGPT Plus subscription won't work here — those don't include API access. Pay-as-you-go API usage is usually a fraction of a cent per request.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Updates") {
                    LabeledContent("Version", value: Updater.current)
                    Button("Check for Updates…") { checkForUpdates(silent: false) }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 680)
        .frame(minHeight: 560, maxHeight: 700)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.10)))
        .shadow(color: .black.opacity(0.30), radius: 28, y: 12)
    }
}

// MARK: - Auto-update (checks GitHub, self-replaces)

enum Updater {
    // Public release channel: a version.json + Penwick.app.zip live here.
    static let versionURL = URL(string: "https://raw.githubusercontent.com/loaffywoffy/penwick-releases/main/version.json")!
    // No version numbers — the app carries an opaque build code (md5 of its binary).
    // Update simply when our code != the code published on GitHub.
    static var current: String { (Bundle.main.infoDictionary?["PenwickBuildCode"] as? String) ?? "" }

    // Append a unique query so GitHub's CDN can't serve a stale cached copy.
    private static func bust(_ url: URL) -> URL {
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.queryItems = [URLQueryItem(name: "t", value: "\(Int(Date().timeIntervalSince1970))")]
        return c?.url ?? url
    }

    static func check() async -> (url: URL, notes: String)? {
        var req = URLRequest(url: bust(versionURL)); req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = j["code"] as? String, let us = j["url"] as? String, let u = URL(string: us) else { return nil }
        guard code != current, !current.isEmpty else { return nil }
        return (bust(u), (j["notes"] as? String) ?? "")   // fresh zip too, not a cached old one
    }

    @MainActor static func performUpdate(from url: URL) async -> Bool {
        guard let (tmp, _) = try? await URLSession.shared.download(from: url) else { return false }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let zip = caches.appendingPathComponent("Penwick-update.zip")
        let unzip = caches.appendingPathComponent("Penwick-update", isDirectory: true)
        try? FileManager.default.removeItem(at: zip)
        try? FileManager.default.removeItem(at: unzip)
        try? FileManager.default.moveItem(at: tmp, to: zip)
        try? FileManager.default.createDirectory(at: unzip, withIntermediateDirectories: true)

        let ditto = Process(); ditto.launchPath = "/usr/bin/ditto"; ditto.arguments = ["-x", "-k", zip.path, unzip.path]
        try? ditto.run(); ditto.waitUntilExit()
        let newApp = unzip.appendingPathComponent("Penwick.app")
        guard FileManager.default.fileExists(atPath: newApp.path) else { return false }

        // Swap the running app out via a detached shell, then relaunch.
        let dest = Bundle.main.bundleURL.path
        let script = """
        #!/bin/sh
        sleep 1
        rm -rf "\(dest)"
        /usr/bin/ditto "\(newApp.path)" "\(dest)"
        /usr/bin/xattr -dr com.apple.quarantine "\(dest)" 2>/dev/null
        open "\(dest)"
        """
        let scriptURL = caches.appendingPathComponent("penwick-update.sh")
        try? script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let sh = Process(); sh.launchPath = "/bin/sh"; sh.arguments = [scriptURL.path]
        try? sh.run()
        NSApp.terminate(nil)
        return true
    }
}

@MainActor func checkForUpdates(silent: Bool) {
    Task {
        if let upd = await Updater.check() {
            let alert = NSAlert()
            alert.messageText = "Update available"
            alert.informativeText = upd.notes.isEmpty ? "A newer build is available. Update now? Penwick will restart." : upd.notes
            alert.addButton(withTitle: "Update Now")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                let ok = await Updater.performUpdate(from: upd.url)
                if !ok {
                    let a = NSAlert(); a.messageText = "Update failed"
                    a.informativeText = "Couldn't download or install the update. Check your connection and try again."
                    a.runModal()
                }
            }
        } else if !silent {
            let a = NSAlert(); a.messageText = "You're up to date"
            a.informativeText = "You have the latest build of Penwick."
            a.runModal()
        }
    }
}

// On launch, move any OTHER copies of Penwick to the Trash, keeping only the
// running app and the canonical /Applications copy. (Stops the "3 copies in
// Spotlight / which one is real" mess; uses Trash, so it's reversible.)
@MainActor func cleanupDuplicateApps() {
    let fm = FileManager.default
    let me = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
    let keep = URL(fileURLWithPath: "/Applications/Penwick.app").standardizedFileURL
    DispatchQueue.global(qos: .background).async {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        task.arguments = ["kMDItemCFBundleIdentifier == 'com.penwick.app'"]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = Pipe()
        do { try task.run() } catch { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let out = String(data: data, encoding: .utf8) else { return }
        let dupes = out.split(separator: "\n").map(String.init).compactMap { p -> URL? in
            let u = URL(fileURLWithPath: p).resolvingSymlinksInPath().standardizedFileURL
            guard u.lastPathComponent == "Penwick.app", u != me, u != keep else { return nil }
            // Confirm it really is Penwick before touching it.
            guard Bundle(url: u)?.bundleIdentifier == "com.penwick.app" else { return nil }
            return u
        }
        guard !dupes.isEmpty else { return }
        DispatchQueue.main.async {
            for u in dupes { try? fm.trashItem(at: u, resultingItemURL: nil) }
        }
    }
}

// MARK: - Model

struct Chapter: Identifiable, Equatable {
    let url: URL
    var text: NSAttributedString
    var modified: Date
    var id: URL { url }

    static func == (a: Chapter, b: Chapter) -> Bool {
        a.url == b.url && a.modified == b.modified && a.text.isEqual(to: b.text)
    }

    var plain: String { text.string }
    private var cleanLines: [String] {
        plain.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    var title: String { cleanLines.first ?? "Untitled" }   // first NON-empty line
    var snippet: String {
        let body = cleanLines.dropFirst().joined(separator: " ")
        return body.isEmpty ? "Empty" : body
    }
    var wordCount: Int { plain.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count }
}

struct Comment: Identifiable, Codable, Equatable {
    var id: String
    var text: String
    var quote: String
    var author: String
    var location: Int
    var length: Int
    var date: Date
}

struct Collaborator: Identifiable, Equatable {
    let id: String
    let name: String
    let lastSeen: Date
    var isMe: Bool
    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.compactMap { $0.first }.map(String.init).joined()
        return s.isEmpty ? "?" : s.uppercased()
    }
    var color: Color {
        let h = abs(id.hashValue)
        let hues = [0.62, 0.0, 0.33, 0.08, 0.78, 0.5, 0.92]
        return Color(hue: hues[h % hues.count], saturation: 0.55, brightness: 0.85)
    }
}

struct Project: Identifiable, Equatable {
    let url: URL          // directory
    var chapters: [Chapter]
    var id: URL { url }
    var name: String { url.lastPathComponent }
    var totalWords: Int { chapters.reduce(0) { $0 + $1.wordCount } }
    var lastEdited: Date? { chapters.map { $0.modified }.max() }
}

// Page-number styling — saved PER PROJECT (each manuscript keeps its own).
struct PageNumberPrefs: Codable, Equatable {
    var show = true
    var numberFirst = true
    var fontName = ""        // "" = system
    var size = 11.0
    var colorHex = ""        // "" = default gray
}

// MARK: - Store

@MainActor
final class PenwickStore: ObservableObject {
    @Published var projects: [Project] = []
    @Published var selection: URL? { didSet { if selection != oldValue { loadPageNumberPrefs() } } }
    @Published var pageNumberPrefs = PageNumberPrefs()   // for the current project
    @Published var chapterEmojis: [URL: String] = [:]    // per-chapter emoji tags
    @Published var commentsByChapter: [URL: [Comment]] = [:]

    let root: URL
    let iCloudAvailable: Bool
    private var saveTimers: [URL: Timer] = [:]
    private var watchTimer: Timer?
    private var lastSignature = ""

    // Identity + live "who's here" roster. Identity (id + name) lives in a synced
    // file in the user's own iCloud folder, so the SAME Apple account on multiple
    // devices is ONE person — not one per device.
    @Published var authorName: String = "" { didSet { if loadedIdentity { saveIdentity() } } }
    @Published var collaborators: [Collaborator] = []
    @Published var scriptChapters: Set<URL> = []   // chapters in screenplay mode
    private var presenceTimer: Timer?

    func isScript(_ url: URL) -> Bool { scriptChapters.contains(url) }
    func setScript(_ on: Bool, for url: URL) {
        UserDefaults.standard.set(on, forKey: "script:" + url.path)
        if on { scriptChapters.insert(url) } else { scriptChapters.remove(url) }
    }
    private(set) var userID: String = ""
    private var loadedIdentity = false
    private var identityURL: URL { root.appendingPathComponent(".me.json") }

    private func loadOrCreateIdentity() {
        if let data = try? Data(contentsOf: identityURL),
           let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = d["id"] as? String, !id.isEmpty {
            userID = id
            authorName = (d["name"] as? String) ?? NSFullUserName()
        } else {
            userID = UUID().uuidString
            authorName = NSFullUserName()
        }
        loadedIdentity = true
        saveIdentity()
    }
    private func saveIdentity() {
        guard !userID.isEmpty else { return }
        let dict: [String: Any] = ["id": userID, "name": authorName]
        if let data = try? JSONSerialization.data(withJSONObject: dict) { try? data.write(to: identityURL) }
    }

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        let cloudAvailable = FileManager.default.fileExists(atPath: cloud.path)
        self.iCloudAvailable = cloudAvailable

        let base = cloudAvailable
            ? cloud.appendingPathComponent("Penwick", isDirectory: true)
            : home.appendingPathComponent("Documents/Penwick", isDirectory: true)
        self.root = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        // Migrate from the previous "Marble" folder.
        let prior = cloudAvailable
            ? cloud.appendingPathComponent("Marble", isDirectory: true)
            : home.appendingPathComponent("Documents/Marble", isDirectory: true)
        if let old = try? FileManager.default.contentsOfDirectory(at: prior, includingPropertiesForKeys: nil) {
            for url in old {
                let dest = base.appendingPathComponent(url.lastPathComponent)
                if !FileManager.default.fileExists(atPath: dest.path) {
                    try? FileManager.default.moveItem(at: url, to: dest)
                }
            }
        }

        // Loose .rtf files at the root → move into a default project folder.
        if let items = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey]) {
            let loose = items.filter { $0.pathExtension.lowercased() == "rtf" }
            if !loose.isEmpty {
                let proj = base.appendingPathComponent("My Manuscript", isDirectory: true)
                try? FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
                for f in loose {
                    try? FileManager.default.moveItem(at: f, to: proj.appendingPathComponent(f.lastPathComponent))
                }
            }
        }

        // Tidy up: drop old leftover app folders (Quill/Marble) if they're empty,
        // and remove stray Finder .DS_Store files so the iCloud folder stays clean.
        let parent = cloudAvailable ? cloud : home.appendingPathComponent("Documents", isDirectory: true)
        for legacy in ["Quill", "Marble"] {
            let dir = parent.appendingPathComponent(legacy, isDirectory: true)
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.filter { $0 != ".DS_Store" } ?? []
            if FileManager.default.fileExists(atPath: dir.path), contents.isEmpty { try? FileManager.default.removeItem(at: dir) }
        }
        try? FileManager.default.removeItem(at: base.appendingPathComponent(".DS_Store"))

        reload()
        if projects.isEmpty {
            seedWelcomeProject()   // ship a formatted sample manuscript for new users
            reload()
        }
        selection = nil   // start on the Home pane, not straight into a chapter
        loadOrCreateIdentity()   // account-stable identity, synced across the user's devices
        lastSignature = folderSignature()
        startWatching()
        startPresence()
    }

    // MARK: Presence / roster
    private func startPresence() {
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.writePresence(); self?.readRoster() }
        }
    }
    private func presenceDir(_ project: Project) -> URL {
        project.url.appendingPathComponent(".penwick", isDirectory: true)
    }
    func writePresence() {
        guard let proj = currentProject, !authorName.isEmpty, !userID.isEmpty else { return }
        let dir = presenceDir(proj)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dict: [String: Any] = ["name": authorName, "t": Date().timeIntervalSince1970]
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            try? data.write(to: dir.appendingPathComponent("presence-\(userID).json"))
        }
    }
    func readRoster() {
        guard let proj = currentProject else { collaborators = []; return }
        let files = (try? FileManager.default.contentsOfDirectory(at: presenceDir(proj), includingPropertiesForKeys: nil)) ?? []
        let now = Date().timeIntervalSince1970
        // Dedupe by name so the same person on two devices (or a stale entry) shows once.
        var byName: [String: Collaborator] = [:]
        for f in files where f.lastPathComponent.hasPrefix("presence-") && f.pathExtension == "json" {
            guard let data = try? Data(contentsOf: f),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = dict["name"] as? String, let t = dict["t"] as? Double, now - t < 150 else { continue }
            let id = f.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "presence-", with: "")
            let c = Collaborator(id: id, name: name, lastSeen: Date(timeIntervalSince1970: t), isMe: id == userID || name == authorName)
            if let existing = byName[name], existing.lastSeen >= c.lastSeen { continue }
            byName[name] = c
        }
        let next = byName.values.sorted { ($0.isMe ? 0 : 1, $0.name) < ($1.isMe ? 0 : 1, $1.name) }
        // Only publish when the set of people actually changed (avoids periodic re-renders
        // that could swallow button clicks).
        if next.map(\.id) != collaborators.map(\.id) { collaborators = next }
    }

    // Poll iCloud Drive for changes from collaborators and refresh the binder.
    private func startWatching() {
        watchTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForExternalChanges(); self?.scanJoinRequests() }
        }
    }
    private func checkForExternalChanges() {
        let sig = folderSignature()
        guard sig != lastSignature else { return }
        lastSignature = sig
        reload()   // open chapter's live editor is untouched; binder + other chapters refresh
    }
    private func folderSignature() -> String {
        let fm = FileManager.default
        var parts: [String] = []
        for dir in projectFolders() {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
            for f in files where f.pathExtension.lowercased() == "rtf" {
                let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                parts.append("\(f.path):\(m.timeIntervalSince1970)")
            }
        }
        return parts.sorted().joined(separator: "|")
    }

    // External/shared project folders the user linked in (e.g. a received iCloud share).
    var externalProjectURLs: [URL] {
        (UserDefaults.standard.array(forKey: "externalProjects") as? [String] ?? []).map { URL(fileURLWithPath: $0) }
    }
    func isExternal(_ project: Project) -> Bool { !project.url.path.hasPrefix(root.path) }

    @discardableResult
    func openExternalProject(_ url: URL) -> Project? {
        var arr = UserDefaults.standard.array(forKey: "externalProjects") as? [String] ?? []
        if !arr.contains(url.path) { arr.append(url.path); UserDefaults.standard.set(arr, forKey: "externalProjects") }
        reload()
        let proj = projects.first { $0.url.path == url.path }
        selection = proj?.chapters.first?.url
        return proj
    }
    func unlinkExternalProject(_ project: Project) {
        var arr = UserDefaults.standard.array(forKey: "externalProjects") as? [String] ?? []
        arr.removeAll { $0 == project.url.path }
        UserDefaults.standard.set(arr, forKey: "externalProjects")
        reload()
    }

    // MARK: Collaboration room codes — a memorable 3-word join code (e.g. TAN-ARM-HER).
    // Stored in <project>/.penwick/room.json so it travels with the shared folder.
    // Common, easy-to-spell 3-letter words only.
    static let roomWords = ["the","and","for","are","but","not","you","all","can","her","was","one",
        "our","out","day","get","has","him","his","how","man","new","now","old","see","two","way","who",
        "boy","did","its","let","put","say","she","too","use","dad","age","ago","air","arm","art","ask",
        "bad","bag","ban","bar","bat","bed","big","bit","box","buy","car","cat","cop","cow","cry","cup",
        "cut","dog","dry","due","ear","eat","egg","end","eye","far","fat","few","fly","fun","gas","got",
        "gun","gut","guy","had","ham","hat","hit","hot","hug","ice","job","joy","key","kid","kit","law",
        "lay","leg","lie","lip","lot","low","mad","map","mix","mom","mud","mug","nap","net","odd","oil",
        "own","pad","pan","pay","pen","pet","pie","pig","pin","pit","pop","pot","pro","pub","raw","red",
        "rid","rip","rod","row","rub","run","sad","sat","set","shy","sin","sir","sit","six","ski","sky",
        "sob","son","spy","sum","sun","tab","tan","tar","tax","tea","ten","tie","tip","toe","top","toy",
        "try","tub","tug","van","vow","war","web","wed","wet","win","wit","woe","won","yes","yet","zoo",
        "ace","act","add","aid","aim","arc","ash","aye","bay","bee","bow"]

    private func roomFile(_ p: Project) -> URL { p.url.appendingPathComponent(".penwick/room.json") }
    private func canonCode(_ s: String) -> String { String(s.uppercased().filter { $0 >= "A" && $0 <= "Z" }) }

    func roomCode(for p: Project) -> String? {
        guard let d = try? Data(contentsOf: roomFile(p)),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let c = j["code"] as? String else { return nil }
        return c
    }
    @discardableResult func ensureRoomCode(for p: Project) -> String {
        roomCode(for: p) ?? regenerateRoomCode(for: p)
    }
    @discardableResult func regenerateRoomCode(for p: Project) -> String {
        var picks: [String] = []
        while picks.count < 3 { let w = Self.roomWords.randomElement() ?? "pen"; if !picks.contains(w) { picks.append(w) } }
        let code = picks.map { $0.uppercased() }.joined(separator: "-")
        let dir = p.url.appendingPathComponent(".penwick", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: ["code": code]) { try? data.write(to: roomFile(p)) }
        return code
    }

    // Find the project folder whose room code matches. Scans linked projects plus the
    // iCloud Drive (where an accepted share lands) so a code can "auto-match".
    func findRoomFolder(code entered: String) -> URL? {
        let target = canonCode(entered)
        guard target.count == 9 else { return nil }
        let fm = FileManager.default
        var candidates = projectFolders()
        let iCloudRoot = root.deletingLastPathComponent()   // …/CloudDocs
        for parent in [iCloudRoot, root] {
            if let items = try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                for d in items where (try? d.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { candidates.append(d) }
            }
        }
        for url in candidates {
            guard let d = try? Data(contentsOf: url.appendingPathComponent(".penwick/room.json")),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let c = j["code"] as? String, canonCode(c) == target else { continue }
            return url
        }
        return nil
    }

    func openMatchedProject(_ url: URL) {
        if url.path.hasPrefix(root.path) { reload(); selection = projects.first { $0.url == url }?.chapters.first?.url }
        else { _ = openExternalProject(url) }
    }

    // MARK: Join approval — the joiner asks, the host must approve before they're let in.
    private var promptedRequests: Set<String> = []

    func requestJoin(at url: URL) {
        let dir = url.appendingPathComponent(".penwick/requests", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dict: [String: Any] = ["id": userID, "name": authorName, "t": Date().timeIntervalSince1970]
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            try? data.write(to: dir.appendingPathComponent("\(userID).json"))
        }
    }
    // "approved" / "denied" / nil — what the host decided about MY request.
    func joinDecision(at url: URL) -> String? {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.appendingPathComponent(".penwick/approved/\(userID).json").path) { return "approved" }
        if fm.fileExists(atPath: url.appendingPathComponent(".penwick/denied/\(userID).json").path) { return "denied" }
        return nil
    }
    private func decisionExists(_ proj: URL, _ id: String) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: proj.appendingPathComponent(".penwick/approved/\(id).json").path)
            || fm.fileExists(atPath: proj.appendingPathComponent(".penwick/denied/\(id).json").path)
    }
    private func writeDecision(_ proj: URL, _ kind: String, _ id: String) {
        let dir = proj.appendingPathComponent(".penwick/\(kind)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data("{}".utf8).write(to: dir.appendingPathComponent("\(id).json"))
    }
    func approveJoin(_ proj: URL, id: String) { writeDecision(proj, "approved", id) }
    func denyJoin(_ proj: URL, id: String) { writeDecision(proj, "denied", id) }

    // Host side: look for join requests across all projects and surface the first
    // undecided one for an Approve/Deny prompt.
    func scanJoinRequests() {
        for p in projects {
            let reqDir = p.url.appendingPathComponent(".penwick/requests")
            guard let files = try? FileManager.default.contentsOfDirectory(at: reqDir, includingPropertiesForKeys: nil) else { continue }
            for f in files where f.pathExtension == "json" {
                guard let d = try? Data(contentsOf: f),
                      let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let id = j["id"] as? String, id != userID else { continue }
                if decisionExists(p.url, id) { continue }
                let key = "\(p.url.path)|\(id)"
                if promptedRequests.contains(key) { continue }
                promptedRequests.insert(key)
                let name = (j["name"] as? String) ?? "Someone"
                NotificationCenter.default.post(name: .penwickJoinRequest,
                                                object: ["project": p.url, "id": id, "name": name, "projectName": p.name])
            }
        }
    }

    // All project folders: local subfolders of root + linked external ones.
    private func projectFolders() -> [URL] {
        let fm = FileManager.default
        var dirs: [URL] = []
        let local = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        for d in local where (try? d.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { dirs.append(d) }
        for ext in externalProjectURLs where fm.fileExists(atPath: ext.path) && !dirs.contains(where: { $0.path == ext.path }) {
            dirs.append(ext)
        }
        return dirs
    }

    // Real page count for a chapter — lays it out into page-sized containers (same as the editor).
    func pageCount(for attr: NSAttributedString) -> Int {
        guard attr.length > 0 else { return 1 }
        let storage = NSTextStorage(attributedString: attr)
        let lm = NSLayoutManager(); storage.addLayoutManager(lm)
        let size = NSSize(width: RichTextEditor.pageW - 2 * RichTextEditor.margin, height: RichTextEditor.pageH - 2 * RichTextEditor.margin)
        func add() { let c = NSTextContainer(size: size); c.lineFragmentPadding = 0; lm.addTextContainer(c) }
        add()
        let total = lm.numberOfGlyphs
        let str = attr.string as NSString
        let endsNL = str.length > 0 && str.character(at: str.length - 1) == 0x0A
        let lineH = lm.defaultLineHeight(for: bodyNSFont()) + 2
        var guardN = 0
        while guardN < 4000 {
            guardN += 1
            guard let last = lm.textContainers.last else { break }
            lm.ensureLayout(for: last)
            if lm.glyphRange(for: last).upperBound < total { add(); continue }
            var fits = true
            if lm.extraLineFragmentTextContainer === last { fits = lm.extraLineFragmentRect.maxY <= last.size.height + 0.5 }
            else if endsNL && lm.glyphRange(for: last).length > 0 { fits = lm.usedRect(for: last).maxY + lineH <= last.size.height + 0.5 }
            if fits { break }
            add()
        }
        return max(1, lm.textContainers.count)
    }

    func loadAttributed(_ url: URL) -> NSAttributedString {
        if url.pathExtension.lowercased() == "rtf", let data = try? Data(contentsOf: url) {
            // Auto-detect RTF vs flattened RTFD (chapters with images) and keep attachments.
            if let a = try? NSAttributedString(data: data, options: [:], documentAttributes: nil) { return a }
            if let a = NSAttributedString(rtf: data, documentAttributes: nil) { return a }
        }
        let s = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return NSAttributedString(string: s, attributes: [.font: bodyNSFont(), .foregroundColor: NSColor.labelColor])
    }

    func reload() {
        let fm = FileManager.default
        var result: [Project] = []
        for dir in projectFolders() {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
            var chapters: [Chapter] = []
            for url in files where url.pathExtension.lowercased() == "rtf" {
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                chapters.append(Chapter(url: url, text: loadAttributed(url), modified: mod))
            }
            chapters.sort { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
            result.append(Project(url: dir, chapters: chapters))
        }
        projects = result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        scriptChapters = Set(projects.flatMap { $0.chapters }.map { $0.url }
            .filter { UserDefaults.standard.bool(forKey: "script:" + $0.path) })
        loadPageNumberPrefs()   // pick up the current project's saved page-number style
        loadChapterEmojis()
        loadComments()
    }

    // MARK: Comments / margin notes — stored per project in .penwick/comments.json (filename → [Comment]).
    private func commentsFile(_ dir: URL) -> URL { dir.appendingPathComponent(".penwick/comments.json") }
    private func loadComments() {
        var map: [URL: [Comment]] = [:]
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        for p in projects {
            guard let d = try? Data(contentsOf: commentsFile(p.url)),
                  let j = try? dec.decode([String: [Comment]].self, from: d) else { continue }
            for ch in p.chapters { if let cs = j[ch.url.lastPathComponent], !cs.isEmpty { map[ch.url] = cs } }
        }
        commentsByChapter = map
    }
    func comments(for url: URL) -> [Comment] { (commentsByChapter[url] ?? []).sorted { $0.location < $1.location } }
    // Best range for a comment: the stored one if the text still matches there, else
    // re-find the quoted text (so comments don't drift when the chapter is edited).
    func resolvedRange(_ c: Comment, in text: String) -> NSRange? {
        let ns = text as NSString
        let stored = NSRange(location: c.location, length: c.length)
        if c.length > 0, NSMaxRange(stored) <= ns.length, ns.substring(with: stored) == c.quote { return stored }
        if !c.quote.isEmpty {
            let f = ns.range(of: c.quote)
            if f.location != NSNotFound { return f }
        }
        return (c.length > 0 && NSMaxRange(stored) <= ns.length) ? stored : nil
    }
    private func saveComments(for url: URL) {
        let dir = url.deletingLastPathComponent()
        let file = commentsFile(dir)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        var j: [String: [Comment]] = [:]
        if let d = try? Data(contentsOf: file), let existing = try? { () -> [String: [Comment]] in
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
            return try dec.decode([String: [Comment]].self, from: d)
        }() { j = existing }
        j[url.lastPathComponent] = commentsByChapter[url] ?? []
        if (j[url.lastPathComponent]?.isEmpty ?? true) { j.removeValue(forKey: url.lastPathComponent) }
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent(".penwick", isDirectory: true), withIntermediateDirectories: true)
        if let data = try? enc.encode(j) { try? data.write(to: file) }
    }
    func addComment(_ text: String, range: NSRange, quote: String, for url: URL) {
        let c = Comment(id: UUID().uuidString, text: text, quote: quote,
                        author: authorName.isEmpty ? "You" : authorName,
                        location: range.location, length: range.length, date: Date())
        commentsByChapter[url, default: []].append(c)
        saveComments(for: url)
    }
    func deleteComment(_ id: String, for url: URL) {
        commentsByChapter[url]?.removeAll { $0.id == id }
        saveComments(for: url)
    }

    // MARK: Per-chapter emoji tags — stored in <project>/.penwick/emoji.json (filename → emoji).
    private func emojiFile(forProjectAt dir: URL) -> URL { dir.appendingPathComponent(".penwick/emoji.json") }
    private func loadChapterEmojis() {
        var map: [URL: String] = [:]
        for p in projects {
            guard let d = try? Data(contentsOf: emojiFile(forProjectAt: p.url)),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { continue }
            for ch in p.chapters { if let e = j[ch.url.lastPathComponent] { map[ch.url] = e } }
            if let pe = j["__project__"] { map[p.url] = pe }   // emoji for the manuscript itself
        }
        chapterEmojis = map
    }
    func emoji(for url: URL) -> String? { chapterEmojis[url] }
    // Emoji for the whole manuscript (project folder), stored under "__project__".
    func setProjectEmoji(_ emoji: String?, projectURL dir: URL) {
        let file = emojiFile(forProjectAt: dir)
        var j: [String: String] = [:]
        if let d = try? Data(contentsOf: file), let e = try? JSONSerialization.jsonObject(with: d) as? [String: String] { j = e }
        if let e = emoji, !e.isEmpty { j["__project__"] = e; chapterEmojis[dir] = e } else { j.removeValue(forKey: "__project__"); chapterEmojis.removeValue(forKey: dir) }
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent(".penwick", isDirectory: true), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: j) { try? data.write(to: file) }
    }
    func setEmoji(_ emoji: String?, for url: URL) {
        let dir = url.deletingLastPathComponent()
        let file = emojiFile(forProjectAt: dir)
        var j: [String: String] = [:]
        if let d = try? Data(contentsOf: file), let existing = try? JSONSerialization.jsonObject(with: d) as? [String: String] { j = existing }
        let key = url.lastPathComponent
        if let e = emoji, !e.isEmpty { j[key] = e; chapterEmojis[url] = e } else { j.removeValue(forKey: key); chapterEmojis.removeValue(forKey: url) }
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent(".penwick", isDirectory: true), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: j) { try? data.write(to: file) }
    }

    // MARK: Importing dropped files
    static let importableExtensions = ["md","markdown","txt","text","rtf","rtfd","fountain","doc","docx","odt","html","htm","webarchive","pages"]
    func isImportable(_ url: URL) -> Bool { Self.importableExtensions.contains(url.pathExtension.lowercased()) }

    func attributedFromFile(_ url: URL) -> NSAttributedString? {
        let ext = url.pathExtension.lowercased()
        let rich = ["rtf","rtfd","doc","docx","odt","html","htm","webarchive"]
        if rich.contains(ext), let a = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) { return a }
        if let s = try? String(contentsOf: url, encoding: .utf8) {
            return NSAttributedString(string: s, attributes: [.font: bodyNSFont(), .foregroundColor: NSColor(white: 0.12, alpha: 1), .paragraphStyle: defaultParagraphStyle()])
        }
        return nil
    }

    // Add a dropped file as its own chapter in a project.
    @discardableResult func importChapter(from url: URL, into project: Project) -> URL? {
        guard let attr = attributedFromFile(url) else { return nil }
        let existing = (try? FileManager.default.contentsOfDirectory(at: project.url, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "rtf" } ?? []
        let n = existing.count + 1
        let base = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "/", with: "-")
        let name = String(format: "%02d %@.rtf", n, base)
        let dest = project.url.appendingPathComponent(name)
        let full = NSRange(location: 0, length: attr.length)
        let data: Data? = attr.containsAttachments(in: full)
            ? attr.rtfd(from: full, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
            : attr.rtf(from: full, documentAttributes: [:])
        guard let data = data else { return nil }
        try? data.write(to: dest)
        reload()
        return projects.first { $0.url == project.url }?.chapters.first { $0.url.lastPathComponent == name }?.url
    }

    // Lookups
    func chapter(_ url: URL) -> Chapter? { projects.flatMap { $0.chapters }.first { $0.url == url } }
    func attributed(for url: URL) -> NSAttributedString { chapter(url)?.text ?? NSAttributedString(string: "") }
    var selectedChapter: Chapter? { selection.flatMap { chapter($0) } }
    var currentProject: Project? {
        if let sel = selection, let p = projects.first(where: { $0.chapters.contains { $0.url == sel } }) { return p }
        return projects.first
    }

    // Per-project page-number styling, persisted in UserDefaults keyed by project name.
    private static let pnPrefsKey = "pageNumberPrefsByProject"
    private func allPageNumberPrefs() -> [String: PageNumberPrefs] {
        guard let data = UserDefaults.standard.data(forKey: Self.pnPrefsKey),
              let map = try? JSONDecoder().decode([String: PageNumberPrefs].self, from: data) else { return [:] }
        return map
    }
    func loadPageNumberPrefs() {
        let key = currentProject?.name ?? ""
        pageNumberPrefs = allPageNumberPrefs()[key] ?? PageNumberPrefs()
    }
    func savePageNumberPrefs() {
        let key = currentProject?.name ?? ""
        guard !key.isEmpty else { return }
        var map = allPageNumberPrefs()
        map[key] = pageNumberPrefs
        if let data = try? JSONEncoder().encode(map) { UserDefaults.standard.set(data, forKey: Self.pnPrefsKey) }
    }

    // Page-style navigation between chapters of the current project.
    func adjacentChapter(_ offset: Int) -> URL? {
        guard let sel = selection,
              let p = projects.first(where: { $0.chapters.contains { $0.url == sel } }),
              let i = p.chapters.firstIndex(where: { $0.url == sel }) else { return nil }
        let j = i + offset
        guard j >= 0 && j < p.chapters.count else { return nil }
        return p.chapters[j].url
    }
    func goChapter(_ offset: Int) { if let u = adjacentChapter(offset) { selection = u } }
    func openFirstChapter(of project: Project) { selection = project.chapters.first?.url }
    // 1-based (index, count) for the current chapter, or nil on Home. Same project lookup as adjacentChapter.
    func chapterPosition() -> (index: Int, count: Int)? {
        guard let sel = selection,
              let p = projects.first(where: { $0.chapters.contains { $0.url == sel } }),
              let i = p.chapters.firstIndex(where: { $0.url == sel }) else { return nil }
        return (i + 1, p.chapters.count)
    }

    // Mutations
    // The default sample manuscript shipped to brand-new users — a formatted tour
    // of Penwick's features across five differently-styled chapters.
    func seedWelcomeProject() {
        let dir = root.appendingPathComponent("Welcome to Penwick", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: dir.path) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let ink  = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        let blue = NSColor(srgbRed: 0.00, green: 0.40, blue: 0.80, alpha: 1)
        let warm = NSColor(srgbRed: 0.62, green: 0.45, blue: 0.24, alpha: 1)
        let green = NSColor(srgbRed: 0.16, green: 0.50, blue: 0.34, alpha: 1)
        let fmgr = NSFontManager.shared
        func serif(_ s: CGFloat, _ b: Bool = false) -> NSFont { NSFont(name: b ? "Georgia-Bold" : "Georgia", size: s) ?? NSFont.systemFont(ofSize: s, weight: b ? .bold : .regular) }
        func serifI(_ s: CGFloat) -> NSFont { fmgr.convert(serif(s), toHaveTrait: .italicFontMask) }
        func mono(_ s: CGFloat) -> NSFont { NSFont(name: "Menlo", size: s) ?? NSFont.monospacedSystemFont(ofSize: s, weight: .regular) }
        func pp(_ a: NSTextAlignment) -> NSMutableParagraphStyle { let p = NSMutableParagraphStyle(); p.alignment = a; p.lineSpacing = 3; p.paragraphSpacing = 9; return p }
        func r(_ t: String, _ f: NSFont, _ c: NSColor = ink, _ a: NSTextAlignment = .left, u: Bool = false, s: Bool = false) -> NSAttributedString {
            var at: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: c, .paragraphStyle: pp(a)]
            if u { at[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if s { at[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            return NSAttributedString(string: t, attributes: at)
        }
        func write(_ name: String, _ parts: [NSAttributedString]) {
            let m = NSMutableAttributedString(); parts.forEach { m.append($0) }
            guard let data = try? m.rtf(from: NSRange(location: 0, length: m.length),
                                        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) else { return }
            try? data.write(to: dir.appendingPathComponent(name))
        }

        write("01 Welcome to Penwick.rtf", [
            r("Welcome to Penwick\n", serif(30, true), ink, .center),
            r("Your story starts here.\n\n", serifI(18), warm, .center),
            r("Penwick is a native Mac app for writing books and screenplays. This little sample manuscript is a tour — each chapter shows off a different feature, and each one is formatted differently so you can see what's possible.\n\n", serif(17)),
            r("Open the next chapter from the sidebar on the left, or use the ", serif(17)),
            r("Previous / Next", serif(17, true), blue),
            r(" buttons at the bottom of the page.\n\n", serif(17)),
            r("When you're ready, delete this project and start your own. Happy writing.\n", serifI(16), warm),
        ])
        write("02 Writing & Formatting.rtf", [
            r("Writing & Formatting\n\n", serif(26, true), blue),
            r("Select any text and use the bar at the top of the page. You can make it ", serif(17)),
            r("bold", serif(17, true)), r(", ", serif(17)), r("italic", serifI(17)), r(", ", serif(17)),
            r("underlined", serif(17), ink, .left, u: true), r(", ", serif(17)),
            r("struck through", serif(17), ink, .left, s: true), r(", or ", serif(17)),
            r("any colour you like", serif(17, true), blue), r(".\n\n", serif(17)),
            r("Every font on your Mac is available, shown in its own typeface:\n", serif(17)),
            r("•  This line is Helvetica Neue\n", NSFont(name: "Helvetica Neue", size: 16) ?? .systemFont(ofSize: 16)),
            r("•  This line is Menlo (monospace)\n", mono(15)),
            r("•  This line is Georgia, the classic book serif\n\n", serif(16)),
            r("Lists continue automatically — press Return and the next item appears:\n", serif(17)),
            r("•  First idea\n", serif(17)), r("•  Second idea\n", serif(17)), r("•  Third idea\n\n", serif(17)),
            r("1.  Outline the chapter\n", serif(17)), r("2.  Write the messy draft\n", serif(17)), r("3.  Edit until it sings\n\n", serif(17)),
            r("Alignment works too — this line is centered.\n", serif(17), ink, .center),
            r("And this one is right-aligned.\n", serif(17), ink, .right),
        ])
        var pages: [NSAttributedString] = [
            r("Real Pages\n\n", serif(32, true), ink, .center),
            r("Unlike a notes app, Penwick lays your words onto real, separate pages — just like Word or Pages. As you write past the bottom of one page, a fresh sheet appears beneath it. Turn page numbers on or off from the footer, and tap a number to restyle it.\n\n", serif(17)),
        ]
        for i in 1...9 {
            pages.append(r("Paragraph \(i). ", serif(17, true), blue))
            pages.append(r("Keep typing and watch the page fill. When this paragraph runs past the bottom margin, Penwick flows the overflow onto a brand-new page automatically, and the page number in the footer follows along. Delete enough text and the empty page disappears again. This is the heart of writing long-form work that actually feels like a manuscript.\n\n", serif(17)))
        }
        write("03 Real Pages.rtf", pages)
        func head(_ t: String) -> NSAttributedString { r("\(t)\n", serif(19, true), green) }
        write("04 Tools You'll Love.rtf", [
            r("Tools You'll Love\n\n", serif(28, true), green),
            head("Name generator"),
            r("Stuck on a character's name? Tools → Name Generator spins up gender-matched first names with surnames from real, per-country databases.\n\n", serif(17)),
            head("Version history"),
            r("Penwick quietly snapshots your drafts as you write. Open Version History to read — or restore — any earlier version.\n\n", serif(17)),
            head("Export anywhere"),
            r("Export to PDF, Word (.docx), Markdown, plain text, or Fountain for screenplays — ready for editors, agents, or print.\n\n", serif(17)),
            head("Write together"),
            r("Share a project through iCloud and write with someone else. You'll see who's here and their edits sync in.\n", serif(17)),
        ])
        write("05 Sharing, Safety & Updates.rtf", [
            r("Sharing, Safety & Updates\n\n", serif(26, true), ink, .center),
            r("Penwick keeps itself up to date — new versions install straight from the web, so you never hunt for a download.\n\n", serif(17)),
            r("Is it safe? Yes.", serif(17, true), blue),
            r(" The app isn't code-signed only because that costs $99 a year — not because anything's wrong. Penwick is fully open source, so anyone can read every line. Your writing lives in your own iCloud Drive as plain .rtf files. No tracking, no accounts, no servers.\n\n", serif(17)),
            r("Now — clear out this sample and write something only you could write.\n", serifI(17), warm, .center),
        ])
        write("06 Personal Touches.rtf", [
            r("Personal Touches\n\n", serif(28, true), warm),
            head("Give it an emoji"),
            r("See the little icons next to the chapters in the sidebar? Right-click any ", serif(17)),
            r("chapter — or the manuscript title itself", serif(17, true), blue),
            r(" — and choose ", serif(17)),
            r("Set Emoji…", serif(17, true)),
            r(" to tag it. Pick one that captures the mood; it shows up right beside the name.\n\n", serif(17)),
            head("Bring in old writing"),
            r("Already started somewhere else? Just ", serif(17)),
            r("drag a file onto Penwick", serif(17, true), blue),
            r(" — Markdown (.md), plain text (.txt), Word (.docx), RTF, or Fountain. Penwick asks whether to drop it in as a ", serif(17)),
            r("new chapter", serif(17, true)),
            r(" or add it to the ", serif(17)),
            r("chapter you're in", serif(17, true)),
            r(". Your old drafts, home in one place.\n", serif(17)),
        ])

        // Default emoji tags — also demonstrates the feature.
        let tags = ["__project__": "📖",
                    "01 Welcome to Penwick.rtf": "👋",
                    "02 Writing & Formatting.rtf": "✍️",
                    "03 Real Pages.rtf": "📄",
                    "04 Tools You'll Love.rtf": "🧰",
                    "05 Sharing, Safety & Updates.rtf": "🔒",
                    "06 Personal Touches.rtf": "🎨"]
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent(".penwick", isDirectory: true), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: tags) {
            try? data.write(to: dir.appendingPathComponent(".penwick/emoji.json"))
        }
    }

    @discardableResult
    func newProject(named name: String, silent: Bool = false) -> Project {
        var folder = root.appendingPathComponent(name, isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = root.appendingPathComponent("\(name) \(n)", isDirectory: true); n += 1
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let proj = Project(url: folder, chapters: [])
        if !silent { reload(); if let first = newChapterURL(in: proj, seed: false) { selection = first }; reload() }
        return proj
    }

    @discardableResult
    func newChapter(in project: Project, seed: Bool = false) -> URL? {
        let url = newChapterURL(in: project, seed: seed)
        reload()
        if let url { selection = url }
        return url
    }

    private func newChapterURL(in project: Project, seed: Bool) -> URL? {
        let existing = (try? FileManager.default.contentsOfDirectory(at: project.url, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "rtf" } ?? []
        var count = existing.count + 1
        var url = project.url.appendingPathComponent(String(format: "%02d Chapter.rtf", count))
        while FileManager.default.fileExists(atPath: url.path) {   // avoid clobbering after a mid-list delete
            count += 1
            url = project.url.appendingPathComponent(String(format: "%02d Chapter.rtf", count))
        }
        let str = seed
            ? "Welcome to Penwick\n\nThis is your manuscript. The sidebar is your binder: each book or script is a Project, and inside it you write chapter by chapter (or scene by scene). Add chapters with the + on a project, and watch your word count climb toward your goal.\n\nEverything is a real .rtf file in iCloud Drive, synced to all your devices.\n"
            : "\n"
        let attr = NSMutableAttributedString(string: str, attributes: [.font: bodyNSFont(), .foregroundColor: NSColor.labelColor])
        if seed {
            let h = NSRange(location: 0, length: 18)
            attr.addAttribute(.font, value: bodyNSFont(size: 28), range: h)
            attr.applyFontTraits(.boldFontMask, range: h)
        }
        if let data = attr.rtf(from: NSRange(location: 0, length: attr.length), documentAttributes: [:]) {
            try? data.write(to: url); return url
        }
        return nil
    }

    func rename(project: Project, to newName: String) {
        let clean = newName.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        let dest = root.appendingPathComponent(clean, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
        let keepSelected = selection
        flushAndCancelSaves()
        let oldGoal = goal(for: project)
        try? FileManager.default.moveItem(at: project.url, to: dest)
        if oldGoal > 0 {
            UserDefaults.standard.set(oldGoal, forKey: "goal:" + clean)
            UserDefaults.standard.removeObject(forKey: "goal:" + project.name)
        }
        reload()
        // Re-point selection if the renamed project held it.
        if let sel = keepSelected, sel.path.hasPrefix(project.url.path) {
            selection = dest.appendingPathComponent(sel.lastPathComponent)
        }
    }

    // Reordering — chapters are ordered by a numeric filename prefix, so moving
    // one rewrites the prefixes of the whole project.
    func moveChapter(_ url: URL, in project: Project, up: Bool) {
        guard let p = projects.first(where: { $0.url == project.url }),
              let i = p.chapters.firstIndex(where: { $0.url == url }) else { return }
        let j = up ? i - 1 : i + 1
        guard j >= 0 && j < p.chapters.count else { return }
        var chapters = p.chapters
        chapters.swapAt(i, j)
        renumber(chapters, in: p, keepSelected: url)
    }

    func reorder(in project: Project, from offsets: IndexSet, to dest: Int) {
        guard let p = projects.first(where: { $0.url == project.url }) else { return }
        var chapters = p.chapters
        let sel = selection
        chapters.move(fromOffsets: offsets, toOffset: dest)
        renumber(chapters, in: p, keepSelected: sel)
    }

    // Write any pending in-memory edits to their current files and cancel timers,
    // so a delayed save can't resurrect/clobber a file after we move or delete it.
    private func flushAndCancelSaves() {
        for (u, t) in saveTimers {
            t.invalidate()
            if let ch = chapter(u) { save(url: u, text: ch.text) }
        }
        saveTimers.removeAll()
    }

    private func renumber(_ ordered: [Chapter], in project: Project, keepSelected: URL?) {
        flushAndCancelSaves()
        let fm = FileManager.default
        let selIndex = keepSelected.flatMap { sel in ordered.firstIndex(where: { $0.url == sel }) }
        // Two-pass rename via temp names to avoid collisions while swapping.
        var temps: [URL] = []
        for (idx, ch) in ordered.enumerated() {
            let tmp = project.url.appendingPathComponent(".tmp-\(idx).rtf")
            try? fm.removeItem(at: tmp)
            try? fm.moveItem(at: ch.url, to: tmp)
            temps.append(tmp)
        }
        for (idx, tmp) in temps.enumerated() {
            let final = project.url.appendingPathComponent(String(format: "%02d Chapter.rtf", idx + 1))
            try? fm.moveItem(at: tmp, to: final)
        }
        reload()
        if let si = selIndex {
            selection = project.url.appendingPathComponent(String(format: "%02d Chapter.rtf", si + 1))
        }
    }

    func update(url: URL, text: NSAttributedString) {
        for i in projects.indices {
            if let j = projects[i].chapters.firstIndex(where: { $0.url == url }) {
                projects[i].chapters[j].text = text
                projects[i].chapters[j].modified = Date()
                scheduleSave(url: url, text: text)
                return
            }
        }
    }

    private func scheduleSave(url: URL, text: NSAttributedString) {
        saveTimers[url]?.invalidate()
        saveTimers[url] = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.save(url: url, text: text) }
        }
    }
    func save(url: URL, text: NSAttributedString) {
        let full = NSRange(location: 0, length: text.length)
        // If the chapter has images, persist as flattened RTFD (RTF drops attachments).
        let data: Data? = text.containsAttachments(in: full)
            ? text.rtfd(from: full, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
            : text.rtf(from: full, documentAttributes: [:])
        if let data = data {
            try? data.write(to: url)
            lastSignature = folderSignature()   // our own write isn't an "external" change
            snapshotIfNeeded(url: url, text: text)
        }
    }

    // MARK: Version history (auto snapshots kept in <project>/.penwick/history)
    private var lastSnapshot: [URL: Date] = [:]
    private func historyDir(for chapter: URL) -> URL {
        chapter.deletingLastPathComponent().appendingPathComponent(".penwick/history", isDirectory: true)
    }
    func snapshotIfNeeded(url: URL, text: NSAttributedString) {
        if Date().timeIntervalSince(lastSnapshot[url] ?? .distantPast) > 300 { saveSnapshot(url: url, text: text) }
    }
    func saveSnapshot(url: URL, text: NSAttributedString) {
        guard text.length > 0 else { return }
        let dir = historyDir(for: url)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = url.deletingPathExtension().lastPathComponent
        let stamp = Int(Date().timeIntervalSince1970)
        if let data = text.rtf(from: NSRange(location: 0, length: text.length), documentAttributes: [:]) {
            try? data.write(to: dir.appendingPathComponent("\(base)__\(stamp).rtf"))
            lastSnapshot[url] = Date()
        }
        pruneHistory(url: url)
    }
    private func pruneHistory(url: URL, keep: Int = 40) {
        let v = versions(for: url)
        if v.count > keep { for item in v.suffix(v.count - keep) { try? FileManager.default.removeItem(at: item.url) } }
    }
    func versions(for url: URL) -> [(date: Date, url: URL)] {
        let base = url.deletingPathExtension().lastPathComponent
        let files = (try? FileManager.default.contentsOfDirectory(at: historyDir(for: url), includingPropertiesForKeys: nil)) ?? []
        var result: [(Date, URL)] = []
        for f in files where f.pathExtension == "rtf" && f.lastPathComponent.hasPrefix(base + "__") {
            let s = f.deletingPathExtension().lastPathComponent.replacingOccurrences(of: base + "__", with: "")
            if let t = Double(s) { result.append((Date(timeIntervalSince1970: t), f)) }
        }
        return result.sorted { $0.0 > $1.0 }
    }
    func restore(snapshot: URL, into chapter: URL) {
        guard let data = try? Data(contentsOf: snapshot),
              let attr = NSAttributedString(rtf: data, documentAttributes: nil) else { return }
        saveSnapshot(url: chapter, text: attributed(for: chapter))   // back up current first
        save(url: chapter, text: attr)
        if let i = projects.firstIndex(where: { $0.chapters.contains { $0.url == chapter } }),
           let j = projects[i].chapters.firstIndex(where: { $0.url == chapter }) {
            projects[i].chapters[j].text = attr
        }
        let keep = chapter
        selection = nil
        DispatchQueue.main.async { self.selection = keep }   // force the editor to reload the restored text
    }

    func deleteChapter(_ url: URL) {
        saveTimers[url]?.invalidate(); saveTimers[url] = nil
        try? FileManager.default.removeItem(at: url)
        reload()
        if selection == url { selection = projects.flatMap { $0.chapters }.first?.url }
    }
    func deleteProject(_ project: Project) {
        for (u, t) in saveTimers where u.path.hasPrefix(project.url.path) { t.invalidate(); saveTimers[u] = nil }
        try? FileManager.default.removeItem(at: project.url)
        reload()
        if let sel = selection, sel.path.hasPrefix(project.url.path) {
            selection = projects.flatMap { $0.chapters }.first?.url
        }
    }

    // Word goals (per project)
    func goal(for project: Project) -> Int { UserDefaults.standard.integer(forKey: "goal:" + project.name) }
    func setGoal(_ n: Int, for project: Project) { UserDefaults.standard.set(n, forKey: "goal:" + project.name) }

    func revealInFinder(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func revealRoot() { NSWorkspace.shared.activateFileViewerSelecting([root]) }
}

// MARK: - Screenplay elements

enum ScriptElement: CaseIterable {
    case scene, action, character, dialogue, paren, transition
    var label: String {
        switch self {
        case .scene: return "Scene Heading"; case .action: return "Action"; case .character: return "Character"
        case .dialogue: return "Dialogue"; case .paren: return "Parenthetical"; case .transition: return "Transition"
        }
    }
    var bold: Bool { self == .scene }
    func paragraphStyle() -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 2
        p.paragraphSpacing = (self == .scene) ? 14 : 4
        switch self {
        case .scene, .action: break
        case .character: p.firstLineHeadIndent = 200; p.headIndent = 200
        case .paren:     p.firstLineHeadIndent = 150; p.headIndent = 150; p.tailIndent = -90
        case .dialogue:  p.firstLineHeadIndent = 100; p.headIndent = 100; p.tailIndent = -90
        case .transition: p.alignment = .right
        }
        return p
    }
    // After pressing Return on this element, the next line becomes…
    var afterReturn: ScriptElement {
        switch self {
        case .scene: return .action
        case .character: return .dialogue
        case .paren: return .dialogue
        case .dialogue: return .action
        case .transition: return .scene
        case .action: return .action
        }
    }
}

func scriptFont(bold: Bool) -> NSFont {
    let base = NSFont(name: "Courier New", size: 13) ?? NSFont(name: "Courier", size: 13) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    return bold ? NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask) : base
}

// MARK: - Editor controller

enum ListKind { case none, bullet, numbered, checklist }

struct AIMessage: Identifiable, Equatable { let id = UUID(); let role: String; let text: String }   // role: "you" / "ai"

@MainActor
final class EditorController: ObservableObject {
    @Published var aiMessages: [AIMessage] = []   // kept here so the chat survives closing the panel
    weak var textView: NSTextView?
    @Published var selFamily: String? = "New York"   // nil = mixed across selection
    @Published var selSize: CGFloat? = 17
    @Published var selBold = false
    @Published var selItalic = false
    @Published var selUnderline = false
    @Published var selStrike = false
    @Published var selAlign: NSTextAlignment? = .natural   // nil = mixed
    @Published var scriptElementLabel = "Action"
    @Published var selColor: Color = .primary
    @Published var selList: ListKind = .none

    // Reflect what's actually under the selection (or the caret) in the toolbar.
    func refreshSelection() {
        guard let tv = textView else { return }
        let r = tv.selectedRange()
        let fm = NSFontManager.shared
        var fam: String?; var size: CGFloat?
        var bold = false, italic = false, underline = false, strike = false
        var align: NSTextAlignment? = .natural

        if r.length == 0 {
            let f = (tv.typingAttributes[.font] as? NSFont) ?? bodyNSFont()
            fam = f.familyName; size = f.pointSize
            let tr = fm.traits(of: f); bold = tr.contains(.boldFontMask); italic = tr.contains(.italicFontMask)
            underline = (tv.typingAttributes[.underlineStyle] as? Int ?? 0) != 0
            strike = (tv.typingAttributes[.strikethroughStyle] as? Int ?? 0) != 0
            align = (tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.alignment ?? .natural
        } else if let storage = tv.textStorage {
            var families = Set<String>(); var sizes = Set<CGFloat>(); var aligns = Set<NSTextAlignment>()
            var allBold = true, allItalic = true, allU = true, allS = true, any = false
            storage.enumerateAttribute(.font, in: r, options: []) { v, _, _ in
                any = true
                let f = (v as? NSFont) ?? bodyNSFont()
                families.insert(f.familyName ?? ""); sizes.insert(f.pointSize.rounded())
                let tr = fm.traits(of: f)
                if !tr.contains(.boldFontMask) { allBold = false }
                if !tr.contains(.italicFontMask) { allItalic = false }
            }
            storage.enumerateAttribute(.paragraphStyle, in: r, options: []) { v, _, _ in
                aligns.insert((v as? NSParagraphStyle)?.alignment ?? .natural)
            }
            storage.enumerateAttribute(.underlineStyle, in: r, options: []) { v, _, _ in if (v as? Int ?? 0) == 0 { allU = false } }
            storage.enumerateAttribute(.strikethroughStyle, in: r, options: []) { v, _, _ in if (v as? Int ?? 0) == 0 { allS = false } }
            fam = families.count == 1 ? families.first : nil
            size = sizes.count == 1 ? sizes.first : nil
            align = aligns.count == 1 ? aligns.first : nil
            bold = any && allBold; italic = any && allItalic; underline = any && allU; strike = any && allS
        }

        // Only publish what actually changed — avoids re-rendering (and dropping clicks)
        // on every caret move while typing.
        if selFamily != fam { selFamily = fam }
        if selSize != size { selSize = size }
        if selBold != bold { selBold = bold }
        if selItalic != italic { selItalic = italic }
        if selUnderline != underline { selUnderline = underline }
        if selStrike != strike { selStrike = strike }
        if selAlign != align { selAlign = align }
        let lk = currentListKind()
        if selList != lk { selList = lk }
        let el = currentScriptElement().label
        if scriptElementLabel != el { scriptElementLabel = el }
        // current foreground colour (for the colour well)
        let fgNS: NSColor
        if r.length == 0 {
            fgNS = (tv.typingAttributes[.foregroundColor] as? NSColor) ?? .labelColor
        } else if let storage = tv.textStorage {
            fgNS = (storage.attribute(.foregroundColor, at: r.location, effectiveRange: nil) as? NSColor) ?? .labelColor
        } else { fgNS = .labelColor }
        let fg = Color(nsColor: fgNS)
        if selColor != fg { selColor = fg }
    }

    // --- Undoable document mutations ----------------------------------------
    // The formal AppKit method: bracket every change between shouldChangeText(...)
    // and didChangeText(). NSTextView then registers undo in its OWN native undo
    // manager — the same one that records typing — so ⌘Z reverts text AND
    // formatting (bold, colour, font, size, alignment, lists) in the right order.
    // Refs: Apple "Using Undo in AppKit", Christian Tietze "Undoable text changes".
    private func attrEdit(_ range: NSRange, _ change: (NSTextStorage) -> Void) {
        guard let tv = textView, let storage = tv.textStorage, range.length > 0 else { return }
        guard tv.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing(); change(storage); storage.endEditing()
        tv.didChangeText()
        refreshSelection()
    }

    private func textEdit(_ range: NSRange, replacement: NSAttributedString) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        guard tv.shouldChangeText(in: range, replacementString: replacement.string) else { return }
        storage.replaceCharacters(in: range, with: replacement)
        tv.didChangeText()
        refreshSelection()
    }

    private func mutateFonts(_ transform: @escaping (NSFont) -> NSFont) {
        guard let tv = textView else { return }
        let sel = tv.selectedRange()
        if sel.length == 0 {
            // No selection → only affect text typed next (NOT the whole document).
            let cur = (tv.typingAttributes[.font] as? NSFont) ?? bodyNSFont()
            tv.typingAttributes[.font] = transform(cur)
            refreshSelection()
            return
        }
        attrEdit(sel) { storage in
            storage.enumerateAttribute(.font, in: sel, options: []) { v, sub, _ in
                let f = (v as? NSFont) ?? bodyNSFont()
                storage.addAttribute(.font, value: transform(f), range: sub)
            }
        }
        // Carry the change into typingAttributes so that if the text is then
        // deleted, the next characters typed keep the font you just chose.
        let cur = (tv.typingAttributes[.font] as? NSFont) ?? bodyNSFont()
        tv.typingAttributes[.font] = transform(cur)
    }

    // Append imported content to the end of the open chapter (undoable, live).
    func appendAtEnd(_ attr: NSAttributedString) {
        guard let tv = textView, let st = tv.textStorage else { return }
        let ins = NSMutableAttributedString(string: "\n\n", attributes: [.font: bodyNSFont(), .foregroundColor: NSColor(white: 0.12, alpha: 1), .paragraphStyle: defaultParagraphStyle()])
        ins.append(attr)
        let end = NSRange(location: st.length, length: 0)
        if tv.shouldChangeText(in: end, replacementString: ins.string) {
            st.replaceCharacters(in: end, with: ins); tv.didChangeText()
            tv.setSelectedRange(NSRange(location: st.length, length: 0))
            tv.scrollRangeToVisible(NSRange(location: st.length, length: 0))
        }
    }

    // Replace a range with new text, keeping the original formatting (font/colour) — used by AI edits.
    // Read the formatting of a range's first character (captured when an AI edit is requested).
    func attributesAt(_ loc: Int) -> [NSAttributedString.Key: Any] {
        guard let st = textView?.textStorage, st.length > 0 else {
            return [.font: bodyNSFont(), .foregroundColor: NSColor(white: 0.12, alpha: 1), .paragraphStyle: defaultParagraphStyle()]
        }
        return st.attributes(at: min(max(0, loc), st.length - 1), effectiveRange: nil)
    }

    func applyEdit(range: NSRange, text: String, keeping attrs: [NSAttributedString.Key: Any]? = nil) {
        guard let tv = textView, let st = tv.textStorage, NSMaxRange(range) <= st.length else { return }
        var a = attrs ?? attributesAt(range.location)
        if a[.font] == nil { a[.font] = bodyNSFont() }                                   // never lose the font
        if a[.foregroundColor] == nil { a[.foregroundColor] = NSColor(white: 0.12, alpha: 1) }
        if a[.paragraphStyle] == nil { a[.paragraphStyle] = defaultParagraphStyle() }
        let repl = NSAttributedString(string: text, attributes: a)
        if tv.shouldChangeText(in: range, replacementString: text) {
            st.replaceCharacters(in: range, with: repl); tv.didChangeText()
            tv.setSelectedRange(NSRange(location: range.location, length: (text as NSString).length))
        }
    }

    // Jump to / select a range (used by the comments panel).
    func goTo(range: NSRange) {
        guard let tv = textView, NSMaxRange(range) <= (tv.string as NSString).length else { return }
        tv.window?.makeFirstResponder(tv)
        tv.setSelectedRange(range)
        tv.scrollRangeToVisible(range)
    }

    // Insert an image at the caret, scaled to fit the page width. Persists via RTFD.
    func insertImage(_ image: NSImage) {
        guard let tv = textView, let st = tv.textStorage else { return }
        let maxW = RichTextEditor.pageW - 2 * RichTextEditor.margin   // page content width
        let maxH = RichTextEditor.pageH - 2 * RichTextEditor.margin   // page content height
        var size = image.size
        if size.width > 0, size.height > 0 {
            let scale = min(1, min(maxW / size.width, maxH / size.height))   // fit the page, never crop
            size = NSSize(width: size.width * scale, height: size.height * scale)
        }
        let att = NSTextAttachment()
        if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            let fw = FileWrapper(regularFileWithContents: png); fw.preferredFilename = "image.png"
            att.fileWrapper = fw   // ensures the image survives RTFD save/load
        }
        att.image = image
        att.bounds = NSRect(origin: .zero, size: size)
        let ins = NSMutableAttributedString(string: "\n")
        ins.append(NSAttributedString(attachment: att))
        ins.append(NSAttributedString(string: "\n"))
        let caret = tv.selectedRange()
        if tv.shouldChangeText(in: caret, replacementString: ins.string) {
            st.replaceCharacters(in: caret, with: ins); tv.didChangeText()
            tv.setSelectedRange(NSRange(location: caret.location + ins.length, length: 0))
        }
    }

    // The font that the next keystroke / selection currently uses.
    private func currentFont() -> NSFont {
        guard let tv = textView else { return bodyNSFont() }
        if tv.selectedRange().length > 0, let s = tv.textStorage,
           let f = s.attribute(.font, at: tv.selectedRange().location, effectiveRange: nil) as? NSFont { return f }
        return (tv.typingAttributes[.font] as? NSFont) ?? bodyNSFont()
    }

    func toggleTrait(_ trait: NSFontTraitMask) {
        let fm = NSFontManager.shared
        let on = !fm.traits(of: currentFont()).contains(trait)
        mutateFonts { f in on ? fm.convert(f, toHaveTrait: trait) : fm.convert(f, toNotHaveTrait: trait) }
    }
    func toggleBold()   { toggleTrait(.boldFontMask) }
    func toggleItalic() { toggleTrait(.italicFontMask) }

    func toggleUnderline() { toggleLineAttr(.underlineStyle) }
    func toggleStrike()    { toggleLineAttr(.strikethroughStyle) }
    private func toggleLineAttr(_ key: NSAttributedString.Key) {
        guard let tv = textView, let s = tv.textStorage else { return }
        let r = tv.selectedRange()
        if r.length == 0 {
            let on = (tv.typingAttributes[key] as? Int ?? 0) != 0
            tv.typingAttributes[key] = on ? 0 : NSUnderlineStyle.single.rawValue
            refreshSelection(); return
        }
        let on = (s.attribute(key, at: r.location, effectiveRange: nil) as? Int ?? 0) != 0
        let newVal = on ? 0 : NSUnderlineStyle.single.rawValue
        attrEdit(r) { $0.addAttribute(key, value: newVal, range: r) }
        tv.typingAttributes[key] = newVal   // keep it for typing after a delete-all
    }

    func setHeading(size: CGFloat) {
        let fm = NSFontManager.shared
        mutateFonts { f in
            let sized = fm.convert(f, toSize: size)
            return size > 17 ? fm.convert(sized, toHaveTrait: .boldFontMask) : fm.convert(sized, toNotHaveTrait: .boldFontMask)
        }
    }
    func setFamily(_ family: FontFamily) { setFamilyName(bodyNSFont(family).familyName ?? "Helvetica") }
    func setFamilyName(_ name: String) { mutateFonts { f in NSFontManager.shared.convert(f, toFamily: name) } }
    func setSize(_ size: CGFloat) { mutateFonts { f in NSFontManager.shared.convert(f, toSize: size) } }

    func setColor(_ color: NSColor) {
        guard let tv = textView, let s = tv.textStorage else { return }
        let r = tv.selectedRange()
        if r.length == 0 { tv.typingAttributes[.foregroundColor] = color; refreshSelection(); return }
        attrEdit(r) { $0.addAttribute(.foregroundColor, value: color, range: r) }
        tv.typingAttributes[.foregroundColor] = color   // keep it for typing after a delete-all
    }
    func setAlignment(_ a: NSTextAlignment) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        // Update typing attributes so an empty line moves the caret and future text aligns.
        let ps = (tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle)
            .flatMap { $0.mutableCopy() as? NSMutableParagraphStyle } ?? defaultParagraphStyle()
        ps.alignment = a
        tv.typingAttributes[.paragraphStyle] = ps
        let para = (storage.string as NSString).paragraphRange(for: tv.selectedRange())
        if para.length > 0 {
            attrEdit(para) { s in
                s.enumerateAttribute(.paragraphStyle, in: para, options: []) { v, sub, _ in
                    let p = ((v as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? defaultParagraphStyle()
                    p.alignment = a
                    s.addAttribute(.paragraphStyle, value: p, range: sub)
                }
            }
        } else { refreshSelection() }
    }

    func insert(_ s: String) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let attr = NSAttributedString(string: s, attributes: [.font: bodyNSFont(), .foregroundColor: NSColor.labelColor])
        let loc = min(tv.selectedRange().location, storage.length)
        textEdit(NSRange(location: loc, length: 0), replacement: attr)
        tv.setSelectedRange(NSRange(location: loc + attr.length, length: 0))
    }

    // MARK: Screenplay (script mode)
    private func scriptAttrs(_ e: ScriptElement) -> [NSAttributedString.Key: Any] {
        [.font: scriptFont(bold: e.bold), .foregroundColor: NSColor.labelColor, .paragraphStyle: e.paragraphStyle()]
    }
    func currentScriptElement() -> ScriptElement {
        guard let tv = textView, let s = tv.textStorage, s.length > 0 else { return .action }
        let pr = (s.string as NSString).paragraphRange(for: tv.selectedRange())
        let loc = max(0, min(pr.location, s.length - 1))
        let ps = s.attribute(.paragraphStyle, at: loc, effectiveRange: nil) as? NSParagraphStyle
        let f = s.attribute(.font, at: loc, effectiveRange: nil) as? NSFont
        let bold = f.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false
        if (ps?.alignment ?? .natural) == .right { return .transition }
        if bold { return .scene }
        let indent = ps?.firstLineHeadIndent ?? 0
        if indent >= 190 { return .character }
        if indent >= 140 { return .paren }
        if indent >= 90 { return .dialogue }
        return .action
    }
    func setScriptElement(_ e: ScriptElement) {
        guard let tv = textView, let s = tv.textStorage else { return }
        let pr = (s.string as NSString).paragraphRange(for: tv.selectedRange())
        let a = scriptAttrs(e)
        if pr.length > 0, tv.shouldChangeText(in: pr, replacementString: nil) {
            s.beginEditing(); s.addAttributes(a, range: pr); s.endEditing(); tv.didChangeText()
        }
        tv.typingAttributes = a   // continued typing keeps this element
        refreshSelection()
    }
    func cycleScriptElement(forward: Bool = true) {
        let all = ScriptElement.allCases
        let i = all.firstIndex(of: currentScriptElement()) ?? all.firstIndex(of: .action)!
        setScriptElement(all[(i + (forward ? 1 : all.count - 1)) % all.count])
    }
    func scriptReturnElement() -> ScriptElement { currentScriptElement().afterReturn }
    func enterScriptMode() {
        guard let tv = textView, let s = tv.textStorage else { return }
        let full = NSRange(location: 0, length: s.length)
        if full.length > 0, tv.shouldChangeText(in: full, replacementString: nil) {
            s.beginEditing(); s.addAttributes(scriptAttrs(.action), range: full); s.endEditing(); tv.didChangeText()
        }
        tv.typingAttributes = scriptAttrs(.action)
        refreshSelection()
    }

    // Which list (if any) the caret's line is in — drives the toolbar's on/off state.
    func currentListKind() -> ListKind {
        guard let tv = textView, let st = tv.textStorage else { return .none }
        let ns = st.string as NSString
        guard ns.length > 0 else { return .none }
        let lr = ns.lineRange(for: NSRange(location: min(tv.selectedRange().location, ns.length - 1), length: 0))
        let line = ns.substring(with: lr)
        if line.hasPrefix("•  ") { return .bullet }
        if line.hasPrefix("☐  ") || line.hasPrefix("☑  ") { return .checklist }
        if line.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil { return .numbered }
        return .none
    }
    // Strip any list markers from the selected paragraphs (toggle off).
    private func removeListMarkers() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let ns = storage.string as NSString
        let para = ns.paragraphRange(for: tv.selectedRange())
        let block = ns.substring(with: para)
        let endsWithNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if endsWithNewline { lines.removeLast() }
        let rebuilt = lines.map { strip($0) }
        var joined = rebuilt.joined(separator: "\n"); if endsWithNewline { joined += "\n" }
        let attrs: [NSAttributedString.Key: Any] = [.font: bodyNSFont(), .foregroundColor: NSColor(white: 0.12, alpha: 1), .paragraphStyle: defaultParagraphStyle()]
        textEdit(para, replacement: NSAttributedString(string: joined, attributes: attrs))
        tv.setSelectedRange(NSRange(location: para.location, length: 0))
        refreshSelection()
    }

    func list(numbered: Bool) {
        if currentListKind() == (numbered ? .numbered : .bullet) { removeListMarkers(); return }
        guard let tv = textView, let storage = tv.textStorage else { return }
        let ns = storage.string as NSString
        let para = ns.paragraphRange(for: tv.selectedRange())
        let block = ns.substring(with: para)
        let endsWithNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if endsWithNewline { lines.removeLast() }      // drop empty element after final \n
        if lines.isEmpty { lines = [""] }              // caret on an empty line → still start a list item

        // Every line gets a marker, even empty ones, so a list starts on a blank line.
        let rebuilt = lines.enumerated().map { (i, line) -> String in
            (numbered ? "\(i + 1).  " : "•  ") + strip(line)
        }
        var joined = rebuilt.joined(separator: "\n"); if endsWithNewline { joined += "\n" }

        let style = NSMutableParagraphStyle(); style.headIndent = 22; style.paragraphSpacing = 2
        let attrs: [NSAttributedString.Key: Any] = [.font: bodyNSFont(), .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
        textEdit(para, replacement: NSAttributedString(string: joined, attributes: attrs))

        // Put the caret right after the first marker so the user can type immediately.
        let firstLen = (rebuilt.first.map { $0 as NSString })?.length ?? 0
        tv.setSelectedRange(NSRange(location: para.location + firstLen, length: 0))
    }
    // Checklist: prefix each selected line with an empty checkbox (click it to tick).
    func checklist() {
        if currentListKind() == .checklist { removeListMarkers(); return }
        guard let tv = textView, let storage = tv.textStorage else { return }
        let ns = storage.string as NSString
        let para = ns.paragraphRange(for: tv.selectedRange())
        let block = ns.substring(with: para)
        let endsWithNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if endsWithNewline { lines.removeLast() }
        if lines.isEmpty { lines = [""] }
        let rebuilt = lines.map { "☐  " + strip($0) }
        var joined = rebuilt.joined(separator: "\n"); if endsWithNewline { joined += "\n" }
        let style = NSMutableParagraphStyle(); style.headIndent = 22; style.paragraphSpacing = 2
        let attrs: [NSAttributedString.Key: Any] = [.font: bodyNSFont(), .foregroundColor: NSColor(white: 0.12, alpha: 1), .paragraphStyle: style]
        textEdit(para, replacement: NSAttributedString(string: joined, attributes: attrs))
        let firstLen = (rebuilt.first.map { $0 as NSString })?.length ?? 0
        tv.setSelectedRange(NSRange(location: para.location + firstLen, length: 0))
    }
    private func strip(_ line: String) -> String {
        var t = line
        if let r = t.range(of: #"^\s*[☐☑]\s+"#, options: .regularExpression) { t.removeSubrange(r); return t }
        if let r = t.range(of: #"^\s*•\s+"#, options: .regularExpression) { t.removeSubrange(r); return t }
        if let r = t.range(of: #"^\s*\d+\.\s+"#, options: .regularExpression) { t.removeSubrange(r); return t }
        return t
    }
}

// MARK: - Rich text editor

// A single page's text view. Paste matches surrounding style; gaining focus makes
// it the controller's active text view (all pages share one text storage).
final class PageTextView: NSTextView {
    weak var controller: EditorController?
    override func paste(_ sender: Any?) {
        if (textStorage?.length ?? 0) == 0 { super.paste(sender) } else { pasteAsPlainText(sender) }
    }
    override func becomeFirstResponder() -> Bool {
        controller?.textView = self
        return super.becomeFirstResponder()
    }

    // ── Comment hover bubble — appears after ~0.25s and follows the cursor ──────
    var commentRanges: [(range: NSRange, text: String)] = []
    private var hoverTracking: NSTrackingArea?
    private var hoverTimer: Timer?
    private var bubbleWindow: NSWindow?
    private var bubbleText: String?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = hoverTracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t); hoverTracking = t
    }
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let pt = convert(event.locationInWindow, from: nil)
        guard let text = commentText(at: pt) else { hoverTimer?.invalidate(); hoverTimer = nil; hideBubble(); return }
        if bubbleWindow != nil {
            if text != bubbleText { hideBubble(); showBubble(text, at: event) } else { positionBubble(at: event) }
        } else {
            hoverTimer?.invalidate()
            hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
                self?.showBubble(text, at: event)
            }
        }
    }
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event); hoverTimer?.invalidate(); hoverTimer = nil; hideBubble()
    }
    private func commentText(at pt: NSPoint) -> String? {
        guard !commentRanges.isEmpty, let lm = layoutManager, let tc = textContainer, let st = textStorage, st.length > 0 else { return nil }
        let p = NSPoint(x: pt.x - textContainerOrigin.x, y: pt.y - textContainerOrigin.y)
        var frac: CGFloat = 0
        let gi = lm.glyphIndex(for: p, in: tc, fractionOfDistanceThroughGlyph: &frac)
        guard lm.boundingRect(forGlyphRange: NSRange(location: gi, length: 1), in: tc).contains(p) else { return nil }
        let ci = lm.characterIndexForGlyph(at: gi)
        return commentRanges.first { NSLocationInRange(ci, $0.range) }?.text
    }
    private func showBubble(_ text: String, at event: NSEvent) {
        guard let host = window else { return }
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12); label.textColor = .white; label.drawsBackground = false; label.isBezeled = false; label.isEditable = false
        label.preferredMaxLayoutWidth = 260
        let size = label.sizeThatFits(NSSize(width: 260, height: 400))
        let pad: CGFloat = 9
        let cv = NSView(frame: NSRect(x: 0, y: 0, width: size.width + pad * 2, height: size.height + pad * 2))
        cv.wantsLayer = true; cv.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.97).cgColor; cv.layer?.cornerRadius = 8
        label.frame = NSRect(x: pad, y: pad, width: size.width, height: size.height)
        cv.addSubview(label)
        let win = NSWindow(contentRect: cv.frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false; win.backgroundColor = .clear; win.level = .floating; win.ignoresMouseEvents = true; win.hasShadow = true
        win.contentView = cv
        host.addChildWindow(win, ordered: .above)
        bubbleWindow = win; bubbleText = text
        positionBubble(at: event)
    }
    private func positionBubble(at event: NSEvent) {
        guard let win = bubbleWindow, let host = window else { return }
        let screen = host.convertPoint(toScreen: event.locationInWindow)
        win.setFrameOrigin(NSPoint(x: screen.x + 14, y: screen.y - win.frame.height - 14))
    }
    private func hideBubble() {
        if let w = bubbleWindow { w.parent?.removeChildWindow(w); w.orderOut(nil) }
        bubbleWindow = nil; bubbleText = nil
    }

    // Click a checklist box (☐ / ☑) to tick it off.
    override func mouseDown(with event: NSEvent) {
        if toggleCheckboxIfHit(at: convert(event.locationInWindow, from: nil)) { return }
        super.mouseDown(with: event)
    }
    private func toggleCheckboxIfHit(at pt: NSPoint) -> Bool {
        guard let lm = layoutManager, let tc = textContainer, let st = textStorage, st.length > 0 else { return false }
        let p = NSPoint(x: pt.x - textContainerOrigin.x, y: pt.y - textContainerOrigin.y)
        var frac: CGFloat = 0
        let gi = lm.glyphIndex(for: p, in: tc, fractionOfDistanceThroughGlyph: &frac)
        let ci = lm.characterIndexForGlyph(at: gi)
        let ns = st.string as NSString
        let line = ns.lineRange(for: NSRange(location: min(ci, ns.length - 1), length: 0))
        guard line.length > 0 else { return false }
        let first = ns.substring(with: NSRange(location: line.location, length: 1))
        guard (first == "☐" || first == "☑"), ci <= line.location + 2 else { return false }   // clicked on/near the box
        let newChar = first == "☐" ? "☑" : "☐"
        let boxRange = NSRange(location: line.location, length: 1)
        guard shouldChangeText(in: boxRange, replacementString: newChar) else { return false }
        let attrs = st.attributes(at: line.location, effectiveRange: nil)
        st.replaceCharacters(in: boxRange, with: NSAttributedString(string: newChar, attributes: attrs))
        // Strike + dim the item text when checked.
        let hasNL = ns.substring(with: line).hasSuffix("\n")
        let textRange = NSRange(location: line.location, length: line.length - (hasNL ? 1 : 0))
        let checked = newChar == "☑"
        st.addAttribute(.strikethroughStyle, value: checked ? NSUnderlineStyle.single.rawValue : 0, range: textRange)
        st.addAttribute(.foregroundColor, value: checked ? NSColor(white: 0.55, alpha: 1) : NSColor(white: 0.12, alpha: 1), range: textRange)
        didChangeText()
        return true
    }

    // Right-click an image → resize options (no drag handles, but discoverable).
    private func attachmentInfo(at pt: NSPoint) -> (NSTextAttachment, NSRange)? {
        guard let lm = layoutManager, let tc = textContainer, let st = textStorage, st.length > 0 else { return nil }
        let p = NSPoint(x: pt.x - textContainerOrigin.x, y: pt.y - textContainerOrigin.y)
        var frac: CGFloat = 0
        let gi = lm.glyphIndex(for: p, in: tc, fractionOfDistanceThroughGlyph: &frac)
        let ci = lm.characterIndexForGlyph(at: gi)
        guard ci < st.length, let att = st.attribute(.attachment, at: ci, effectiveRange: nil) as? NSTextAttachment else { return nil }
        return (att, NSRange(location: ci, length: 1))
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let base = super.menu(for: event) ?? NSMenu()
        let pt = convert(event.locationInWindow, from: nil)
        guard let (_, range) = attachmentInfo(at: pt) else { return base }
        let sub = NSMenu()
        for (label, frac) in [("Small (⅓ page)", 0.33), ("Medium (½ page)", 0.5), ("Large (¾ page)", 0.75), ("Full width", 1.0)] {
            let it = NSMenuItem(title: label, action: #selector(resizeImage(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = ["loc": range.location, "frac": frac]
            sub.addItem(it)
        }
        let parent = NSMenuItem(title: "Resize Image", action: nil, keyEquivalent: "")
        parent.submenu = sub
        base.insertItem(parent, at: 0)
        base.insertItem(.separator(), at: 1)
        return base
    }
    @objc private func resizeImage(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let loc = info["loc"] as? Int, let frac = info["frac"] as? CGFloat,
              let st = textStorage, loc < st.length,
              let att = st.attribute(.attachment, at: loc, effectiveRange: nil) as? NSTextAttachment else { return }
        let img = att.image ?? (att.attachmentCell as? NSTextAttachmentCell)?.image
        let aspect = (img != nil && img!.size.width > 0) ? img!.size.height / img!.size.width : (att.bounds.height / max(att.bounds.width, 1))
        let maxW = RichTextEditor.pageW - 2 * RichTextEditor.margin
        let maxH = RichTextEditor.pageH - 2 * RichTextEditor.margin
        let w = maxW * frac
        let h = min(w * aspect, maxH)
        let range = NSRange(location: loc, length: 1)
        if shouldChangeText(in: range, replacementString: nil) {
            att.bounds = NSRect(x: 0, y: 0, width: w, height: h)
            st.edited(.editedAttributes, range: range, changeInLength: 0)
            didChangeText()
        }
    }

    // (Reverted the custom inked cursor at the user's request — back to the
    // standard system text cursor. The caret stays accent-blue via insertionPointColor.)
}

final class PagesDocView: NSView { override var isFlipped: Bool { true } }


extension NSColor {
    convenience init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                  blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "" }
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}

// Popover content for styling the page number (font + size + colour). Uses the
// same font menu as the main toolbar and writes to @AppStorage so it applies live.
struct PageNumberStyleView: View {
    @ObservedObject var store: PenwickStore
    private var fontName: String { store.pageNumberPrefs.fontName }
    private var size: Double { store.pageNumberPrefs.size }
    private var colorHex: String { store.pageNumberPrefs.colorHex }

    private let recommended = ["New York", "SF Pro", "Helvetica Neue", "Georgia", "Menlo"]
    private var systemFamilies: [String] { NSFontManager.shared.availableFontFamilies }

    private func setFont(_ n: String) { store.pageNumberPrefs.fontName = n; store.savePageNumberPrefs() }
    private func setSize(_ s: Double) { store.pageNumberPrefs.size = s; store.savePageNumberPrefs() }
    private func setColorHex(_ h: String) { store.pageNumberPrefs.colorHex = h; store.savePageNumberPrefs() }
    private var sizeBinding: Binding<Double> { Binding(get: { size }, set: { setSize($0) }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Page Number Style").font(.system(size: 13, weight: .semibold))

            HStack {
                Text("Font").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button { setFont("") } label: { Text("System") }
                    Divider()
                    Section("Recommended") {
                        ForEach(recommended, id: \.self) { name in
                            Button { setFont(name) } label: { Text(name).font(.custom(name, size: 13)) }
                        }
                    }
                    Divider()
                    Section("All fonts") {
                        ForEach(systemFamilies, id: \.self) { name in
                            Button { setFont(name) } label: { Text(name).font(.custom(name, size: 13)) }
                        }
                    }
                } label: {
                    Text(fontName.isEmpty ? "System" : fontName)
                        .font(fontName.isEmpty ? .system(size: 13) : .custom(fontName, size: 13))
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton).frame(width: 160)
            }

            HStack {
                Text("Size").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Menu("\(Int(size)) pt") {
                    ForEach([9, 10, 11, 12, 14, 16, 18, 24], id: \.self) { s in
                        Button("\(s) pt") { setSize(Double(s)) }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize()
                Stepper("", value: sizeBinding, in: 6...48, step: 1).labelsHidden()
            }

            HStack {
                Text("Colour").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { colorHex.isEmpty ? Color(white: 0.45) : Color(NSColor(hexString: colorHex) ?? .gray) },
                    set: { setColorHex(NSColor($0).hexString) }
                )).labelsHidden()
                Button("Default") { setColorHex("") }
                    .font(.system(size: 11)).buttonStyle(.borderless)
            }
        }
        .padding(16).frame(width: 280)
    }
}

// True paginated editor: one NSTextStorage + NSLayoutManager, one NSTextContainer
// (= one page sheet) per page; pages are added/removed as content flows.
struct RichTextEditor: NSViewRepresentable {
    let url: URL
    @ObservedObject var store: PenwickStore
    let controller: EditorController
    var showPageNumbers: Bool = false
    var numberFirstPage: Bool = true
    var pageNumberFont: String = ""
    var pageNumberSize: Double = 11
    var pageNumberColor: String = ""

    static let pageW: CGFloat = 612, pageH: CGFloat = 792, margin: CGFloat = 72, gap: CGFloat = 26

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let storage = NSTextStorage(attributedString: store.attributed(for: url))
        Coordinator.darkenInvisibleText(storage)   // pages are white; rescue near-white text
        Coordinator.normalizeSpacing(storage)       // tighten any old airy line spacing
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        c.textStorage = storage; c.layoutManager = lm

        let doc = PagesDocView()
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = doc
        c.docView = doc; c.scroll = scroll

        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(c, selector: #selector(Coordinator.viewResized),
                                               name: NSView.frameDidChangeNotification, object: scroll.contentView)

        c.ensurePages()
        c.applyCommentHighlights()
        DispatchQueue.main.async { c.controller.refreshSelection() }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let c = context.coordinator
        guard let st = c.textStorage else { return }
        let numChanged = (c.showNums != showPageNumbers) || (c.numberFirst != numberFirstPage)
            || (c.pnFont != pageNumberFont) || (c.pnSize != pageNumberSize) || (c.pnColor != pageNumberColor)
        c.showNums = showPageNumbers; c.numberFirst = numberFirstPage
        c.pnFont = pageNumberFont; c.pnSize = pageNumberSize; c.pnColor = pageNumberColor
        let latest = store.attributed(for: url)
        let editing = c.pageViews.contains { $0.window?.firstResponder === $0 }
        if !editing, latest.length > 0, !st.isEqual(to: latest) {
            st.setAttributedString(latest)
            Coordinator.darkenInvisibleText(st); Coordinator.normalizeSpacing(st)
            c.ensurePages()
        } else if numChanged {
            c.reposition()
        }
        c.applyCommentHighlights()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.debounce?.invalidate()
        NotificationCenter.default.removeObserver(coordinator)
        if let st = coordinator.textStorage {
            let snapshot = NSAttributedString(attributedString: st); let url = coordinator.parent.url
            Task { @MainActor in coordinator.parent.store.update(url: url, text: snapshot) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: RichTextEditor
        var textStorage: NSTextStorage!
        var layoutManager: NSLayoutManager!
        weak var docView: PagesDocView?
        weak var scroll: NSScrollView?
        var pageViews: [PageTextView] = []
        var sheetViews: [NSView] = []
        var numberLabels: [NSTextField] = []
        var debounce: Timer?
        var showNums = false
        var numberFirst = true
        var pnFont = ""
        var pnSize = 11.0
        var pnColor = ""
        var stylePopover: NSPopover?
        init(_ p: RichTextEditor) {
            parent = p; showNums = p.showPageNumbers; numberFirst = p.numberFirstPage
            pnFont = p.pageNumberFont; pnSize = p.pageNumberSize; pnColor = p.pageNumberColor
        }
        var controller: EditorController { parent.controller }

        @objc func viewResized() { reposition() }

        private func makePage() {
            let contentSize = NSSize(width: RichTextEditor.pageW - 2 * RichTextEditor.margin,
                                     height: RichTextEditor.pageH - 2 * RichTextEditor.margin)
            let container = NSTextContainer(size: contentSize)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            let tv = PageTextView(frame: .zero, textContainer: container)
            tv.controller = controller
            // The page is always white, so render text/caret/selection in light-mode
            // colours (labelColor etc. resolve dark) — even when the app is in dark mode.
            tv.appearance = NSAppearance(named: .aqua)
            tv.isRichText = true; tv.allowsUndo = true; tv.delegate = self
            tv.importsGraphics = false   // images removed (paste stays text-only)
            tv.isContinuousSpellCheckingEnabled = true; tv.isGrammarCheckingEnabled = true
            tv.isAutomaticSpellingCorrectionEnabled = false
            tv.isAutomaticQuoteSubstitutionEnabled = true; tv.isAutomaticDashSubstitutionEnabled = true
            tv.drawsBackground = false
            tv.isVerticallyResizable = false; tv.isHorizontallyResizable = false
            tv.textContainerInset = .zero
            tv.defaultParagraphStyle = defaultParagraphStyle()
            tv.typingAttributes = [.font: bodyNSFont(), .foregroundColor: Coordinator.pageTextColor, .paragraphStyle: defaultParagraphStyle()]
            tv.insertionPointColor = Coordinator.pageTextColor
            tv.selectedTextAttributes = [.backgroundColor: NSColor.selectedTextBackgroundColor]
            let sheet = NSView(); sheet.wantsLayer = true; sheet.layer?.cornerRadius = 12
            sheet.shadow = { let s = NSShadow(); s.shadowColor = NSColor.black.withAlphaComponent(0.18); s.shadowBlurRadius = 18; s.shadowOffset = NSSize(width: 0, height: -5); return s }()
            let label = NSTextField(labelWithString: "")
            label.font = .systemFont(ofSize: 11); label.textColor = NSColor(white: 0.45, alpha: 1)
            label.alignment = .center; label.isHidden = true
            // Click the page number to choose its font and size.
            let click = NSClickGestureRecognizer(target: self, action: #selector(editPageNumberStyle(_:)))
            label.addGestureRecognizer(click)
            sheetViews.append(sheet); pageViews.append(tv); numberLabels.append(label)
            docView?.addSubview(sheet); docView?.addSubview(tv); docView?.addSubview(label)
        }

        private func removeLastPage() {
            guard pageViews.count > 1 else { return }
            pageViews.removeLast().removeFromSuperview()
            sheetViews.removeLast().removeFromSuperview()
            numberLabels.removeLast().removeFromSuperview()
            if !layoutManager.textContainers.isEmpty {
                layoutManager.removeTextContainer(at: layoutManager.textContainers.count - 1)
            }
        }

        // ---- Pagination -------------------------------------------------------
        // One integer source of truth: pagesNeeded(). Measured on a SEPARATE
        // throwaway NSLayoutManager (fixed-height page-sized containers) attached to
        // the shared storage only inside the function and removed via defer — so the
        // DISPLAYED layout is never perturbed mid-measure, and grow/shrink read the
        // same count and cannot oscillate.
        private var contentSizeForPage: NSSize {
            NSSize(width: RichTextEditor.pageW - 2 * RichTextEditor.margin,
                   height: RichTextEditor.pageH - 2 * RichTextEditor.margin)
        }
        private var isReconciling = false           // reentrancy guard
        private var lastPageCount = -1
        private var lastLayoutWidth: CGFloat = -1

        private func pagesNeeded() -> Int {
            guard let storage = textStorage else { return 1 }
            let probe = NSLayoutManager()
            storage.addLayoutManager(probe)
            defer { storage.removeLayoutManager(probe) }

            func addContainer() {
                let c = NSTextContainer(size: contentSizeForPage)
                c.lineFragmentPadding = 0
                probe.addTextContainer(c)
            }
            addContainer()
            let total = probe.numberOfGlyphs          // forces glyph generation
            let str = storage.string as NSString
            let endsNewline = str.length > 0 && str.character(at: str.length - 1) == 0x0A
            let caretFont = (str.length > 0
                ? (storage.attribute(.font, at: str.length - 1, effectiveRange: nil) as? NSFont)
                : nil) ?? bodyNSFont()
            let lineHeight = probe.defaultLineHeight(for: caretFont) + 2   // + lineSpacing(2)

            var guardN = 0
            while guardN < 4000 {
                guardN += 1
                guard let last = probe.textContainers.last else { break }
                probe.ensureLayout(for: last)
                // (1) Unplaced glyphs → need another page.
                if probe.glyphRange(for: last).upperBound < total { addContainer(); continue }
                // (2) Everything placed — does the trailing caret line fit on `last`?
                var trailingFits = true
                if probe.extraLineFragmentTextContainer === last {
                    trailingFits = probe.extraLineFragmentRect.maxY <= last.size.height + 0.5
                } else if endsNewline && probe.glyphRange(for: last).length > 0 {
                    // Suppressed trailing line (the Enter-at-bottom bug): detect by geometry.
                    trailingFits = (probe.usedRect(for: last).maxY + lineHeight) <= last.size.height + 0.5
                }
                if trailingFits { break }
                addContainer()
            }
            return max(1, probe.textContainers.count)
        }

        func ensurePages() {
            guard !isReconciling else { return }
            isReconciling = true
            defer { isReconciling = false }

            if pageViews.isEmpty { makePage() }
            let needed = max(1, min(pagesNeeded(), 4000))
            if pageViews.count < needed {
                while pageViews.count < needed { makePage() }
                if let last = pageViews.last?.textContainer { layoutManager.ensureLayout(for: last) }
            } else if pageViews.count > needed {
                while pageViews.count > needed { removeLastPage() }
            }
            // Cheap keystroke path: skip relayout when nothing visible changed.
            let width = scroll?.contentView.bounds.width ?? RichTextEditor.pageW
            if pageViews.count == lastPageCount && abs(width - lastLayoutWidth) < 0.5 { return }
            lastPageCount = pageViews.count
            lastLayoutWidth = width
            reposition()
        }

        // Focus the page that hosts the caret after a programmatic edit that may have
        // changed the page count (used by list auto-continue so the caret never strands).
        @MainActor private func focusCaret(at caretIndex: Int) {
            ensurePages()
            let safeIdx = max(0, min(caretIndex, textStorage.length))
            let glyph = (safeIdx < textStorage.length)
                ? layoutManager.glyphIndexForCharacter(at: safeIdx)
                : max(0, layoutManager.numberOfGlyphs - 1)
            let host = layoutManager.textContainer(forGlyphAt: glyph, effectiveRange: nil, withoutAdditionalLayout: false)
            let target = pageViews.first { $0.textContainer === host } ?? pageViews.last
            if let tv = target {
                tv.window?.makeFirstResponder(tv)
                controller.textView = tv
                tv.setSelectedRange(NSRange(location: safeIdx, length: 0))
            }
        }

        // Highlight commented ranges using layout-manager temporary attributes (NOT saved to the text).
        @MainActor func applyCommentHighlights() {
            guard let lm = layoutManager, let st = textStorage else { return }
            let full = NSRange(location: 0, length: st.length)
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
            var ranges: [(NSRange, String)] = []
            for c in parent.store.comments(for: parent.url) {
                guard let r = parent.store.resolvedRange(c, in: st.string), r.length > 0, NSMaxRange(r) <= st.length else { continue }
                lm.addTemporaryAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.32), forCharacterRange: r)
                ranges.append((r, "\(c.author): \(c.text)"))
            }
            for tv in pageViews { tv.commentRanges = ranges }   // drives the hover bubble
        }

        func reposition() {
            guard let doc = docView else { return }
            let pageW = RichTextEditor.pageW, pageH = RichTextEditor.pageH, margin = RichTextEditor.margin, gap = RichTextEditor.gap
            let avail = scroll?.contentView.bounds.width ?? pageW
            let width = max(avail, pageW + 32)
            let x = (width - pageW) / 2
            var y = gap
            for (i, tv) in pageViews.enumerated() {
                sheetViews[i].frame = NSRect(x: x, y: y, width: pageW, height: pageH)
                sheetViews[i].layer?.backgroundColor = NSColor.white.cgColor
                tv.frame = NSRect(x: x + margin, y: y + margin, width: pageW - 2 * margin, height: pageH - 2 * margin)
                // Page number, centered in the bottom margin of the sheet.
                let label = numberLabels[i]
                if showNums, !(i == 0 && !numberFirst) {
                    label.stringValue = "\(numberFirst ? i + 1 : i)"
                    label.font = Coordinator.resolveFont(pnFont, CGFloat(pnSize))
                    label.textColor = pnColor.isEmpty ? NSColor(white: 0.45, alpha: 1)
                                                      : (NSColor(hexString: pnColor) ?? NSColor(white: 0.45, alpha: 1))
                    label.isHidden = false
                    let h = max(18, CGFloat(pnSize) * 1.6)
                    label.frame = NSRect(x: x, y: y + pageH - margin / 2 - h / 2, width: pageW, height: h)
                } else {
                    label.isHidden = true
                }
                y += pageH + gap
            }
            doc.frame = NSRect(x: 0, y: 0, width: width, height: y)
        }

        // The page sheet is always white, so any near-white text would be invisible.
        // Remap those runs (and the document default) to a readable near-black.
        static let pageTextColor = NSColor(white: 0.12, alpha: 1)
        static func darkenInvisibleText(_ storage: NSTextStorage) {
            let full = NSRange(location: 0, length: storage.length)
            guard full.length > 0 else { return }
            storage.beginEditing()
            storage.enumerateAttribute(.foregroundColor, in: full, options: []) { val, range, _ in
                guard let c = (val as? NSColor)?.usingColorSpace(.sRGB) else {
                    storage.addAttribute(.foregroundColor, value: pageTextColor, range: range); return
                }
                let bright = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
                if bright > 0.8 { storage.addAttribute(.foregroundColor, value: pageTextColor, range: range) }
            }
            storage.endEditing()
        }

        // Re-flow existing paragraphs to the current (tighter) line/paragraph spacing,
        // preserving each paragraph's alignment, so old documents don't look airy.
        static func normalizeSpacing(_ storage: NSTextStorage) {
            let full = NSRange(location: 0, length: storage.length)
            guard full.length > 0 else { return }
            storage.beginEditing()
            storage.enumerateAttribute(.paragraphStyle, in: full, options: []) { val, range, _ in
                let ps = ((val as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? defaultParagraphStyle()
                ps.lineSpacing = 2
                ps.paragraphSpacing = 3
                storage.addAttribute(.paragraphStyle, value: ps, range: range)
            }
            storage.endEditing()
        }

        // Resolve a saved family name + size into a concrete font (empty = system).
        static func resolveFont(_ family: String, _ size: CGFloat) -> NSFont {
            if family.isEmpty { return .systemFont(ofSize: size) }
            if let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
               let first = members.first, let name = first.first as? String,
               let f = NSFont(name: name, size: size) { return f }
            return NSFont(name: family, size: size) ?? .systemFont(ofSize: size)
        }

        // Click on a page number → popover to pick its font + size.
        @objc func editPageNumberStyle(_ g: NSGestureRecognizer) {
            guard let anchor = g.view else { return }
            let pop = NSPopover()
            pop.behavior = .transient
            pop.contentViewController = NSHostingController(rootView: PageNumberStyleView(store: parent.store))
            pop.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
            stylePopover = pop
        }

        func textDidChange(_ notification: Notification) {
            ensurePages()
            let snapshot = NSAttributedString(attributedString: textStorage)
            let url = parent.url
            debounce?.invalidate()
            debounce = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                guard self != nil else { return }
                Task { @MainActor in self?.parent.store.update(url: url, text: snapshot) }
            }
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            if let tv = notification.object as? PageTextView { controller.textView = tv }
            Task { @MainActor in self.controller.refreshSelection() }
        }

        // Google-Docs-style list continuation on Return (ranges are document-global; storage is shared).
        func textView(_ tv: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            guard let storage = tv.textStorage else { return false }
            let caret = tv.selectedRange()
            guard caret.length == 0 else { return false }
            let ns = storage.string as NSString
            let lineRange = ns.lineRange(for: NSRange(location: caret.location, length: 0))
            var line = ns.substring(with: lineRange)
            if line.hasSuffix("\n") { line.removeLast() }
            func deleteMarker(_ len: Int) {
                let range = NSRange(location: lineRange.location, length: len)
                if tv.shouldChangeText(in: range, replacementString: "") {
                    storage.replaceCharacters(in: range, with: ""); tv.didChangeText()
                    self.focusCaret(at: lineRange.location)
                }
            }
            func insert(_ s: String) {
                if tv.shouldChangeText(in: caret, replacementString: s) {
                    storage.replaceCharacters(in: caret, with: s); tv.didChangeText()
                    self.focusCaret(at: caret.location + (s as NSString).length)
                }
            }
            if line.hasPrefix("•  ") {
                let rest = String(line.dropFirst(3))
                if rest.trimmingCharacters(in: .whitespaces).isEmpty { deleteMarker(3) } else { insert("\n•  ") }
                return true
            }
            if line.hasPrefix("☐  ") || line.hasPrefix("☑  ") {
                let rest = String(line.dropFirst(3))
                if rest.trimmingCharacters(in: .whitespaces).isEmpty { deleteMarker(3) } else { insert("\n☐  ") }
                return true
            }
            let digits = line.prefix { $0.isNumber }
            if !digits.isEmpty {
                let after = line.dropFirst(digits.count)
                if after.hasPrefix(".  ") {
                    let rest = String(after.dropFirst(3))
                    if rest.trimmingCharacters(in: .whitespaces).isEmpty { deleteMarker(digits.count + 3) }
                    else { insert("\n\((Int(digits) ?? 1) + 1).  ") }
                    return true
                }
            }
            return false
        }
    }
}

// MARK: - App

@main
struct PenwickApp: App {
    @StateObject private var store = PenwickStore()
    @StateObject private var editor = EditorController()

    var body: some Scene {
        WindowGroup("Penwick") {
            ContentView().environmentObject(store).environmentObject(editor)
                .frame(minWidth: 680, minHeight: 440)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1120, height: 720)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { NotificationCenter.default.post(name: .openPenwickSettings, object: nil) }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Chapter") { if let p = store.currentProject { store.newChapter(in: p) } }
                    .keyboardShortcut("n", modifiers: .command)
                Button("New Project") { NotificationCenter.default.post(name: .openPenwickNewProject, object: nil) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Open Project…") { penwickOpenProject(store) }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Save") { penwickSave(store, editor) }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Export…") { penwickExport(store, editor) }
                    .keyboardShortcut("e", modifiers: .command)
                Button("Share…") { penwickShare(store, editor) }
                Button("Collaborate…") { penwickCollaborate(store) }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Set Your Name…") { penwickSetName(store) }
            }
            CommandMenu("Format") {
                Button("Bold") { editor.toggleBold() }.keyboardShortcut("b")
                Button("Italic") { editor.toggleItalic() }.keyboardShortcut("i")
                Button("Underline") { editor.toggleUnderline() }.keyboardShortcut("u")
                Divider()
                Button("Align Left") { editor.setAlignment(.left) }.keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Align Center") { editor.setAlignment(.center) }.keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Align Right") { editor.setAlignment(.right) }.keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button("Bullet List") { editor.list(numbered: false) }.keyboardShortcut("8", modifiers: [.command, .shift])
                Button("Numbered List") { editor.list(numbered: true) }.keyboardShortcut("7", modifiers: [.command, .shift])
                Button("Checklist") { editor.checklist() }.keyboardShortcut("9", modifiers: [.command, .shift])
            }
            CommandMenu("Chapter") {
                Button("Previous Chapter") { store.goChapter(-1) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                    .disabled(store.adjacentChapter(-1) == nil)
                Button("Next Chapter") { store.goChapter(1) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                    .disabled(store.adjacentChapter(1) == nil)
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: PenwickStore
    @EnvironmentObject var editor: EditorController
    @State private var confirmDeleteChapter = false
    @State private var showGenerator = false
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var showCollab = false
    @State private var showComments = false
    @State private var joinReq: [String: Any]?
    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("appearance") private var appearance = "auto"
    @AppStorage("focusMode") private var focusMode = false

    private var scheme: ColorScheme? {
        appearance == "light" ? .light : appearance == "dark" ? .dark : nil
    }
    private var appearanceIcon: String {
        appearance == "light" ? "sun.max" : appearance == "dark" ? "moon" : "circle.lefthalf.filled"
    }

    var body: some View {
        VStack(spacing: 0) {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Binder().navigationSplitViewColumnWidth(min: 220, ideal: 290, max: 380)
        } detail: {
            if let ch = store.selectedChapter {
                EditorView(url: ch.url).id(ch.url)
            } else { HomeView() }
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(store.selectedChapter?.title ?? "Penwick")
        .navigationSubtitle(store.currentProject?.name ?? "")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { store.selection = nil } label: { Image(systemName: "house") }
                    .help("Home")
                    .disabled(store.selectedChapter == nil)
            }
            ToolbarItem(placement: .navigation) {
                Menu {
                    Button("New Chapter") { if let p = store.currentProject { store.newChapter(in: p) } }
                    Button("New Project…") { NotificationCenter.default.post(name: .openPenwickNewProject, object: nil) }
                    Divider()
                    Button("Open Project…") { penwickOpenProject(store) }
                } label: { Image(systemName: "plus") }
                .help("Add")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                // Appearance (light / dark / system).
                Menu {
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag("auto"); Text("Light").tag("light"); Text("Dark").tag("dark")
                    }.pickerStyle(.inline)
                } label: { Label("Appearance", systemImage: appearanceIcon) }
                .help("Appearance")

                // Focus mode — hide everything but the page.
                Button { focusMode.toggle() } label: {
                    Image(systemName: focusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .help("Focus mode (⇧⌘F)").keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(store.selectedChapter == nil)

                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .help("Settings (⌘,)")

                // Tools (image & comment live in the format bar; this is the rest).
                Menu {
                    Button("Comments…") { showComments = true }.disabled(store.selectedChapter == nil)
                    Button("Name Generator…") { showGenerator = true }
                    Button("Version History…") { showHistory = true }.disabled(store.selectedChapter == nil)
                    Divider()
                    Button("Check for Updates…") { checkForUpdates(silent: false) }
                } label: { Label("Tools", systemImage: "wrench.and.screwdriver") }
                .help("Tools")

                // People / collaboration — everything about writing with others.
                Menu {
                    Button("Collaborate with a Code…") { showCollab = true }
                        .disabled(store.currentProject == nil)
                    Button("Open Shared Project…") { penwickOpenProject(store) }
                    Button("Send a Copy…") { penwickShare(store, editor) }
                        .disabled(store.selectedChapter == nil)
                    Divider()
                    Button("Set Your Name…") { penwickSetName(store) }
                } label: { Label("Share", systemImage: "person.2") }
                .help("Collaborate & share")

                Button { penwickExport(store, editor) } label: { Label("Export", systemImage: "arrow.down.doc") }
                    .labelStyle(.titleAndIcon).help("Export (⌘E)").disabled(store.selectedChapter == nil)

                Button(role: .destructive) { confirmDeleteChapter = true } label: { Image(systemName: "trash") }
                    .help("Delete chapter").keyboardShortcut(.delete, modifiers: .command)
                    .disabled(store.selectedChapter == nil)
            }
        }
        .confirmationDialog("Delete this chapter?", isPresented: $confirmDeleteChapter, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let c = store.selectedChapter { store.deleteChapter(c.url) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("\"\(store.selectedChapter?.title ?? "Untitled")\" will be removed from iCloud Drive.") }
        .onAppear { ensureOnScreen(); cleanupDuplicateApps(); checkForUpdates(silent: true) }
        // Native sheets / alerts instead of custom dimmed overlays.
        .sheet(isPresented: $showGenerator) {
            CharacterGeneratorView(onClose: { showGenerator = false })
                .environmentObject(editor)
                .frame(minWidth: 480, idealWidth: 520, minHeight: 520, idealHeight: 640)
        }
        .sheet(isPresented: $showHistory) {
            if let ch = store.selectedChapter {
                VersionHistoryView(url: ch.url, onClose: { showHistory = false })
                    .environmentObject(store)
                    .frame(minWidth: 460, idealWidth: 500, minHeight: 500, idealHeight: 600)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(onClose: { showSettings = false })
                .environmentObject(store)
                .frame(minWidth: 680, idealWidth: 680, minHeight: 560, idealHeight: 640)
        }
        .sheet(isPresented: $showCollab) {
            CollaborateView(store: store, onClose: { showCollab = false })
                .frame(minWidth: 420, idealWidth: 420, minHeight: 440, idealHeight: 460)
        }
        .sheet(isPresented: $showComments) {
            if let ch = store.selectedChapter {
                CommentsView(store: store, editor: editor, url: ch.url, onClose: { showComments = false })
            } else { Text("Open a chapter first.").padding(40) }
        }
        .alert("New Manuscript", isPresented: $showNewProject) {
            TextField("Project name", text: $newProjectName)
            Button("Create") {
                let trimmed = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
                store.newProject(named: trimmed.isEmpty ? "Untitled Project" : trimmed)
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Give your project a name.") }
        .onReceive(NotificationCenter.default.publisher(for: .openPenwickNewProject)) { _ in newProjectName = ""; showNewProject = true }
        .onReceive(NotificationCenter.default.publisher(for: .openPenwickSettings)) { _ in showSettings = true }
        .onReceive(NotificationCenter.default.publisher(for: .openPenwickGenerator)) { _ in showGenerator = true }
        .onReceive(NotificationCenter.default.publisher(for: .openPenwickHistory)) { _ in if store.selectedChapter != nil { showHistory = true } }
        .onReceive(NotificationCenter.default.publisher(for: .openPenwickExport)) { _ in penwickExport(store, editor) }
        .onReceive(NotificationCenter.default.publisher(for: .openPenwickCollaborate)) { _ in showCollab = true }
        .modifier(JoinRequestPrompt(store: store, joinReq: $joinReq))
        .modifier(DropImport(store: store, editor: editor))
        .animation(.easeInOut(duration: 0.18), value: showGenerator)
        .animation(.easeInOut(duration: 0.18), value: showHistory)
        .animation(.easeInOut(duration: 0.18), value: showSettings)
        .animation(.easeInOut(duration: 0.18), value: showNewProject)
        .onChange(of: focusMode) { _, on in columnVisibility = on ? .detailOnly : .all }
        .onAppear { columnVisibility = focusMode ? .detailOnly : .all }

            if !focusMode { UnifiedStatusBar() }
        }
        .preferredColorScheme(scheme)
    }

    private func ensureOnScreen() {
        DispatchQueue.main.async {
            guard let w = NSApp.windows.first(where: { $0.isVisible }),
                  let screen = w.screen ?? NSScreen.main else { return }
            let vf = screen.visibleFrame
            if !vf.contains(w.frame) {
                let size = w.frame.size
                let x = vf.midX - size.width / 2
                let y = vf.midY - size.height / 2
                w.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
            }
        }
    }
}

// MARK: - Binder (sidebar)

struct Binder: View {
    @EnvironmentObject var store: PenwickStore
    @AppStorage("theme") private var activeTheme = "Ocean"   // observe so accent repaints live
    @State private var collapsed: Set<URL> = Binder.loadCollapsed()
    static func loadCollapsed() -> Set<URL> {
        Set((UserDefaults.standard.array(forKey: "collapsedProjects") as? [String] ?? []).map { URL(fileURLWithPath: $0) })
    }
    @State private var search = ""
    @State private var renameTarget: Project?
    @State private var renameText = ""
    @State private var chapterToDelete: URL?
    @State private var emojiTarget: URL?
    @State private var emojiIsProject = false
    @State private var projectToDelete: Project?

    private func match(_ c: Chapter) -> Bool {
        search.isEmpty || c.title.localizedCaseInsensitiveContains(search) || c.plain.localizedCaseInsensitiveContains(search)
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(store.projects) { project in
                    let chapters = project.chapters.filter(match)
                    if !chapters.isEmpty || search.isEmpty {
                        // Project header — chevron toggles; clicking the name opens chapter 1.
                        HStack(spacing: 4) {
                            Button {
                                if collapsed.contains(project.url) { collapsed.remove(project.url) } else { collapsed.insert(project.url) }
                            } label: {
                                Image(systemName: collapsed.contains(project.url) ? "chevron.right" : "chevron.down")
                                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).frame(width: 14)
                            }.buttonStyle(.plain)
                            Button {
                                if collapsed.contains(project.url) {
                                    collapsed.remove(project.url)        // open + jump to chapter 1
                                    store.openFirstChapter(of: project)
                                } else {
                                    collapsed.insert(project.url)        // click again to hide chapters
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    if let e = store.emoji(for: project.url) {
                                        Text(e).font(.system(size: 13)).frame(width: 16)
                                    } else {
                                        Image(systemName: store.isExternal(project) ? "person.2.fill" : "book.closed.fill")
                                            .foregroundStyle(Palette.accent()).font(.system(size: 11))
                                    }
                                    Text(project.name).font(.system(size: 12, weight: .semibold))
                                    Spacer()
                                    if let d = project.lastEdited {
                                        Text(shortRelative(d)).font(.system(size: 10)).foregroundStyle(.tertiary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
                        }
                        .contextMenu {
                            Button("Set Emoji…") { emojiIsProject = true; emojiTarget = project.url }
                            Button("New Chapter") { store.newChapter(in: project) }
                            Button("Collaborate…") { store.selection = project.chapters.first?.url; NotificationCenter.default.post(name: .openPenwickCollaborate, object: nil) }
                            Button("Rename…") { renameTarget = project; renameText = project.name }
                            Button("Reveal in Finder") { store.revealInFinder(project.url) }
                            Divider()
                            if store.isExternal(project) {
                                Button("Remove from Penwick") { store.unlinkExternalProject(project) }
                            } else {
                                Button("Delete Project", role: .destructive) { projectToDelete = project }
                            }
                        }

                        if !collapsed.contains(project.url) {
                            ForEach(chapters) { ch in
                                Button { store.selection = ch.url } label: {
                                    ChapterRow(chapter: ch).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .onHover { $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
                                .listRowBackground(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(ch.url == store.selection ? Palette.accent().opacity(0.20) : Color.clear)
                                        .padding(.horizontal, 6).padding(.vertical, 1))
                                .contextMenu {
                                    Button("Set Emoji…") { emojiIsProject = false; emojiTarget = ch.url }
                                    Button("Move Up") { store.moveChapter(ch.url, in: project, up: true) }
                                    Button("Move Down") { store.moveChapter(ch.url, in: project, up: false) }
                                    Divider()
                                    Button("Reveal in Finder") { store.revealInFinder(ch.url) }
                                    Divider()
                                    Button("Delete Chapter", role: .destructive) { chapterToDelete = ch.url }
                                }
                            }
                            .onMove { offsets, dest in
                                if search.isEmpty { store.reorder(in: project, from: offsets, to: dest) }
                            }
                            Button { store.newChapter(in: project) } label: {
                                Label("New chapter", systemImage: "plus").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .onHover { $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
                        }
                    }
                }

                // Add a new project — fills the empty space at the bottom of the binder.
                Button { NotificationCenter.default.post(name: .openPenwickNewProject, object: nil) } label: {
                    Label("New Project", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
                .padding(.top, 6)
            }
            .listStyle(.sidebar)
            .searchable(text: $search, placement: .sidebar, prompt: "Search manuscript")
        }
        .onChange(of: collapsed) { _, new in
            UserDefaults.standard.set(new.map { $0.path }, forKey: "collapsedProjects")   // remember across restarts
        }
        .alert("Rename Project", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { if let p = renameTarget { store.rename(project: p, to: renameText) }; renameTarget = nil }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .confirmationDialog("Delete this chapter?",
                            isPresented: Binding(get: { chapterToDelete != nil }, set: { if !$0 { chapterToDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let u = chapterToDelete { store.deleteChapter(u) }; chapterToDelete = nil }
            Button("Cancel", role: .cancel) { chapterToDelete = nil }
        } message: {
            Text("\"\(chapterToDelete.flatMap { store.chapter($0)?.title } ?? "This chapter")\" will be removed from iCloud Drive. This can't be undone.")
        }
        .sheet(isPresented: Binding(get: { emojiTarget != nil }, set: { if !$0 { emojiTarget = nil } })) {
            if let u = emojiTarget {
                EmojiPickerView(
                    title: emojiIsProject ? "Tag this manuscript" : "Tag this document",
                    apply: { e in if emojiIsProject { store.setProjectEmoji(e, projectURL: u) } else { store.setEmoji(e, for: u) } },
                    onClose: { emojiTarget = nil })
            }
        }
        .confirmationDialog("Delete this project?",
                            isPresented: Binding(get: { projectToDelete != nil }, set: { if !$0 { projectToDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Project", role: .destructive) { if let p = projectToDelete { store.deleteProject(p) }; projectToDelete = nil }
            Button("Cancel", role: .cancel) { projectToDelete = nil }
        } message: {
            Text("\"\(projectToDelete?.name ?? "")\" and all \(projectToDelete?.chapters.count ?? 0) of its chapters will be deleted from iCloud Drive. This can't be undone.")
        }
    }
}

struct ChapterRow: View {
    @EnvironmentObject var store: PenwickStore
    let chapter: Chapter
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let e = store.emoji(for: chapter.url) {
                Text(e).font(.system(size: 16)).frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(chapter.snippet).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Text("Edited \(shortRelative(chapter.modified))")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3).padding(.leading, 4)
    }
}

// A compact emoji picker for tagging a chapter or a whole manuscript.
struct EmojiPickerView: View {
    let title: String
    var apply: (String?) -> Void
    var onClose: () -> Void
    private let choices = ["📖","📚","✍️","📝","📌","⭐️","🔥","💡","🎬","🎭","🗺️","⚔️","🌙","☀️","🌊","🏔️","🌲","🌹","🩸","👑","💀","🕯️","🔮","🎻","🚪","🗝️","📜","🪶","✨","❄️","🍂","🐉","🦊","🐺","⚓️","🧭","💔","💍","🏰","🌟"]
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 8)
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(choices, id: \.self) { e in
                    Button { apply(e); onClose() } label: {
                        Text(e).font(.system(size: 22)).frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.05)))
                    }.buttonStyle(.plain)
                }
            }
            Button("Remove emoji") { apply(nil); onClose() }
                .font(.system(size: 12)).buttonStyle(.borderless)
        }
        .padding(18).frame(width: 360)
    }
}

// MARK: - Format toolbar

struct FormatBar: View {
    @EnvironmentObject var editor: EditorController
    @EnvironmentObject var store: PenwickStore
    @Environment(\.colorScheme) var scheme
    @AppStorage("fontFamilyName") private var familyName = "New York"
    @AppStorage("fontSize") private var fontSize: Double = 17

    private var systemFamilies: [String] { NSFontManager.shared.availableFontFamilies }

    var body: some View {
        HStack(spacing: 3) {
            Menu {
                Section("Recommended") {
                    ForEach(["New York", "SF Pro", "Helvetica Neue", "Georgia", "Menlo"], id: \.self) { name in
                        Button { pick(name) } label: { Text(name).font(.custom(name, size: 13)) }
                    }
                }
                Divider()
                Section("All fonts") {
                    ForEach(systemFamilies, id: \.self) { name in
                        Button { pick(name) } label: { Text(name).font(.custom(name, size: 13)) }
                    }
                }
            } label: {
                HStack(spacing: 4) { Image(systemName: "character"); Text(displayFontName(editor.selFamily)).font(.system(size: 12)).lineLimit(1) }
                    .frame(maxWidth: 130)
            }.menuStyle(.borderlessButton).fixedSize()

            bar
            // Size: tap −/+ to nudge by one, or the number for presets.
            grp {
                fmt("minus") { stepSize(-1) }
                Menu {
                    ForEach([11, 13, 15, 17, 20, 24, 28, 36], id: \.self) { s in Button("\(s) pt") { fontSize = Double(s); editor.setSize(Double(s)) } }
                } label: { Text(editor.selSize.map { "\(Int($0))" } ?? "—").font(.system(size: 12)).frame(minWidth: 18) }
                    .menuStyle(.borderlessButton).fixedSize()
                fmt("plus") { stepSize(1) }
            }

            bar
            Menu {
                Button("Title") { editor.setHeading(size: 28) }
                Button("Heading") { editor.setHeading(size: 22) }
                Button("Subheading") { editor.setHeading(size: 18) }
                Button("Body") { editor.setHeading(size: 17) }
            } label: { HStack(spacing: 4) { Image(systemName: "textformat"); Text("Style").font(.system(size: 12)) } }
                .menuStyle(.borderlessButton).fixedSize()

            bar
            grp { fmt("bold", active: editor.selBold) { editor.toggleBold() }
                  fmt("italic", active: editor.selItalic) { editor.toggleItalic() }
                  fmt("underline", active: editor.selUnderline) { editor.toggleUnderline() }
                  fmt("strikethrough", active: editor.selStrike) { editor.toggleStrike() } }
            bar
            ColorPicker("", selection: Binding(
                get: { editor.selColor },
                set: { editor.setColor(NSColor($0)) }
            ), supportsOpacity: false).labelsHidden().frame(width: 34)
            bar
            grp { fmt("text.alignleft", active: editor.selAlign == .left || editor.selAlign == .natural) { editor.setAlignment(.left) }
                  fmt("text.aligncenter", active: editor.selAlign == .center) { editor.setAlignment(.center) }
                  fmt("text.alignright", active: editor.selAlign == .right) { editor.setAlignment(.right) } }
            bar
            grp { fmt("list.bullet", active: editor.selList == .bullet) { editor.list(numbered: false) }
                  fmt("list.number", active: editor.selList == .numbered) { editor.list(numbered: true) }
                  fmt("checklist", active: editor.selList == .checklist) { editor.checklist() } }
            bar
            fmt("bubble.left") { penwickAddComment(store, editor) }
            bar
            fmt("sparkles") { NotificationCenter.default.post(name: .openPenwickAIChat, object: nil) }
        }
    }

    private func stepSize(_ delta: Double) {
        let cur = editor.selSize.map(Double.init) ?? fontSize
        let n = min(48, max(9, (cur + delta).rounded()))
        fontSize = n; editor.setSize(n)
    }

    private var bar: some View { Divider().frame(height: 16).padding(.horizontal, 3) }
    @ViewBuilder private func grp<C: View>(@ViewBuilder _ c: () -> C) -> some View { HStack(spacing: 1) { c() } }
    private func pick(_ name: String) {
        familyName = name
        switch name { case "SF Pro": editor.setFamily(.sfPro); case "New York": editor.setFamily(.newYork); default: editor.setFamilyName(name) }
    }
    private func fmt(_ icon: String, active: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13)).frame(width: 26, height: 22)
                .foregroundStyle(active ? Palette.accent() : Color.primary)
                .background(active ? Palette.accent().opacity(0.16) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.borderless).onHover { $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
    }
}

// Reliable in-content chapter navigation (NOT a toolbar item — toolbar items get
// torn down mid-click when ContentView re-renders). Lives in the editor footer.
struct ChapterNavBar: View {
    @EnvironmentObject var store: PenwickStore

    var body: some View {
        let pos = store.chapterPosition()
        let prevURL = store.adjacentChapter(-1)
        let nextURL = store.adjacentChapter(1)
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button { store.goChapter(-1) } label: { Label("Previous", systemImage: "chevron.left") }
                    .buttonStyle(.borderless).disabled(prevURL == nil)
                    .help(prevURL.flatMap { store.chapter($0)?.title }.map { "Previous: \($0)" } ?? "First chapter")
                Spacer()
                if let pos {
                    Text("Chapter \(pos.index) of \(pos.count)")
                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Menu {
                    Toggle("Show page numbers", isOn: Binding(
                        get: { store.pageNumberPrefs.show },
                        set: { store.pageNumberPrefs.show = $0; store.savePageNumberPrefs() }))
                    Toggle("Number the first page", isOn: Binding(
                        get: { store.pageNumberPrefs.numberFirst },
                        set: { store.pageNumberPrefs.numberFirst = $0; store.savePageNumberPrefs() }))
                        .disabled(!store.pageNumberPrefs.show)
                } label: {
                    Label("Page numbers", systemImage: "number")
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Show or hide page numbers (saved per project)")
                Spacer().frame(width: 4)
                Button { store.goChapter(1) } label: { Label("Next", systemImage: "chevron.right") }
                    .buttonStyle(.borderless).disabled(nextURL == nil)
                    .help(nextURL.flatMap { store.chapter($0)?.title }.map { "Next: \($0)" } ?? "Last chapter")
            }
            .labelStyle(.titleAndIcon).font(.system(size: 12))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }
}

// MARK: - Editor

struct EditorView: View {
    @EnvironmentObject var store: PenwickStore
    @EnvironmentObject var editor: EditorController
    @Environment(\.colorScheme) var scheme
    @AppStorage("theme") private var activeTheme = "Ocean"
    @AppStorage("focusMode") private var focusMode = false
    @State private var showAI = false
    let url: URL

    var chapter: Chapter? { store.chapter(url) }

    var body: some View {
        ZStack {
            Palette.surround(scheme).ignoresSafeArea()
            VStack(spacing: 0) {
                // Full-width formatting toolbar — always shown, even in focus mode.
                VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) { FormatBar() }
                            .padding(.horizontal, 14).padding(.vertical, 6)
                    }
                    .frame(maxWidth: .infinity)
                    .background(.bar)
                    Divider()
                }

                // The paginated editor draws its own page sheets, so no paper card here.
                RichTextEditor(url: url, store: store, controller: editor,
                               showPageNumbers: store.pageNumberPrefs.show,
                               numberFirstPage: store.pageNumberPrefs.numberFirst,
                               pageNumberFont: store.pageNumberPrefs.fontName,
                               pageNumberSize: store.pageNumberPrefs.size,
                               pageNumberColor: store.pageNumberPrefs.colorHex)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                ChapterNavBar()
            }
            // AI assistant panel — opened from the format-bar sparkles button.
            .overlay(alignment: .bottomTrailing) {
                if showAI {
                    AIChatPanel(editor: editor, onClose: { showAI = false })
                        .padding(20)
                        .transition(.scale(scale: 0.92, anchor: .bottomTrailing).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.78), value: showAI)
            .onReceive(NotificationCenter.default.publisher(for: .openPenwickAIChat)) { _ in showAI.toggle() }
        }
    }
}

struct VersionHistoryView: View {
    @EnvironmentObject var store: PenwickStore
    let url: URL
    var onClose: () -> Void
    @State private var tick = 0

    private func stamp(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d, h:mm a"; return f.string(from: d)
    }

    var body: some View {
        let versions = store.versions(for: url)
        _ = tick   // re-read after Save Version
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(colors: [Palette.accent(), Palette.accentDark()], startPoint: .top, endPoint: .bottom))
                    .frame(width: 34, height: 34)
                    .overlay(Image(systemName: "clock.arrow.circlepath").foregroundStyle(.white).font(.system(size: 15)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Version History").font(.system(size: 15, weight: .semibold))
                    Text("Auto-saved snapshots of this chapter").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            Divider()

            HStack {
                Text("\(versions.count) version\(versions.count == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Save Version Now") { store.saveSnapshot(url: url, text: store.attributed(for: url)); tick += 1 }
                    .controlSize(.small)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)

            ScrollView {
                if versions.isEmpty {
                    Text("No versions yet — Penwick snapshots automatically as you write, or hit “Save Version Now.”")
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .padding(.horizontal, 30).padding(.vertical, 40)
                } else {
                    VStack(spacing: 8) {
                        ForEach(versions, id: \.url) { v in
                            HStack(spacing: 12) {
                                Image(systemName: "doc.text").foregroundStyle(Palette.accent())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stamp(v.date)).font(.system(size: 13, weight: .medium))
                                    Text(shortRelative(v.date)).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Restore") { store.restore(snapshot: v.url, into: url); onClose() }
                                    .controlSize(.small)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.06)))
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 460)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.10)))
        .shadow(color: .black.opacity(0.30), radius: 28, y: 12)
    }
}

// One status bar spanning the whole window bottom (sidebar + editor) so the
// left and right halves always line up.
struct UnifiedStatusBar: View {
    @EnvironmentObject var store: PenwickStore

    var body: some View {
        let project = store.currentProject
        let total = project?.totalWords ?? 0
        let goal = project.map { store.goal(for: $0) } ?? 0
        return VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 7, height: 7)
                Text(store.iCloudAvailable ? "Synced to iCloud" : "Saved locally").foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Text(store.projects.count == 1 ? "1 project" : "\(store.projects.count) projects").foregroundStyle(.secondary)
                if store.collaborators.count > 1 {
                    Text("·").foregroundStyle(.tertiary)
                    HStack(spacing: -5) {
                        ForEach(store.collaborators.prefix(5)) { c in
                            Text(c.initials).font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 18, height: 18).background(Circle().fill(c.color))
                                .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                                .help(c.isMe ? "\(c.name) (you)" : c.name)
                        }
                    }
                }
                Spacer()
                Image(systemName: "checkmark.icloud").foregroundStyle(.secondary)
                Text("All changes saved").foregroundStyle(.secondary)
                Spacer()
                if goal > 0 {
                    ProgressView(value: Double(min(total, goal)), total: Double(goal))
                        .frame(width: 100).controlSize(.small)
                    Text("\(total) / \(goal) words").foregroundStyle(.secondary)
                } else {
                    Text(total == 1 ? "1 word" : "\(total) words").foregroundStyle(.secondary)
                }
                Menu {
                    Button("No goal") { if let p = project { store.setGoal(0, for: p) } }
                    ForEach([1000, 5000, 10000, 50000, 80000], id: \.self) { g in
                        Button("\(g.formatted()) words") { if let p = project { store.setGoal(g, for: p) } }
                    }
                } label: { Image(systemName: "target") }
                .menuStyle(.borderlessButton).fixedSize().help("Set word goal")
            }
            .font(.system(size: 11)).frame(height: 30).padding(.horizontal, 14).background(.bar)
        }
    }
}

// MARK: - Character Generator

struct Character: Identifiable {
    let id = UUID()
    var name: String
    var gender: String
    var type: String
    var nationality: String
    var location: String
    var language: String
    var age: Int
    var birth: String
    var heightCm: Int
    var weightKg: Int
    var handedness: String
    var bloodType: String
    var death: String
    var lifespan: Int
    var cause: String

    var heightStr: String {
        let totalIn = Int((Double(heightCm) / 2.54).rounded())
        return "\(heightCm) cm / \(totalIn / 12) ft \(totalIn % 12) in"
    }
    var weightStr: String { "\(weightKg) kg / \(Int((Double(weightKg) * 2.20462).rounded())) lbs" }

    var formatted: String { name }
}

// Loads name lists bundled into the app from the NameDatabases project.
enum NameDB {
    private static var cache: [String: [String]] = [:]
    static func load(_ resource: String) -> [String] {
        if let c = cache[resource] { return c }
        var lines: [String] = []
        if let url = Bundle.main.url(forResource: resource, withExtension: "txt"),
           let s = try? String(contentsOf: url, encoding: .utf8) {
            lines = s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        cache[resource] = lines
        return lines
    }
    static var firstNames: [String] { load("firstnames") }
    static var maleFirstNames: [String] { load("firstnames-male") }
    static var femaleFirstNames: [String] { load("firstnames-female") }
    static func surnames(_ code: String) -> [String] {
        let l = load("surname-\(code)")
        return l.isEmpty ? load("surname-us") : l
    }
}

enum CharacterGen {
    struct Locale2 { let nationality: String; let language: String; let surname: String; let places: [String] }

    static let locales: [Locale2] = [
        .init(nationality: "American", language: "English", surname: "us", places: ["New York City, New York, United States", "Los Angeles, California, United States", "Chicago, Illinois, United States", "New Mexico, United States", "Austin, Texas, United States", "Seattle, Washington, United States", "Miami, Florida, United States", "Boston, Massachusetts, United States"]),
        .init(nationality: "Canadian", language: "English", surname: "us", places: ["British Columbia, Canada", "Toronto, Ontario, Canada", "Montreal, Quebec, Canada", "Calgary, Alberta, Canada", "Halifax, Nova Scotia, Canada"]),
        .init(nationality: "British", language: "English", surname: "uk", places: ["London, England, United Kingdom", "Cheshire, England, United Kingdom", "Manchester, England, United Kingdom", "Edinburgh, Scotland, United Kingdom", "Cardiff, Wales, United Kingdom"]),
        .init(nationality: "Australian", language: "English", surname: "uk", places: ["Sydney, New South Wales, Australia", "Adelaide, South Australia, Australia", "Melbourne, Victoria, Australia", "Brisbane, Queensland, Australia"]),
        .init(nationality: "Irish", language: "English", surname: "ie", places: ["Dublin, Ireland", "Cork, Ireland", "Galway, Ireland"]),
        .init(nationality: "French", language: "French", surname: "fr", places: ["Paris, Île-de-France, France", "Lyon, France", "Marseille, France"]),
        .init(nationality: "German", language: "German", surname: "de", places: ["Berlin, Germany", "Munich, Bavaria, Germany", "Hamburg, Germany"]),
        .init(nationality: "Italian", language: "Italian", surname: "it", places: ["Rome, Lazio, Italy", "Milan, Lombardy, Italy", "Naples, Campania, Italy"]),
        .init(nationality: "Spanish", language: "Spanish", surname: "es", places: ["Madrid, Spain", "Barcelona, Catalonia, Spain", "Seville, Andalusia, Spain"]),
        .init(nationality: "Mexican", language: "Spanish", surname: "es", places: ["Mexico City, Mexico", "Guadalajara, Jalisco, Mexico", "Monterrey, Nuevo León, Mexico"]),
        .init(nationality: "Russian", language: "Russian", surname: "ru", places: ["Moscow, Russia", "Saint Petersburg, Russia", "Novosibirsk, Russia"]),
        .init(nationality: "Portuguese", language: "Portuguese", surname: "pt", places: ["Lisbon, Portugal", "Porto, Portugal", "Braga, Portugal"]),
        .init(nationality: "Greek", language: "Greek", surname: "gk", places: ["Athens, Greece", "Thessaloniki, Greece", "Patras, Greece"]),
        .init(nationality: "Polish", language: "Polish", surname: "pl", places: ["Warsaw, Poland", "Kraków, Poland", "Gdańsk, Poland"]),
        .init(nationality: "Dutch", language: "Dutch", surname: "ne", places: ["Amsterdam, Netherlands", "Rotterdam, Netherlands", "Utrecht, Netherlands"]),
        .init(nationality: "Czech", language: "Czech", surname: "cz", places: ["Prague, Czechia", "Brno, Czechia", "Ostrava, Czechia"]),
    ]

    // Fallback name pools used only if the bundled databases fail to load.
    static let fallbackFirst = ["Alphonzo", "Tristan", "Greyson", "Eloise", "Maren", "Cordelia", "Julian", "Marcus", "Vivienne", "Imogen"]
    static let fallbackLast = ["Hale", "Whitlock", "Calloway", "Mercer", "Ashford", "Vance", "Sterling", "Beaumont"]

    static func titleCased(_ s: String) -> String {
        // Normalize ALLCAPS / alllower to Titlecase, but keep already-mixed
        // names intact (McDonald, O'Brien, van der Berg).
        if s == s.uppercased() || s == s.lowercased() {
            return s.prefix(1).uppercased() + s.dropFirst().lowercased()
        }
        return s
    }

    static func weighted<T>(_ items: [(T, Int)]) -> T {
        let total = items.reduce(0) { $0 + $1.1 }
        var r = Int.random(in: 0..<total)
        for (v, w) in items { if r < w { return v }; r -= w }
        return items[0].0
    }

    static func randomAge(_ type: String) -> Int {
        switch type {
        case "Child": return Int.random(in: 3...12)
        case "Adolescent": return Int.random(in: 13...17)
        case "Young Adult": return Int.random(in: 18...29)
        case "Adult": return Int.random(in: 30...49)
        case "Middle-Aged": return Int.random(in: 50...64)
        case "Senior": return Int.random(in: 65...90)
        default: return Int.random(in: 16...55)
        }
    }

    static func fmt(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMMM d, yyyy (h:mm a)"; f.amSymbol = "AM"; f.pmSymbol = "PM"
        return f.string(from: d)
    }

    static func make(gender g: String, type t: String, nationality nat: String) -> Character {
        let isMale = g == "Male" ? true : (g == "Female" ? false : Bool.random())
        let genderStr = isMale ? "Male" : "Female"
        let locale = nat == "Any" ? locales.randomElement()! : (locales.first { $0.nationality == nat } ?? locales.randomElement()!)
        let place = locale.places.randomElement()!

        let pool = isMale ? NameDB.maleFirstNames : NameDB.femaleFirstNames
        let first = pool.randomElement() ?? NameDB.firstNames.randomElement() ?? fallbackFirst.randomElement()!
        let last = NameDB.surnames(locale.surname).randomElement() ?? fallbackLast.randomElement()!
        let name = "\(first) \(titleCased(last))"

        let typeName = t == "Any"
            ? weighted([("Child", 6), ("Adolescent", 16), ("Young Adult", 26), ("Adult", 30), ("Middle-Aged", 14), ("Senior", 8)])
            : t
        let age = randomAge(typeName)

        let cal = Calendar.current
        let now = Date()
        let base = cal.date(byAdding: DateComponents(year: -age), to: now) ?? now
        var birth = cal.date(byAdding: .day, value: -Int.random(in: 0...360), to: base) ?? base
        birth = cal.date(bySettingHour: Int.random(in: 0...23), minute: Int.random(in: 0...59), second: 0, of: birth) ?? birth

        let lifespan = Int.random(in: max(age + 4, 58)...96)
        let deathBase = cal.date(byAdding: DateComponents(year: lifespan), to: birth) ?? birth
        var death = cal.date(byAdding: .day, value: Int.random(in: 0...300), to: deathBase) ?? deathBase
        death = cal.date(bySettingHour: Int.random(in: 0...23), minute: Int.random(in: 0...59), second: 0, of: death) ?? death

        let height = isMale ? Int.random(in: 162...196) : Int.random(in: 150...182)
        let weight = isMale ? Int.random(in: 55...98) : Int.random(in: 45...88)
        let handed = weighted([("Right", 88), ("Left", 10), ("Ambidextrous", 2)])
        let blood = weighted([("O+", 38), ("A+", 34), ("B+", 9), ("O-", 7), ("A-", 6), ("AB+", 3), ("B-", 2), ("AB-", 1)])
        let cause = weighted([("Unspecified Illness", 30), ("Heart Disease", 22), ("Cancer", 18), ("Stroke", 9), ("Accident", 8), ("Respiratory Disease", 6), ("Natural Causes", 7)])

        return Character(name: name, gender: genderStr, type: typeName, nationality: locale.nationality,
                         location: place, language: locale.language, age: age, birth: fmt(birth),
                         heightCm: height, weightKg: weight, handedness: handed, bloodType: blood,
                         death: fmt(death), lifespan: lifespan, cause: cause)
    }
}

struct CharacterGeneratorView: View {
    @EnvironmentObject var editor: EditorController
    @AppStorage("theme") private var activeTheme = "Ocean"
    var onClose: () -> Void = {}
    @AppStorage("nameGen_gender") private var gender = "Any"
    @AppStorage("nameGen_nationality") private var nationality = "Any"
    @AppStorage("nameGen_count") private var count = 3
    @State private var type = "Any"
    @State private var results: [Character] = []

    private let genders = ["Any", "Male", "Female"]
    private let types = ["Any", "Child", "Adolescent", "Young Adult", "Adult", "Middle-Aged", "Senior"]
    private var nationalities: [String] { ["Any"] + CharacterGen.locales.map { $0.nationality } }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(colors: [Palette.accent(), Palette.accentDark()],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 34, height: 34)
                    .overlay(Image(systemName: "person.crop.rectangle.stack").foregroundStyle(.white).font(.system(size: 15)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Name Generator").font(.system(size: 15, weight: .semibold))
                    Text("Character names for your cast").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)

            // Controls
            HStack(spacing: 14) {
                labeled("Gender") { Picker("", selection: $gender) { ForEach(genders, id: \.self) { Text($0) } }.labelsHidden().frame(width: 96) }
                labeled("Nationality") { Picker("", selection: $nationality) { ForEach(nationalities, id: \.self) { Text($0) } }.labelsHidden().frame(width: 120) }
                labeled("Count") { Stepper("\(count)", value: $count, in: 1...12).fixedSize() }
                Spacer()
                Button { generate() } label: { Label("Generate", systemImage: "wand.and.stars") }
                    .buttonStyle(.borderedProminent).controlSize(.large).tint(Palette.accent())
            }
            .padding(.horizontal, 20).padding(.bottom, 14)

            Divider()

            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(results) { c in CharacterCard(character: c) }
                }
                .padding(18)
            }
        }
        .frame(width: 460)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.10)))
        .shadow(color: .black.opacity(0.30), radius: 28, y: 12)
        .onAppear { if results.isEmpty { generate() } }
    }

    private func generate() {
        results = (0..<count).map { _ in CharacterGen.make(gender: gender, type: type, nationality: nationality) }
    }

    @ViewBuilder private func labeled<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            content()
        }
    }
}

struct CharacterCard: View {
    let character: Character
    @EnvironmentObject var editor: EditorController
    @AppStorage("theme") private var activeTheme = "Ocean"
    @State private var inserted = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            Text(character.name).font(.system(size: 17, weight: .semibold, design: .serif))
            Spacer()
            iconButton(copied ? "checkmark" : "doc.on.doc", "Copy") { copy() }
            iconButton(inserted ? "checkmark" : "square.and.arrow.down", "Insert into chapter") { insert() }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08)))
    }

    private func iconButton(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.accent())
                .frame(width: 28, height: 24).background(Palette.accent().opacity(0.14)).clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain).help(help)
        .onHover { $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(character.formatted, forType: .string)
        copied = true
    }
    private func insert() {
        editor.insert("\n" + character.formatted + "\n")
        inserted = true
    }
}

// The home pane — lives inside the normal split view (sidebar stays visible),
// uses the editor's own surface/accent, and scrolls. Shown when no chapter is open.
// Drag a compatible file onto the window → choose new chapter vs. current chapter.
struct DropImport: ViewModifier {
    @ObservedObject var store: PenwickStore
    let editor: EditorController
    @State private var dropped: [URL] = []
    @State private var ask = false

    func body(content: Content) -> some View {
        content
            .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in loadDrop(providers); return true }
            .confirmationDialog(promptTitle, isPresented: $ask, titleVisibility: .visible) {
                Button("Add as new chapter\(dropped.count > 1 ? "s" : "")") { importNew() }
                if store.selectedChapter != nil { Button("Add to the current chapter") { importCurrent() } }
                Button("Cancel", role: .cancel) { dropped = [] }
            } message: { Text("Where should Penwick put the content?") }
    }
    private var promptTitle: String {
        dropped.count == 1 ? "Add “\(dropped.first?.lastPathComponent ?? "")”" : "Add \(dropped.count) files"
    }
    private func loadDrop(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for p in providers {
            group.enter()
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var u: URL?
                if let d = item as? Data { u = URL(dataRepresentation: d, relativeTo: nil) }
                else if let url = item as? URL { u = url }
                if let u, store.isImportable(u) { lock.lock(); urls.append(u); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { if !urls.isEmpty { dropped = urls; ask = true } }
    }
    private func importNew() {
        guard let proj = store.currentProject else { dropped = []; return }
        var last: URL?
        for u in dropped { last = store.importChapter(from: u, into: proj) ?? last }
        if let l = last { store.selection = l }
        dropped = []
    }
    private func importCurrent() {
        for u in dropped { if let a = store.attributedFromFile(u) { editor.appendAtEnd(a) } }
        dropped = []
    }
}

// Host-side "X wants to join" Approve/Deny prompt (extracted so ContentView.body stays light).
struct JoinRequestPrompt: ViewModifier {
    @ObservedObject var store: PenwickStore
    @Binding var joinReq: [String: Any]?
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .penwickJoinRequest)) { note in
                if joinReq == nil, let d = note.object as? [String: Any] { joinReq = d }
            }
            .confirmationDialog("Someone wants to join",
                                isPresented: Binding(get: { joinReq != nil }, set: { if !$0 { joinReq = nil } }),
                                titleVisibility: .visible) {
                Button("Approve") { decide(true) }
                Button("Deny", role: .destructive) { decide(false) }
                Button("Cancel", role: .cancel) { joinReq = nil }
            } message: { Text(message) }
    }
    private var message: String {
        let n = (joinReq?["name"] as? String) ?? "Someone"
        let p = (joinReq?["projectName"] as? String) ?? "your project"
        return "\(n) wants to join “\(p)”."
    }
    private func decide(_ ok: Bool) {
        if let r = joinReq, let p = r["project"] as? URL, let id = r["id"] as? String {
            if ok { store.approveJoin(p, id: id) } else { store.denyJoin(p, id: id) }
        }
        joinReq = nil
    }
}

// Comments / margin notes for the current chapter.
struct CommentsView: View {
    @ObservedObject var store: PenwickStore
    let editor: EditorController
    let url: URL
    var onClose: () -> Void
    @Environment(\.colorScheme) var scheme
    private func stamp(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "MMM d, h:mm a"; return f.string(from: d) }
    var body: some View {
        let comments = store.comments(for: url)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Comments").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(.secondary) }.buttonStyle(.plain)
            }.padding(16)
            Divider()
            if comments.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "bubble.left").font(.system(size: 26)).foregroundStyle(.secondary)
                    Text("No comments yet").font(.system(size: 13, weight: .medium))
                    Text("Select text in the page, then Tools → Add Comment.").font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(comments) { c in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("“\(c.quote)”").font(.system(size: 12)).italic().foregroundStyle(.secondary).lineLimit(2)
                                Text(c.text).font(.system(size: 13))
                                HStack {
                                    Text("\(c.author) · \(stamp(c.date))").font(.system(size: 10)).foregroundStyle(.tertiary)
                                    Spacer()
                                    Button("Go to") {
                                        let r = store.resolvedRange(c, in: editor.textView?.string ?? "") ?? NSRange(location: c.location, length: c.length)
                                        editor.goTo(range: r); onClose()
                                    }
                                        .font(.system(size: 11)).buttonStyle(.borderless)
                                    Button { store.deleteComment(c.id, for: url) } label: { Image(systemName: "trash").font(.system(size: 11)) }
                                        .buttonStyle(.borderless).foregroundStyle(.red)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.paper(scheme)))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.08)))
                        }
                    }.padding(16)
                }
            }
        }
        .frame(width: 380, height: 460)
    }
}

// Subtle lift on hover — used on Home cards/buttons to make the app feel alive.
struct HoverScale: ViewModifier {
    var scale: CGFloat = 1.025
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? scale : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: hovering)
            .onHover { hovering = $0 }
    }
}
extension View { func hoverScale(_ s: CGFloat = 1.025) -> some View { modifier(HoverScale(scale: s)) } }

// Floating AI chat — chat, or (with text selected) propose an edit you approve before applying.
struct AIChatPanel: View {
    @ObservedObject var editor: EditorController
    @Environment(\.colorScheme) var scheme
    var onClose: () -> Void

    @State private var input = ""
    @State private var thinking = false
    @State private var proposalRange: NSRange?
    @State private var proposalText = ""
    @State private var proposalAttrs: [NSAttributedString.Key: Any] = [:]

    private let brand = "You are the writing assistant built into Penwick, a native Mac app for writing books and screenplays. The user is working on their manuscript. Be warm, concise, and practical — help with prose, brainstorming, structure, and names."

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(LinearGradient(colors: [Palette.accent(), Palette.accentDark()], startPoint: .top, endPoint: .bottom))
                    .frame(width: 24, height: 24)
                    .overlay(Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Penwick AI").font(.system(size: 13, weight: .semibold))
                    Text(AIClient.isConfigured ? "\(AIClient.provider.shortName) · \(AIClient.model)" : "Not linked")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if !editor.aiMessages.isEmpty {
                    Button { editor.aiMessages.removeAll() } label: { Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(.secondary) }
                        .buttonStyle(.plain).help("Clear chat")
                }
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
            .padding(12)
            Divider()

            if !AIClient.isConfigured {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "sparkles").font(.system(size: 30)).foregroundStyle(Palette.accent())
                    Text("Link an AI to get started").font(.system(size: 14, weight: .medium))
                    Text("Use a free local model with Ollama, or your own Claude / ChatGPT key.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Open AI settings") { NotificationCenter.default.post(name: .openPenwickSettings, object: nil) }
                        .buttonStyle(.borderedProminent).tint(Palette.accent())
                    Spacer()
                }.padding(.horizontal, 24)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            if editor.aiMessages.isEmpty {
                                Text("Ask me anything — or select text in your page and tell me how to change it. I'll show the edit for you to approve, and keep your font.")
                                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 6)
                            }
                            ForEach(editor.aiMessages) { m in bubble(m) }
                            if thinking { HStack(spacing: 6) { ProgressView().scaleEffect(0.5); Text("Thinking…").font(.system(size: 12)).foregroundStyle(.secondary) } }
                            if let r = proposalRange { proposalCard(r) }
                            Color.clear.frame(height: 1).id("end")
                        }
                        .padding(12)
                    }
                    .onChange(of: editor.aiMessages.count) { _, _ in withAnimation { proxy.scrollTo("end") } }
                    .onChange(of: thinking) { _, _ in withAnimation { proxy.scrollTo("end") } }
                }
            }

            Divider()
            HStack(spacing: 8) {
                TextField("Message…", text: $input, axis: .vertical).textFieldStyle(.plain).lineLimit(1...4)
                    .onSubmit(send).disabled(!AIClient.isConfigured)
                Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 22)).foregroundStyle(Palette.accent()) }
                    .buttonStyle(.plain).disabled(thinking || !AIClient.isConfigured || input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)
        }
        .frame(width: 340, height: 460)
        .background(RoundedRectangle(cornerRadius: 16).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.10)))
        .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
    }

    private func bubble(_ m: AIMessage) -> some View {
        HStack {
            if m.role == "you" { Spacer(minLength: 30) }
            Text(m.text).font(.system(size: 13)).textSelection(.enabled)
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(m.role == "you" ? Palette.accent().opacity(0.16) : Color.primary.opacity(0.06)))
                .frame(maxWidth: 250, alignment: m.role == "you" ? .trailing : .leading)
            if m.role == "ai" { Spacer(minLength: 30) }
        }
        .frame(maxWidth: .infinity, alignment: m.role == "you" ? .trailing : .leading)
    }

    private func proposalCard(_ range: NSRange) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROPOSED EDIT").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.secondary)
            Text(proposalText).font(.system(size: 13)).foregroundStyle(.primary)
            HStack {
                Button("Approve") { editor.applyEdit(range: range, text: proposalText, keeping: proposalAttrs); editor.aiMessages.append(AIMessage(role: "ai", text: "Applied — your font is kept.")); proposalRange = nil }
                    .buttonStyle(.borderedProminent).controlSize(.small).tint(Palette.accent())
                Button("Discard") { proposalRange = nil; editor.aiMessages.append(AIMessage(role: "ai", text: "Discarded.")) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.accent().opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.accent().opacity(0.4)))
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !thinking, AIClient.isConfigured else { return }
        input = ""
        let tv = editor.textView
        let sel = tv?.selectedRange() ?? NSRange(location: 0, length: 0)
        let selText = (sel.length > 0 && tv != nil) ? (tv!.string as NSString).substring(with: sel) : ""
        let selAttrs = sel.length > 0 ? editor.attributesAt(sel.location) : [:]   // capture the original font now
        editor.aiMessages.append(AIMessage(role: "you", text: text))
        thinking = true
        let history = editor.aiMessages.map { "\($0.role == "you" ? "User" : "Assistant"): \($0.text)" }.joined(separator: "\n")
        Task {
            do {
                if !selText.isEmpty {
                    let reply = try await AIClient.complete(
                        system: brand + " Apply the user's instruction to the passage and return ONLY the revised passage — no preamble, no quotes, no markdown.",
                        prompt: "Instruction: \(text)\n\nPassage:\n\(selText)")
                    await MainActor.run {
                        proposalText = reply.trimmingCharacters(in: .whitespacesAndNewlines); proposalRange = sel; proposalAttrs = selAttrs
                        editor.aiMessages.append(AIMessage(role: "ai", text: "Here's a revision — approve to apply it to your selection.")); thinking = false
                    }
                } else {
                    let reply = try await AIClient.complete(system: brand, prompt: history + "\nAssistant:")
                    await MainActor.run { editor.aiMessages.append(AIMessage(role: "ai", text: reply.trimmingCharacters(in: .whitespacesAndNewlines))); thinking = false }
                }
            } catch {
                await MainActor.run { editor.aiMessages.append(AIMessage(role: "ai", text: "Error: \(error.localizedDescription)")); thinking = false }
            }
        }
    }
}

// Collaborate via a memorable 3-word room code.
struct CollaborateView: View {
    @ObservedObject var store: PenwickStore
    var onClose: () -> Void
    @Environment(\.colorScheme) var scheme
    @State private var code = ""
    @State private var joinText = ""
    @State private var joinMsg = ""
    @State private var waiting = false
    @State private var pendingURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Collaborate").font(.system(size: 18, weight: .semibold))
                    Text("Write together with a room code").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.secondary) }.buttonStyle(.plain)
            }

            if let proj = store.currentProject {
                VStack(alignment: .leading, spacing: 10) {
                    Text("YOUR ROOM CODE").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                    Text(code).font(.system(size: 30, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(Palette.accent())
                    Text("for “\(proj.name)”").font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        capsule("Invite people…", filled: true) { penwickCollaborate(store) }
                        capsule("Copy", filled: false) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) }
                        capsule("New code", filled: false) { code = store.regenerateRoomCode(for: proj) }
                    }
                    Text("Tap Invite people to send the iCloud invite, then tell your collaborator this code. They type it below to jump straight into the same project.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Palette.paper(scheme)))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.08)))
            } else {
                Text("Open a project first to start a session.").font(.system(size: 13)).foregroundStyle(.secondary)
            }

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("JOIN A SESSION").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    TextField("TAN-ARM-HER", text: $joinText)
                        .textFieldStyle(.roundedBorder).font(.system(size: 15, design: .monospaced)).onSubmit(join)
                        .disabled(waiting)
                    if waiting { ProgressView().scaleEffect(0.6).frame(width: 60) }
                    else { capsule("Join", filled: true, action: join) }
                }
                if !joinMsg.isEmpty {
                    Text(joinMsg).font(.system(size: 11))
                        .foregroundStyle(waiting ? Color.secondary : Color.red).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20).frame(width: 380)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in pollDecision() }
        .onAppear { if let p = store.currentProject { code = store.ensureRoomCode(for: p) } }
    }

    private func join() {
        guard let url = store.findRoomFolder(code: joinText) else {
            joinMsg = "No project found for that code yet. Make sure you've accepted their iCloud invite, then try again."
            return
        }
        store.requestJoin(at: url)
        pendingURL = url; waiting = true
        joinMsg = "Asked to join — waiting for the host to approve…"
    }
    private func pollDecision() {
        guard waiting, let url = pendingURL else { return }
        switch store.joinDecision(at: url) {
        case "approved": store.openMatchedProject(url); onClose()
        case "denied": waiting = false; pendingURL = nil; joinMsg = "The host declined the request."
        default: break
        }
    }
    private func capsule(_ t: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 13))
                .foregroundStyle(filled ? Color.white : Palette.accent())
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(filled ? Palette.accent() : Color.clear))
                .overlay(Capsule().strokeBorder(Palette.accent(), lineWidth: filled ? 0 : 1))
        }.buttonStyle(.plain).onHover { $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
    }
}

struct HomeView: View {
    @EnvironmentObject var store: PenwickStore
    @Environment(\.colorScheme) var scheme
    @AppStorage("theme") private var activeTheme = "Ocean"
    @State private var quote = ""
    @State private var totalPages = 0
    @State private var appeared = false

    private let quotes = [
        "“The first draft is just you telling yourself the story.” — Terry Pratchett",
        "“A word after a word after a word is power.” — Margaret Atwood",
        "“Fill your paper with the breathings of your heart.” — William Wordsworth",
        "“There is no greater agony than bearing an untold story inside you.” — Maya Angelou",
        "“Start writing, no matter what. The water does not flow until the faucet is turned on.” — Louis L’Amour",
        "“Get it down. Take chances. It may be bad, but it’s the only way to do anything really good.” — William Faulkner",
        "“You can always edit a bad page. You can’t edit a blank one.” — Jodi Picoult",
    ]
    private var recent: [Chapter] {
        store.projects.flatMap { $0.chapters }.sorted { $0.modified > $1.modified }
    }
    private func projectName(of ch: Chapter) -> String {
        store.projects.first { $0.chapters.contains { $0.url == ch.url } }?.name ?? ""
    }
    private var totalWords: Int { store.projects.reduce(0) { $0 + $1.totalWords } }
    private var chapterCount: Int { store.projects.reduce(0) { $0 + $1.chapters.count } }
    private func computePages() {
        totalPages = store.projects.flatMap { $0.chapters }.reduce(0) { $0 + store.pageCount(for: $1.text) }
    }
    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 12 ? "Good morning" : (h < 18 ? "Good afternoon" : "Good evening")
        let name = store.authorName.split(separator: " ").first.map(String.init) ?? ""
        return name.isEmpty ? part : "\(part), \(name)"
    }
    private func fmt(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 38) {
                // Hero — big tight headline + pill CTAs (Apple editorial)
                VStack(alignment: .leading, spacing: 12) {
                    Text(greeting)
                        .font(.system(size: 44, weight: .semibold)).tracking(-0.6)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(recent.isEmpty ? "Start your first manuscript." : "Pick up your story, or start something new.")
                        .font(.system(size: 21)).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        pill("New Manuscript", filled: true) { post(.openPenwickNewProject) }
                        if let u = recent.first?.url { pill("Continue writing", filled: false) { store.selection = u } }
                    }.padding(.top, 8)
                }
                .padding(.top, 52)

                // Stats — flat metric cards
                HStack(spacing: 12) {
                    statCard("textformat", fmt(totalWords), "words")
                    statCard("books.vertical", "\(store.projects.count)", store.projects.count == 1 ? "manuscript" : "manuscripts")
                    statCard("doc.on.doc", "\(chapterCount)", chapterCount == 1 ? "chapter" : "chapters")
                    statCard("doc.richtext", "\(fmt(totalPages))", totalPages == 1 ? "page" : "pages")
                }

                if !store.projects.isEmpty {
                    sectionTitle("Your library")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 210), spacing: 16)], spacing: 16) {
                        ForEach(store.projects) { p in projectCover(p) }
                    }
                }

                if !recent.isEmpty {
                    sectionTitle("Pick up where you left off")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(recent.prefix(6)) { ch in recentRow(ch) }
                    }
                }

                sectionTitle("Tools")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 12)], spacing: 12) {
                    toolTile("person.crop.rectangle.stack", "Name generator", "Characters, gender-matched") { post(.openPenwickGenerator) }
                    toolTile("clock.arrow.circlepath", "Version history", "Restore earlier drafts") { post(.openPenwickHistory) }
                    toolTile("arrow.down.doc", "Export", "PDF, DOCX, Fountain & more") { post(.openPenwickExport) }
                    toolTile("person.2", "Collaborate", "Write together via iCloud") { post(.openPenwickCollaborate) }
                    toolTile("sparkles", "AI assistant", "Linked in Settings") { post(.openPenwickSettings) }
                    toolTile("gearshape", "Settings", "Appearance, name, updates") { post(.openPenwickSettings) }
                }

                if !store.collaborators.isEmpty {
                    sectionTitle("Who's here")
                    HStack(spacing: 8) {
                        ForEach(store.collaborators) { c in
                            HStack(spacing: 6) {
                                Circle().fill(Palette.accent()).frame(width: 7, height: 7)
                                Text(c.name).font(.system(size: 13))
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(Palette.paper(scheme)))
                            .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
                        }
                        Spacer()
                    }
                }

                Spacer(minLength: 48)
            }
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
        }
        .background(Palette.surround(scheme).ignoresSafeArea())
        .onAppear {
            if quote.isEmpty { quote = quotes.randomElement() ?? quotes[0] }
            computePages()
            appeared = false
            withAnimation(.easeOut(duration: 0.4)) { appeared = true }
        }
        .onChange(of: totalWords) { _, _ in computePages() }
    }

    private func post(_ n: Notification.Name) { NotificationCenter.default.post(name: n, object: nil) }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.system(size: 24, weight: .semibold)).tracking(-0.4)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
    }

    // Apple pill CTA — filled Action Blue, or a blue ghost outline.
    private func pill(_ title: String, filled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 16))
                .foregroundStyle(filled ? Color.white : Palette.accent())
                .padding(.horizontal, 22).padding(.vertical, 11)
                .background(Capsule().fill(filled ? Palette.accent() : Color.clear))
                .overlay(Capsule().strokeBorder(Palette.accent(), lineWidth: filled ? 0 : 1))
        }
        .buttonStyle(.plain).hoverScale().onHover { $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
    }

    private func statCard(_ icon: String, _ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Palette.accent())
            Text(value).font(.system(size: 26, weight: .semibold)).tracking(-0.5).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Palette.paper(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.08)))
    }

    private func projectCover(_ p: Project) -> some View {
        Button { store.selection = p.chapters.first?.url } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Palette.accent().opacity(0.10)).frame(height: 92)
                    Text("&").font(.system(size: 34, weight: .semibold, design: .serif)).foregroundStyle(Palette.accent())
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.name).font(.system(size: 15, weight: .semibold)).tracking(-0.2).lineLimit(1)
                    Text("\(p.chapters.count) ch · \(fmt(p.totalWords)) words").font(.system(size: 12)).foregroundStyle(.secondary)
                    if let d = p.lastEdited { Text("Edited \(shortRelative(d))").font(.system(size: 11)).foregroundStyle(.tertiary) }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18).fill(Palette.paper(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.08)))
        }
        .buttonStyle(.plain).hoverScale().onHover { $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
    }

    private func recentRow(_ ch: Chapter) -> some View {
        Button { store.selection = ch.url } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.text").font(.system(size: 15)).foregroundStyle(Palette.accent())
                VStack(alignment: .leading, spacing: 2) {
                    Text(snippet(ch.title, words: 7)).font(.system(size: 15, weight: .medium)).tracking(-0.2).lineLimit(1)
                    Text("\(projectName(of: ch)) · \(shortRelative(ch.modified)) · \(fmt(ch.wordCount)) words")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Palette.paper(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.08)))
        }
        .buttonStyle(.plain).hoverScale().onHover { $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
    }

    private func toolTile(_ icon: String, _ title: String, _ subtitle: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 17)).foregroundStyle(Palette.accent()).frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 14, weight: .medium)).tracking(-0.2).lineLimit(1)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 14).fill(Palette.paper(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.08)))
        }
        .buttonStyle(.plain).hoverScale().onHover { $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
    }

    // First few words of a title (so a giant pasted blob doesn't fill the card).
    private func snippet(_ s: String, words: Int = 6) -> String {
        let parts = s.split(whereSeparator: { $0.isWhitespace })
        let head = parts.prefix(words).joined(separator: " ")
        return parts.count > words ? head + "…" : head
    }
}
