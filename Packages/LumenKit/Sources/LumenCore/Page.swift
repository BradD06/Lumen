import Foundation

/// Страница: заметка, документ или строка базы данных. Страницы образуют дерево.
public struct Page: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var parentId: UUID?
    public var title: String
    /// Эмодзи или имя SF Symbol.
    public var icon: String?
    /// Обложка страницы, см. `PageCover`.
    public var cover: String?
    /// Ракурс и высота обложки, см. `CoverCrop`. `nil`: картинка по центру, средняя высота.
    public var coverCrop: String?
    /// Фон страницы, см. `PageBackground`. `nil` это фон темы.
    public var background: String?
    /// Источник (книга, файл), к которому привязана заметка. Появится на этапе 3.
    public var sourceId: UUID?
    /// Папка библиотеки. Только у страниц верхнего уровня: подстраницы живут внутри своей страницы.
    public var folderId: UUID?
    /// Место на холсте папки, см. `Folder.position`.
    public var canvasX: Double?
    public var canvasY: Double?
    /// Быстрые заметки лежат во «Входящих», пока их не разложат по разделам.
    public var inInbox: Bool
    public var isFavorite: Bool
    /// База данных, строкой которой является страница, см. `DataTable`. Строка вложена в страницу базы.
    public var databaseId: UUID?
    /// Значения свойств строки базы данных.
    public var properties: PropertyValues?
    /// Вид страницы строкой, см. `pageKind`. Строкой, а не перечислением: вид из более новой
    /// версии приложения не должен ломать чтение страницы в старой.
    public var kind: String?
    /// Лист заметки (номер с нуля), приколотый к полке «Кабинета». `nil`: ничего не приколото.
    public var shelfPin: Int?
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
        folderId: UUID? = nil,
        position: LibraryPoint? = nil,
        inInbox: Bool = false,
        isFavorite: Bool = false,
        databaseId: UUID? = nil,
        properties: PropertyValues? = nil,
        kind: PageKind? = nil,
        shelfPin: Int? = nil,
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
        self.folderId = folderId
        self.canvasX = position?.x
        self.canvasY = position?.y
        self.inInbox = inInbox
        self.isFavorite = isFavorite
        self.databaseId = databaseId
        self.properties = properties
        self.kind = kind?.rawValue
        self.shelfPin = shelfPin
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

    /// Строка базы данных, а не самостоятельная страница: в списках подстраниц её нет.
    public var isDatabaseRow: Bool { databaseId != nil }

    /// Рукописная заметка: листы, на которых пишут от руки, а не блоки текста.
    public var isNotebook: Bool { pageKind == .notebook }

    /// Вид страницы: обычная из блоков (`nil`) или рукописная заметка.
    public var pageKind: PageKind? {
        get { kind.flatMap(PageKind.init(rawValue:)) }
        set { kind = newValue?.rawValue }
    }

    public var position: LibraryPoint? {
        get { LibraryPoint(x: canvasX, y: canvasY) }
        set {
            canvasX = newValue?.x
            canvasY = newValue?.y
        }
    }

    public var pageCover: PageCover? {
        get { cover.flatMap(PageCover.init(rawValue:)) }
        set { cover = newValue?.rawValue }
    }

    public var pageBackground: PageBackground? {
        get { background.flatMap(PageBackground.init(rawValue:)) }
        set { background = newValue?.rawValue }
    }

    /// Ракурс обложки. Без сохранённого ракурса картинка стоит по центру.
    public var pageCoverCrop: CoverCrop {
        get { coverCrop.flatMap(CoverCrop.init(rawValue:)) ?? CoverCrop() }
        set { coverCrop = newValue == CoverCrop() ? nil : newValue.rawValue }
    }
}

/// Какая часть картинки видна в полосе обложки и какой полоса высоты.
/// Картинка закрывает полосу целиком; лишнее по краям скрыто, его и выбирает ракурс.
/// В базе хранится строкой: `0.5,0.3,1.4,medium` (x, y, увеличение, высота).
public struct CoverCrop: Hashable, Sendable {
    /// Высота полосы обложки над листом.
    public enum Height: String, CaseIterable, Sendable {
        case low, medium, high

        public var points: Double {
            switch self {
            case .low: 170
            case .medium: 240
            case .high: 330
            }
        }

        public var title: String {
            switch self {
            case .low: "Низкая"
            case .medium: "Средняя"
            case .high: "Высокая"
            }
        }
    }

    public static let minZoom = 1.0
    public static let maxZoom = 3.0

    /// Сколько скрытого по ширине лежит слева от видимого: 0 левый край, 0,5 середина, 1 правый край.
    public var focusX: Double
    /// То же по высоте: 0 видно верх картинки, 1 низ.
    public var focusY: Double
    /// Во сколько раз картинка крупнее, чем нужно, чтобы закрыть полосу.
    public var zoom: Double
    public var height: Height

    public init(focusX: Double = 0.5, focusY: Double = 0.5, zoom: Double = 1, height: Height = .medium) {
        self.focusX = Self.unit(focusX)
        self.focusY = Self.unit(focusY)
        self.zoom = min(max(zoom, Self.minZoom), Self.maxZoom)
        self.height = height
    }

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 4,
              let x = Double(parts[0]), let y = Double(parts[1]), let zoom = Double(parts[2]),
              x.isFinite, y.isFinite, zoom.isFinite else { return nil }
        self.init(focusX: x, focusY: y, zoom: zoom, height: Height(rawValue: parts[3]) ?? .medium)
    }

    public var rawValue: String {
        func number(_ value: Double) -> String { String(format: "%.3f", value) }
        return "\(number(focusX)),\(number(focusY)),\(number(zoom)),\(height.rawValue)"
    }

    /// Сдвиг ракурса, когда картинку тянут на `dx`, `dy` точек. `spanX`, `spanY`: сколько точек
    /// картинки скрыто по ширине и высоте. Тянут вниз: показывается то, что было выше.
    public func dragged(dx: Double, dy: Double, spanX: Double, spanY: Double) -> CoverCrop {
        var crop = self
        if spanX > 0 { crop.focusX = Self.unit(focusX - dx / spanX) }
        if spanY > 0 { crop.focusY = Self.unit(focusY - dy / spanY) }
        return crop
    }

    /// Как положить картинку `imageWidth × imageHeight` в полосу `boxWidth × boxHeight`:
    /// картинка закрывает полосу целиком (как «заполнить»), потом увеличивается на `zoom`.
    /// Размер картинки ещё неизвестен (`nil`): считаем, что она как раз по полосе.
    public func layout(boxWidth: Double, boxHeight: Double, imageWidth: Double?, imageHeight: Double?) -> CoverLayout {
        let box = (width: max(boxWidth, 1), height: max(boxHeight, 1))
        var image = (width: box.width, height: box.height)
        if let imageWidth, let imageHeight, imageWidth > 0, imageHeight > 0 {
            image = (imageWidth, imageHeight)
        }
        let scale = max(box.width / image.width, box.height / image.height) * zoom
        let width = image.width * scale
        let height = image.height * scale
        let spanX = max(width - box.width, 0)
        let spanY = max(height - box.height, 0)
        return CoverLayout(
            width: width, height: height,
            spanX: spanX, spanY: spanY,
            offsetX: -spanX * focusX, offsetY: -spanY * focusY
        )
    }

    private static func unit(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0.5
    }
}

/// Картинка обложки на экране: её размер, сколько скрыто по краям и где её левый верхний угол
/// относительно полосы (сдвиги отрицательные или ноль).
public struct CoverLayout: Hashable, Sendable {
    public var width: Double
    public var height: Double
    public var spanX: Double
    public var spanY: Double
    public var offsetX: Double
    public var offsetY: Double

    /// Есть ли что двигать: картинка больше полосы хотя бы в одну сторону.
    public var canMove: Bool { spanX > 0.5 || spanY > 0.5 }
}

/// Обложка страницы: градиент из палитры темы, горы как у обоев или картинка из вложений.
/// В базе хранится строкой: `gradient:2`, `wallpaper:0,4,1,42,1` или `image:<имя файла>`.
public enum PageCover: Hashable, Sendable {
    case gradient(Int)
    case wallpaper(Wallpaper)
    case image(String)

    public init?(rawValue: String) {
        if rawValue.hasPrefix("gradient:"), let index = Int(rawValue.dropFirst("gradient:".count)) {
            self = .gradient(index)
        } else if rawValue.hasPrefix("wallpaper:"), let wallpaper = Wallpaper(rawValue: String(rawValue.dropFirst("wallpaper:".count))) {
            self = .wallpaper(wallpaper)
        } else if rawValue.hasPrefix("image:"), rawValue.count > "image:".count {
            self = .image(String(rawValue.dropFirst("image:".count)))
        } else {
            return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .gradient(let index): "gradient:\(index)"
        case .wallpaper(let wallpaper): "wallpaper:\(wallpaper.rawValue)"
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
