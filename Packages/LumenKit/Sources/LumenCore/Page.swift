import Foundation

/// Страница: заметка, документ или (позже) строка базы данных. Страницы образуют дерево.
public struct Page: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var parentId: UUID?
    public var title: String
    /// Эмодзи или имя SF Symbol.
    public var icon: String?
    /// Обложка страницы, см. `PageCover`.
    public var cover: String?
    /// Фон страницы, см. `PageBackground`. `nil` это фон темы.
    public var background: String?
    /// Источник (книга, файл), к которому привязана заметка. Появится на этапе 3.
    public var sourceId: UUID?
    /// Быстрые заметки лежат во «Входящих», пока их не разложат по разделам.
    public var inInbox: Bool
    public var isFavorite: Bool
    /// Дробный индекс порядка среди соседей, см. `SortKey`.
    public var sortKey: String
    public var createdAt: Date
    public var updatedAt: Date
    /// Мягкое удаление: страница лежит в корзине.
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        parentId: UUID? = nil,
        title: String = "",
        icon: String? = nil,
        cover: String? = nil,
        background: String? = nil,
        sourceId: UUID? = nil,
        inInbox: Bool = false,
        isFavorite: Bool = false,
        sortKey: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.parentId = parentId
        self.title = title
        self.icon = icon
        self.cover = cover
        self.background = background
        self.sourceId = sourceId
        self.inInbox = inInbox
        self.isFavorite = isFavorite
        self.sortKey = sortKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Без названия" : trimmed
    }

    public var isTrashed: Bool { deletedAt != nil }

    public var pageCover: PageCover? {
        get { cover.flatMap(PageCover.init(rawValue:)) }
        set { cover = newValue?.rawValue }
    }

    public var pageBackground: PageBackground? {
        get { background.flatMap(PageBackground.init(rawValue:)) }
        set { background = newValue?.rawValue }
    }
}

/// Обложка страницы: градиент из палитры темы или картинка из вложений.
/// В базе хранится строкой: `gradient:2` или `image:<имя файла>`.
public enum PageCover: Hashable, Sendable {
    case gradient(Int)
    case image(String)

    public init?(rawValue: String) {
        if rawValue.hasPrefix("gradient:"), let index = Int(rawValue.dropFirst("gradient:".count)) {
            self = .gradient(index)
        } else if rawValue.hasPrefix("image:"), rawValue.count > "image:".count {
            self = .image(String(rawValue.dropFirst("image:".count)))
        } else {
            return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .gradient(let index): "gradient:\(index)"
        case .image(let name): "image:\(name)"
        }
    }
}

/// Фон страницы за текстом: многослойные «обои» или своя картинка из вложений.
/// В базе хранится строкой: `wallpaper:0,5,1,42,1` или `image:<имя файла>`.
public enum PageBackground: Hashable, Sendable {
    case wallpaper(Wallpaper)
    case image(String)

    public init?(rawValue: String) {
        if rawValue.hasPrefix("wallpaper:"), let wallpaper = Wallpaper(rawValue: String(rawValue.dropFirst("wallpaper:".count))) {
            self = .wallpaper(wallpaper)
        } else if rawValue.hasPrefix("image:"), rawValue.count > "image:".count {
            self = .image(String(rawValue.dropFirst("image:".count)))
        } else {
            return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .wallpaper(let wallpaper): "wallpaper:\(wallpaper.rawValue)"
        case .image(let name): "image:\(name)"
        }
    }
}

/// Объёмные обои из полупрозрачных слоёв гор: небо, солнце и гряды, которые светлеют к горизонту.
/// Рисует их `LayeredWallpaper` из LumenThemes, здесь только настройки.
public struct Wallpaper: Hashable, Sendable {
    public static let layerRange = 2...7

    /// Номер палитры, см. `WallpaperPalette`.
    public var palette: Int
    /// Сколько гряд гор от горизонта до переднего плана.
    public var layers: Int
    public var hasSun: Bool
    /// Гранёные горы из прямых линий, как в дизайн-примере, вместо скалистых гребней.
    public var isFaceted: Bool
    /// Зерно формы гор: одно и то же зерно всегда даёт те же горы.
    public var seed: Int

    public init(palette: Int = 0, layers: Int = 5, hasSun: Bool = true, isFaceted: Bool = false, seed: Int = 7) {
        self.palette = palette
        self.layers = min(max(layers, Self.layerRange.lowerBound), Self.layerRange.upperBound)
        self.hasSun = hasSun
        self.isFaceted = isFaceted
        self.seed = seed
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ",").map { Int($0) }
        // Пятое поле (гранёные горы) добавлено позже, без него горы скалистые.
        guard parts.count == 4 || parts.count == 5, !parts.contains(nil) else { return nil }
        let values = parts.compactMap { $0 }
        self.init(
            palette: values[0],
            layers: values[1],
            hasSun: values[2] != 0,
            isFaceted: values.count == 5 && values[4] != 0,
            seed: values[3]
        )
    }

    var rawValue: String {
        "\(palette),\(layers),\(hasSun ? 1 : 0),\(seed),\(isFaceted ? 1 : 0)"
    }
}
