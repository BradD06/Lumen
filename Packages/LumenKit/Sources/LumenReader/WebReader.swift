import Foundation
import SwiftUI
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Выделение в тексте, которое красит читалка.
public struct WebHighlight: Hashable, Sendable {
    public var id: UUID
    public var text: String
    public var offset: Int
    public var colorHex: UInt32

    public init(id: UUID, text: String, offset: Int, colorHex: UInt32) {
        self.id = id
        self.text = text
        self.offset = offset
        self.colorHex = colorHex
    }
}

/// Что происходит в открытой главе.
public enum WebReaderEvent: Sendable {
    /// Глава загрузилась.
    case ready
    /// Выделили текст. `text` для цитаты, `raw` и `offset` чтобы найти это место снова.
    case selection(text: String, raw: String, offset: Int, label: String?, progression: Double)
    case selectionCleared
    /// Прокрутили главу, `progression` от 0 до 1. `anchor` это последний пройденный якорь оглавления,
    /// `offset` сколько символов главы стоит до первой строки вверху экрана.
    case scrolled(Double, anchor: String?, offset: Int?)
    /// Нажали на выделение.
    case highlightTapped(UUID)
    /// Листают дальше конца главы (`forward`) или назад от её начала.
    case turnedPastEdge(forward: Bool)
}

/// Управляет веб-видом главы. Экран читалки держит один такой объект и через него
/// открывает главы, меняет оформление и прокручивает к выделениям.
@MainActor
public final class WebReaderController: NSObject {
    public let webView: WKWebView
    public var onEvent: (@MainActor (WebReaderEvent) -> Void)?

    private var appearance = ReaderAppearance()
    private var highlights: [WebHighlight] = []
    private var isReady = false
    /// Что сделать, когда глава загрузится.
    private var pendingProgression: Double?
    private var pendingOffset: Int?
    private var pendingReveal: UUID?
    private var pendingAnchor: String?
    private var anchors: [String] = []
    private var loadedURL: URL?

    public override init() {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: ReaderScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        configuration.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        controller.add(WeakMessageHandler(self), name: ReaderScript.handlerName)
        webView.navigationDelegate = self
        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        #endif
    }

    /// Открывает главу. `reveal` прокручивает к выделению, `anchor` к пункту оглавления,
    /// `offset` к строке, где остановились, иначе к `progression`.
    public func load(_ url: URL, root: URL, progression: Double = 0, offset: Int? = nil, reveal: UUID? = nil, anchor: String? = nil) {
        pendingProgression = progression
        pendingOffset = offset
        pendingReveal = reveal
        pendingAnchor = anchor
        if url == loadedURL, isReady {
            applyPending()
            return
        }
        isReady = false
        loadedURL = url
        webView.loadFileURL(url, allowingReadAccessTo: root)
    }

    public func setAppearance(_ appearance: ReaderAppearance) {
        guard appearance != self.appearance else { return }
        self.appearance = appearance
        guard isReady else { return }
        // Другой размер шрифта сдвигает текст: скрипт оставляет вверху ту же строку.
        webView.evaluateJavaScript("window.lumen && window.lumen.restyle(\(Self.jsString(appearance.css)))")
    }

    public func setHighlights(_ highlights: [WebHighlight]) {
        guard highlights != self.highlights else { return }
        self.highlights = highlights
        if isReady { paint() }
    }

    public func reveal(_ id: UUID) {
        guard isReady else {
            pendingReveal = id
            return
        }
        webView.evaluateJavaScript("window.lumen && window.lumen.reveal('\(id.uuidString)')")
    }

    public func scroll(to progression: Double) {
        webView.evaluateJavaScript("window.lumen && window.lumen.scrollTo(\(progression))")
    }

    /// Прокрутка к строке, перед которой в главе `offset` символов.
    public func scroll(toOffset offset: Int) {
        webView.evaluateJavaScript("window.lumen && window.lumen.scrollToOffset(\(offset))")
    }

        public func scroll(toAnchor anchor: String) {
        webView.evaluateJavaScript("window.lumen && window.lumen.scrollToAnchor(\(Self.jsString(anchor)))")
    }

    /// Якоря оглавления в открытой главе, в порядке текста.
    public func setAnchors(_ anchors: [String]) {
        self.anchors = anchors
        if isReady { applyAnchors() }
    }

    /// Заголовки открытой главы, когда в самом файле оглавления нет.
    public func headings(section: Int) async -> [TocEntry] {
        guard isReady else { return [] }
        let json: String? = await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("window.lumen ? window.lumen.headings() : '[]'") { result, _ in
                continuation.resume(returning: result as? String)
            }
        }
        struct Heading: Decodable {
            var id: String
            var title: String
            var level: Int
        }
        guard let data = json?.data(using: .utf8),
              let headings = try? JSONDecoder().decode([Heading].self, from: data) else { return [] }
        return headings.map { TocEntry(title: $0.title, section: section, anchor: $0.id, level: $0.level) }
    }

    public func clearSelection() {
        webView.evaluateJavaScript("window.lumen && window.lumen.clearSelection()")
    }

    /// Последняя известная доля прокрутки главы.
    public private(set) var currentProgression: Double = 0

    // MARK: Внутреннее

    fileprivate func receive(_ body: Any) {
        guard let message = body as? [String: Any], let type = message["type"] as? String else { return }
        switch type {
        case "ready":
            isReady = true
            applyStyle()
            paint()
            // Сначала к нужному месту, потом якоря: они сразу сообщают, где читатель.
            applyPending()
            applyAnchors()
            onEvent?(.ready)
        case "selection":
            let text = message["text"] as? String ?? ""
            if text.isEmpty {
                onEvent?(.selectionCleared)
            } else {
                onEvent?(.selection(
                    text: text,
                    raw: message["raw"] as? String ?? text,
                    offset: (message["offset"] as? NSNumber)?.intValue ?? 0,
                    label: message["label"] as? String,
                    progression: (message["progression"] as? NSNumber)?.doubleValue ?? currentProgression
                ))
            }
        case "scroll":
            let value = (message["progression"] as? NSNumber)?.doubleValue ?? 0
            currentProgression = value
            onEvent?(.scrolled(value, anchor: message["anchor"] as? String, offset: (message["offset"] as? NSNumber)?.intValue))
        case "turn":
            let direction = (message["direction"] as? NSNumber)?.intValue ?? 1
            onEvent?(.turnedPastEdge(forward: direction > 0))
        case "highlightTap":
            if let id = (message["id"] as? String).flatMap(UUID.init(uuidString:)) {
                onEvent?(.highlightTapped(id))
            }
        default:
            break
        }
    }

    private func applyStyle() {
        webView.evaluateJavaScript("window.lumen && window.lumen.setStyle(\(Self.jsString(appearance.css)))")
    }

    private func paint() {
        let items = highlights.map { item -> String in
            let color = String(format: "#%06X", item.colorHex)
            return "{id:'\(item.id.uuidString)',text:\(Self.jsString(item.text)),offset:\(item.offset),color:'\(color)'}"
        }
        webView.evaluateJavaScript("window.lumen && window.lumen.paint([\(items.joined(separator: ","))])")
    }

    private func applyAnchors() {
        let list = anchors.map(Self.jsString).joined(separator: ",")
        webView.evaluateJavaScript("window.lumen && window.lumen.setAnchors([\(list)])")
    }

    private func applyPending() {
        let offset = pendingOffset
        pendingOffset = nil
        if let id = pendingReveal {
            pendingReveal = nil
            pendingAnchor = nil
            pendingProgression = nil
            reveal(id)
        } else if let anchor = pendingAnchor {
            pendingAnchor = nil
            pendingProgression = nil
            scroll(toAnchor: anchor)
        } else if let offset {
            currentProgression = pendingProgression ?? currentProgression
            pendingProgression = nil
            webView.evaluateJavaScript("window.lumen && window.lumen.scrollToOffset(\(offset))")
        } else if let progression = pendingProgression {
            pendingProgression = nil
            currentProgression = progression
            scroll(to: progression)
        }
    }

    /// Строка JavaScript в кавычках, со всеми спецсимволами экранированными через JSON.
    static func jsString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let array = String(data: data, encoding: .utf8) else { return "''" }
        return String(array.dropFirst().dropLast())
    }
}

extension WebReaderController: WKNavigationDelegate {
    /// Ссылки внутри книги открываются в читалке, внешние в браузере. В сеть сама книга не ходит.
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        if url.isFileURL || url.scheme == "about" { return .allow }
        if navigationAction.navigationType == .linkActivated {
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            await UIApplication.shared.open(url)
            #endif
        }
        return .cancel
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Глава без <body> или с ошибкой скрипта не пришлёт «ready»: тогда считаем готовой здесь.
        if !isReady {
            webView.evaluateJavaScript("window.lumen ? 1 : 0") { [weak self] result, _ in
                MainActor.assumeIsolated {
                    guard let self, !self.isReady, (result as? NSNumber)?.intValue == 1 else { return }
                    self.receive(["type": "ready"])
                }
            }
        }
    }
}

/// Обработчик сообщений держит контроллер слабо: иначе веб-вид и контроллер держали бы друг друга.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WebReaderController?

    init(_ target: WebReaderController) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            target?.receive(message.body)
        }
    }
}

/// Веб-вид главы в SwiftUI.
public struct WebReaderView: View {
    let controller: WebReaderController

    public init(controller: WebReaderController) {
        self.controller = controller
    }

    public var body: some View {
        Representable(controller: controller)
    }

    #if os(macOS)
    private struct Representable: NSViewRepresentable {
        let controller: WebReaderController
        func makeNSView(context: Context) -> WKWebView { controller.webView }
        func updateNSView(_ nsView: WKWebView, context: Context) {}
    }
    #else
    private struct Representable: UIViewRepresentable {
        let controller: WebReaderController
        func makeUIView(context: Context) -> WKWebView { controller.webView }
        func updateUIView(_ uiView: WKWebView, context: Context) {}
    }
    #endif
}
