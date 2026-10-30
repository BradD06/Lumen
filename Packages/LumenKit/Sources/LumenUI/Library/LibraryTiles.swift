import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Цвета папок: пять ярких из палитры темы и стеклянная.
enum FolderPalette {
    static let names = ["Персик", "Солнце", "Лаванда", "Лайм", "Небо", "Стекло"]

    static func name(_ color: Int) -> String {
        names.indices.contains(color) ? names[color] : names[0]
    }
}

/// Папка как в Goodnotes: задняя стенка с ярлыком, торчащие листы и глянцевый передний карман.
/// Когда над папкой держат предмет, карман приоткрывается сильнее.
struct FolderArt: View {
    let color: Int
    var count: Int?
    var isTargeted = false

    @Environment(\.lumenTheme) private var theme

    private var isGlass: Bool { color == Folder.glassColor }
    private var card: Theme.VividCard { theme.vividCard(color) }

    private var backColor: Color {
        isGlass ? Color(hex: 0x5A3E62, opacity: 0.95) : (card.colors.last ?? theme.accent).mix(with: .black, by: 0.25)
    }

    private var foreground: Color { isGlass ? theme.textPrimary : card.foreground }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(backColor)
                .frame(width: 136, height: 96)
                .offset(y: 12)
            UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 12, style: .continuous)
                .fill(backColor)
                .frame(width: 56, height: 22)
                .offset(y: 3)
            paper(Color(hex: 0xFFF3EC), width: 110)
                .rotationEffect(.degrees(-4))
                .offset(x: 12, y: 20)
            paper(Color(hex: 0xEFDFD0), width: 106)
                .rotationEffect(.degrees(5))
                .offset(x: 22, y: 24)
            front
                .frame(width: 136, height: 78)
                .rotation3DEffect(
                    .degrees(isTargeted ? -26 : -12),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .bottom,
                    perspective: 0.6
                )
                .offset(y: 30)
        }
        .frame(width: 136, height: 108, alignment: .topLeading)
        .scaleEffect(isTargeted ? 1.08 : 1, anchor: .bottom)
        .animation(.spring(duration: 0.25), value: isTargeted)
    }

    private func paper(_ color: Color, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(color)
            .frame(width: width, height: 58)
            .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
    }

    private var front: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 10, bottomLeadingRadius: 14, bottomTrailingRadius: 14, topTrailingRadius: 10,
            style: .continuous
        )
        return ZStack(alignment: .bottomTrailing) {
            if isGlass {
                shape.fill(.ultraThinMaterial)
                shape.fill(LinearGradient(
                    colors: [.white.opacity(0.3), .white.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            } else {
                shape.fill(LinearGradient(colors: card.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            // Глянец сверху кармана.
            shape.fill(LinearGradient(
                colors: [.white.opacity(0.4), .white.opacity(0)],
                startPoint: .top,
                endPoint: .center
            ))
            if let count {
                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(foreground.opacity(0.75))
                    .padding(.trailing, 11)
                    .padding(.bottom, 7)
            }
        }
        .overlay(shape.strokeBorder(
            LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0)], startPoint: .top, endPoint: .center),
            lineWidth: 1
        ))
        .clipShape(shape)
        .shadow(color: (isGlass ? Color.black : card.colors.last ?? .black).opacity(0.55), radius: 13, y: 10)
    }
}

/// Маленький значок папки для сайдбара и списков.
struct FolderGlyph: View {
    let color: Int
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 2, bottomLeadingRadius: 3, bottomTrailingRadius: 3, topTrailingRadius: 3,
            style: .continuous
        )
        .fill(color == Folder.glassColor
            ? AnyShapeStyle(theme.textPrimary.opacity(0.35))
            : AnyShapeStyle(LinearGradient(colors: theme.vividCard(color).colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
        .frame(width: 14, height: 11)
    }
}

/// Обложка страницы на холсте: тетрадка с корешком, полосой обложки и началом текста.
/// Если у страницы есть подстраницы, за ней видна стопка листов, а на обложке их число.
struct PageCoverArt: View {
    let preview: PagePreview
    let attachments: AttachmentStore
    var subpageCount = 0

    @Environment(\.lumenTheme) private var theme

    private var page: Page { preview.page }

    var body: some View {
        ZStack {
            // Не больше двух листов: дальше стопка только шумит.
            ForEach(Array(0..<min(subpageCount, 2)).reversed(), id: \.self) { index in
                sheet
                    .rotationEffect(.degrees(Double(index + 1) * 4), anchor: .bottomLeading)
                    .offset(x: CGFloat(index + 1) * 5, y: -CGFloat(index + 1) * 2)
            }
            cover
                .overlay(alignment: .topTrailing) {
                    if subpageCount > 0 {
                        subpageBadge
                    }
                }
        }
    }

    private var sheet: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 12, topTrailingRadius: 12,
            style: .continuous
        )
        .fill(theme.cardFill.mix(with: .white, by: 0.12))
        .overlay(UnevenRoundedRectangle(
            topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 12, topTrailingRadius: 12,
            style: .continuous
        ).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .frame(width: 100, height: 132)
        .shadow(color: .black.opacity(0.3), radius: 6, y: 4)
    }

    private var subpageBadge: some View {
        Label("\(subpageCount)", systemImage: "doc.on.doc.fill")
            .font(.system(size: 9, weight: .bold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.35), in: Capsule())
            .padding(6)
    }

    @ViewBuilder
    private var cover: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 12, topTrailingRadius: 12,
            style: .continuous
        )
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                if let cover = page.pageCover {
                    PageCoverView(cover: cover, attachments: attachments, height: 40)
                } else {
                    // Без своей обложки у страницы постоянный цвет из палитры темы.
                    LinearGradient(
                        colors: theme.vividCard(Int(page.id.uuid.0)).colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(height: 40)
                }
                if let icon = page.icon, !icon.isEmpty {
                    Text(icon)
                        .font(.system(size: 18))
                        .padding(.leading, 12)
                        .offset(y: 10)
                }
            }
            Text(preview.excerpt.isEmpty ? page.displayTitle : preview.excerpt)
                .font(.system(size: 7))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(9)
                .padding(.top, 14)
                .padding(.horizontal, 12)
                .padding(.leading, 3)
            Spacer(minLength: 0)
        }
        .frame(width: 100, height: 132)
        .background(.ultraThinMaterial)
        .background(theme.cardFill)
        .overlay(alignment: .leading) {
            // Корешок тетради.
            LinearGradient(
                colors: [.black.opacity(0.3), .white.opacity(0.14), .black.opacity(0.08)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 7)
        }
        .overlay(shape.strokeBorder(
            LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom),
            lineWidth: 1
        ))
        .clipShape(shape)
        .shadow(color: .black.opacity(0.5), radius: 13, y: 12)
    }
}

/// Плитка на холсте: картинка, подпись (или поле для переименования) и строка под ней.
struct LibraryTile<Art: View>: View {
    let title: String
    let caption: String
    var isSelected = false
    var isTargeted = false
    var isDragging = false
    @Binding var renameText: String
    var isRenaming = false
    var onCommitRename: () -> Void = {}
    /// Сколько прочитано, от 0 до 1: полоска между картинкой и подписью. `nil` без полоски.
    /// Непрочитанная книга оставляет под полоску пустое место, чтобы подписи в ряду не прыгали.
    var progress: Double?
    @ViewBuilder var art: () -> Art

    @FocusState private var isRenameFocused: Bool
    @Environment(\.lumenTheme) private var theme

    var body: some View {
        VStack(spacing: 6) {
            // Под полоску картинка становится чуть ниже: плитка остаётся прежнего размера.
            art()
                .frame(height: progress == nil ? 132 : 132 - 4 - ReadingProgressBar.height, alignment: .bottom)
            if let progress {
                ReadingProgressBar(progress: progress)
                    .frame(width: SourceCoverArt.size.width)
                    .opacity(progress > 0.005 ? 1 : 0)
                    .padding(.top, 4)
            }
            if isRenaming {
                TextField("Название", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.accent, lineWidth: 1.5))
                    .focused($isRenameFocused)
                    .onSubmit(onCommitRename)
                    .onAppear { isRenameFocused = true }
                    .onChange(of: isRenameFocused) { _, focused in
                        if !focused { onCommitRename() }
                    }
            } else {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            Text(caption)
                .font(.caption2)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
        }
        .padding(8)
        .frame(width: LibraryLayout.tileWidth, height: LibraryLayout.tileHeight, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isTargeted ? Color(hex: 0xFFE07A).opacity(0.12) : theme.accent.opacity(isSelected ? 0.14 : 0))
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(hex: 0xFFE07A).opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            } else if isSelected {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(theme.accent.opacity(0.75), lineWidth: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .scaleEffect(isDragging ? 1.06 : 1)
        .rotationEffect(.degrees(isDragging ? -3 : 0))
        .shadow(color: .black.opacity(isDragging ? 0.45 : 0), radius: 24, y: 20)
        .animation(.spring(duration: 0.2), value: isDragging)
    }
}

extension Int {
    /// «1 объект», «3 объекта», «12 объектов».
    var objectCountText: String {
        let mod10 = self % 10
        let mod100 = self % 100
        let word: String
        if mod10 == 1 && mod100 != 11 {
            word = "объект"
        } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            word = "объекта"
        } else {
            word = "объектов"
        }
        return "\(self) \(word)"
    }
}

/// Полоска прочитанного под обложкой книги: на светлой обложке поверх картинки её не видно.
struct ReadingProgressBar: View {
    static let height = 8.0

    let progress: Double

    @Environment(\.lumenTheme) private var theme

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.textPrimary.opacity(0.16))
                Capsule()
                    .fill(theme.accent)
                    .frame(width: max(Self.height, geometry.size.width * min(max(progress, 0), 1)))
                    .shadow(color: theme.accent.opacity(0.6), radius: 4)
            }
        }
        .frame(height: Self.height)
        .accessibilityElement()
        .accessibilityLabel("Прочитано \(Int((progress * 100).rounded()))%")
    }
}

/// Книга или файл на холсте: обложка из файла или нарисованная и корешок.
struct SourceCoverArt: View {
    static let size = CGSize(width: 92, height: 128)

    let source: Source
    let attachments: AttachmentStore

    @Environment(\.lumenTheme) private var theme

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 10, topTrailingRadius: 10,
            style: .continuous
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let cover = source.cover {
                AttachmentImage(name: cover, attachments: attachments, contentMode: .fill)
                    .frame(width: Self.size.width, height: Self.size.height)
                    .clipped()
            } else {
                drawnCover
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .overlay(alignment: .leading) {
            // Корешок книги.
            LinearGradient(
                colors: [.black.opacity(0.35), .white.opacity(0.18), .black.opacity(0.1), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 10)
        }
        .overlay(alignment: .topTrailing) {
            if !source.format.isBook || source.cover != nil {
                Text(source.format.label)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(5)
            }
        }
        .overlay(shape.strokeBorder(
            LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
            lineWidth: 1
        ))
        .clipShape(shape)
        .shadow(color: .black.opacity(0.5), radius: 12, y: 10)
    }

    /// Обложка без картинки: постоянный цвет по книге, название и автор.
    private var drawnCover: some View {
        let card = theme.vividCard(Int(source.id.uuid.1))
        return ZStack {
            LinearGradient(colors: card.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center)
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: source.format.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                Text(source.displayTitle)
                    .font(.system(size: 11, weight: .bold, design: .serif))
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if let author = source.author {
                    Text(author)
                        .font(.system(size: 8, weight: .medium))
                        .lineLimit(2)
                        .opacity(0.8)
                }
                Text(source.format.label.uppercased())
                    .font(.system(size: 7, weight: .heavy))
                    .opacity(0.6)
            }
            .foregroundStyle(card.foreground)
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
