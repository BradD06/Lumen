import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Имя системы координат доски: в ней лежат карточки, кнопки и нитки.
enum BoardSpace {
    static let name = "linkBoard"
}

/// Размеры карточек на доске. Центр карточки это точка из `BoardPin`.
enum BoardCardMetrics {
    /// Ближе к краю доски карточку не положить: иначе кнопку не достать.
    static let margin: CGFloat = 90

    static func size(of kind: BoardPin.Kind) -> CGSize {
        switch kind {
        case .source: CGSize(width: 96, height: 138)
        case .page: CGSize(width: 188, height: 132)
        case .folder: CGSize(width: 180, height: 116)
        }
    }

    /// Где кнопка, которая держит карточку: посередине верхнего края.
    static func pinPoint(center: CGPoint, kind: BoardPin.Kind) -> CGPoint {
        CGPoint(x: center.x, y: center.y - size(of: kind).height / 2 + 2)
    }

    /// Карточки висят чуть криво, как приколотые руками. Наклон постоянный для вещи.
    static func tilt(_ id: UUID) -> Double {
        Double(BookSpineStyle.seed(id) % 7) - 3
    }
}

/// Материалы доски: пробка, бумага, красная нитка. Это вещи, а не цвета темы,
/// поэтому они одинаковые во всех цветовых схемах. Рамка и кнопки латунные, из темы.
enum BoardMaterial {
    static let cork = Color(hex: 0xA97F52)
    static let corkDark = Color(hex: 0x3C230A)
    static let corkLight = Color(hex: 0xFFE6BE)
    static let thread = Color(hex: 0xB3261E)
    static let threadBright = Color(hex: 0xE0392D)
    static let paper = Color(hex: 0xF6EEDC)
    static let kraft = Color(hex: 0xEADBB8)
    static let ink = Color(hex: 0x2C2318)
    static let inkSoft = Color(hex: 0x2C2318, opacity: 0.6)
    static let handwriting = Color(hex: 0x2C3A6A)
}

// MARK: - Пробка

/// Пробковая поверхность: ровный цвет и мелкая крошка, нарисованная один раз плиткой.
struct CorkSurface: View {
    var body: some View {
        Rectangle()
            .fill(BoardMaterial.cork)
            .overlay {
                if let tile = CorkTexture.tile {
                    Rectangle().fill(ImagePaint(image: tile, scale: 0.5))
                }
            }
    }
}

/// Плитка пробковой крошки. Рисуется один раз за запуск.
@MainActor
enum CorkTexture {
    static let tile: Image? = {
        let renderer = ImageRenderer(content: CorkTile().frame(width: 160, height: 160))
        renderer.scale = 2
        #if os(macOS)
        return renderer.nsImage.map { Image(nsImage: $0) }
        #else
        return renderer.uiImage.map { Image(uiImage: $0) }
        #endif
    }()
}

private struct CorkTile: View {
    var body: some View {
        Canvas { context, size in
            // Простой генератор: одна и та же крошка при каждом запуске.
            var state: UInt64 = 0x9E37_79B9_7F4A_7C15
            func next() -> CGFloat {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return CGFloat(state >> 33) / CGFloat(UInt32.max >> 1)
            }
            for index in 0..<520 {
                let x = next() * size.width
                let y = next() * size.height
                let radius = 0.5 + next() * (index % 9 == 0 ? 1.6 : 0.9)
                let rect = CGRect(x: x, y: y, width: radius * 2, height: radius * 2)
                let isLight = index % 3 == 0
                let color = isLight ? BoardMaterial.corkLight : BoardMaterial.corkDark
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(isLight ? 0.22 : 0.3)))
            }
        }
    }
}

// MARK: - Кнопка

/// Латунная кнопка, которой карточка приколота. От неё тянут новую нитку.
struct BoardPinHead: View {
    var isActive = false

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        Circle()
            .fill(RadialGradient(
                colors: [
                    theme.accent.mix(with: .white, by: 0.55),
                    theme.accent,
                    theme.accent.mix(with: .black, by: 0.45),
                ],
                center: UnitPoint(x: 0.35, y: 0.3),
                startRadius: 0,
                endRadius: 9
            ))
            .frame(width: isActive ? 18 : 14, height: isActive ? 18 : 14)
            .shadow(color: .black.opacity(0.55), radius: 2, y: 3)
            .overlay {
                if isActive {
                    Circle().strokeBorder(BoardMaterial.threadBright, lineWidth: 2).frame(width: 26, height: 26)
                }
            }
            // Палец больше кнопки: место, за которое берут, шире.
            .frame(width: 34, height: 34)
            .contentShape(Circle())
            .animation(LumenMotion.standard, value: isActive)
    }
}

// MARK: - Нитки

/// Одна нитка на экране: от кнопки до кнопки.
struct BoardThreadLine: Equatable, Identifiable {
    var id: String
    var from: CGPoint
    var to: CGPoint
    var emphasis: Emphasis
    /// Только «лежит в папке»: тоньше и пунктиром.
    var isContainment: Bool

    enum Emphasis: Equatable {
        case normal, strong, faint
    }
}

/// Нитку тянут: от кнопки до пальца или до кнопки карточки под ним.
struct BoardThreadDraftLine: Equatable {
    var from: CGPoint
    var to: CGPoint
    var hasTarget: Bool
}

/// Все нитки доски. Провисают, как настоящие: середина ниже концов.
struct BoardThreads: View {
    let lines: [BoardThreadLine]
    var draft: BoardThreadDraftLine?

    var body: some View {
        Canvas { context, _ in
            for line in lines {
                draw(line, in: &context)
            }
            if let draft {
                let path = Self.path(from: draft.from, to: draft.to)
                context.stroke(
                    path,
                    with: .color(BoardMaterial.threadBright.opacity(draft.hasTarget ? 1 : 0.75)),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: draft.hasTarget ? [] : [7, 5])
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ line: BoardThreadLine, in context: inout GraphicsContext) {
        let path = Self.path(from: line.from, to: line.to)
        let width: CGFloat
        let color: Color
        switch line.emphasis {
        case .normal:
            width = line.isContainment ? 1.2 : 2
            color = BoardMaterial.thread
        case .strong:
            width = line.isContainment ? 1.8 : 3
            color = BoardMaterial.threadBright
        case .faint:
            width = line.isContainment ? 1 : 1.5
            color = BoardMaterial.thread.opacity(0.28)
        }
        let dash: [CGFloat] = line.isContainment ? [4, 4] : []
        // Тень под ниткой: она натянута над пробкой.
        if line.emphasis != .faint {
            context.stroke(
                path.offsetBy(dx: 0, dy: 2),
                with: .color(.black.opacity(0.32)),
                style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dash)
            )
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dash))
    }

    static func path(from a: CGPoint, to b: CGPoint) -> Path {
        var path = Path()
        path.move(to: a)
        let distance = hypot(b.x - a.x, b.y - a.y)
        let sag = min(70, distance * 0.12) + 6
        let control = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 + sag)
        path.addQuadCurve(to: b, control: control)
        return path
    }
}

// MARK: - Карточки

/// Что нарисовано на карточке.
enum BoardCardContent {
    case page(Page, snippet: String?)
    case source(Source)
    case folder(Folder, count: Int)

    init?(pin: BoardPin, snapshot: BoardSnapshot) {
        switch pin.kind {
        case .page:
            guard let page = snapshot.pages[pin.id] else { return nil }
            self = .page(page, snippet: snapshot.snippets[pin.id])
        case .source:
            guard let source = snapshot.sources[pin.id] else { return nil }
            self = .source(source)
        case .folder:
            guard let folder = snapshot.folders[pin.id] else { return nil }
            self = .folder(folder, count: snapshot.folderCounts[pin.id] ?? 0)
        }
    }

    var kind: BoardPin.Kind {
        switch self {
        case .page: .page
        case .source: .source
        case .folder: .folder
        }
    }

    var title: String {
        switch self {
        case .page(let page, _): page.displayTitle
        case .source(let source): source.displayTitle
        case .folder(let folder, _): folder.displayName
        }
    }

    /// Что это за вещь, для подписи сверху и для VoiceOver.
    var caption: String {
        switch self {
        case .page(let page, _):
            if page.isNotebook { return "Тетрадь" }
            if page.sourceId != nil { return "Заметки к книге" }
            if page.isDatabaseRow { return "Запись" }
            if page.inInbox { return "Записка" }
            return "Лист"
        case .source(let source):
            return source.author ?? "Книга"
        case .folder(_, let count):
            return count > 0 ? "Папка · \(count.objectCountText)" : "Папка"
        }
    }
}

/// Карточка на доске: обложка книги, лист бумаги или крафтовая папка.
struct BoardCard: View {
    let content: BoardCardContent
    let attachments: AttachmentStore
    var isSelected = false
    var isDimmed = false
    /// Сколько ниток у выбранной карточки: подписано от руки под ней.
    var threadCount: Int?

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        let size = BoardCardMetrics.size(of: content.kind)
        face
            .frame(width: size.width, height: size.height)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(theme.accent.opacity(0.85), lineWidth: 3)
                        .padding(-6)
                }
            }
            .overlay(alignment: .bottom) {
                if let threadCount {
                    Text(Self.threadText(threadCount))
                        .font(.system(.callout, design: .serif).italic().weight(.semibold))
                        .foregroundStyle(BoardMaterial.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(BoardMaterial.paper, in: RoundedRectangle(cornerRadius: 3))
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                        .rotationEffect(.degrees(-2))
                        .offset(y: 22)
                        .transition(.opacity)
                }
            }
            .shadow(color: .black.opacity(0.55), radius: 10, y: 9)
            .opacity(isDimmed ? 0.45 : 1)
            .saturation(isDimmed ? 0.6 : 1)
    }

    @ViewBuilder
    private var face: some View {
        switch content {
        case .source(let source):
            SourceCoverArt(
                source: source,
                attachments: attachments,
                width: BoardCardMetrics.size(of: .source).width,
                height: BoardCardMetrics.size(of: .source).height
            )
        case .page(let page, let snippet):
            paper(fill: BoardMaterial.paper) {
                Text(content.caption.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(BoardMaterial.inkSoft)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let icon = page.icon, !icon.isEmpty {
                        Text(icon).font(.system(size: 14))
                    }
                    Text(page.displayTitle)
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .lineLimit(2)
                }
                .foregroundStyle(BoardMaterial.ink)
                if let snippet {
                    Text(snippet)
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(BoardMaterial.inkSoft)
                        .lineLimit(3)
                }
            }
        case .folder(let folder, _):
            paper(fill: BoardMaterial.kraft) {
                HStack(spacing: 6) {
                    // Ярлык цвета папки, как цветной язычок на крафтовой папке.
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.folderCard(folder.color).colors.first ?? theme.accent)
                        .frame(width: 18, height: 6)
                    Text(content.caption.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(BoardMaterial.inkSoft)
                        .lineLimit(1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let icon = folder.icon, !icon.isEmpty {
                        Text(icon).font(.system(size: 14))
                    }
                    Text(folder.displayName)
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .lineLimit(2)
                }
                .foregroundStyle(BoardMaterial.ink)
            }
        }
    }

    private func paper<Content: View>(fill: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5, content: content)
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(fill, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
    }

    /// «1 связь», «3 связи», «5 связей».
    static func threadText(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        let word: String
        if mod10 == 1 && mod100 != 11 {
            word = "связь"
        } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            word = "связи"
        } else {
            word = "связей"
        }
        return count == 0 ? "пока без связей" : "\(count) \(word)"
    }
}
