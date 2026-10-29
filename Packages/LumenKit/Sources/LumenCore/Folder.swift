import Foundation

/// Папка библиотеки. Папки вкладываются друг в друга, в них лежат страницы, книги и файлы.
/// Как в Goodnotes, но без сетки: у каждой папки и страницы своё место на холсте родительской папки.
public struct Folder: Identifiable, Hashable, Codable, Sendable {
    public static let colorCount = 6
    /// Последний цвет из палитры: полупрозрачная «стеклянная» папка.
    public static let glassColor = 5

    public var id: UUID
    public var parentId: UUID?
    public var name: String
    /// Номер цвета, см. `colorCount`.
    public var color: Int
    /// Место на холсте родителя. `nil`: папку ещё не двигали, приложение само найдёт свободное место.
    public var canvasX: Double?
    public var canvasY: Double?
    public var createdAt: Date
    public var updatedAt: Date
    /// Мягкое удаление: папка лежит в корзине.
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        parentId: UUID? = nil,
        name: String = "",
        color: Int = 0,
        position: LibraryPoint? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.parentId = parentId
        self.name = name
        self.color = color
        self.canvasX = position?.x
        self.canvasY = position?.y
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Без названия" : trimmed
    }

    public var isTrashed: Bool { deletedAt != nil }

    public var position: LibraryPoint? {
        get { LibraryPoint(x: canvasX, y: canvasY) }
        set {
            canvasX = newValue?.x
            canvasY = newValue?.y
        }
    }
}

/// Точка на холсте библиотеки, в пунктах, от левого верхнего угла.
public struct LibraryPoint: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Точка, если заданы обе координаты.
    public init?(x: Double?, y: Double?) {
        guard let x, let y else { return nil }
        self.init(x: x, y: y)
    }
}

/// Что лежит на холсте библиотеки.
public enum LibraryItemID: Hashable, Sendable, Identifiable {
    case folder(UUID)
    case page(UUID)
    /// Книга или файл.
    case source(UUID)

    public var id: Self { self }
}

/// Раскладка холста библиотеки. Предметы лежат где угодно, сетка нужна только чтобы
/// найти место новому предмету и для кнопки «Сетка», которая выравнивает всё по ячейкам.
public enum LibraryLayout {
    /// Размер плитки (папки или документа) на холсте.
    public static let tileWidth = 152.0
    public static let tileHeight = 200.0
    /// Шаг ячеек сетки и отступ первой ячейки от края холста.
    public static let cellWidth = 172.0
    public static let cellHeight = 216.0
    public static let origin = LibraryPoint(x: 24, y: 16)

    /// Левый верхний угол ячейки под номером `index`, ячейки идут по строкам.
    public static func cell(_ index: Int, columns: Int) -> LibraryPoint {
        let columns = max(columns, 1)
        return LibraryPoint(
            x: origin.x + Double(index % columns) * cellWidth,
            y: origin.y + Double(index / columns) * cellHeight
        )
    }

    /// Ближайшая ячейка сетки к точке. Ячейки левее и выше первой не бывает.
    public static func snapped(_ point: LibraryPoint) -> LibraryPoint {
        LibraryPoint(
            x: origin.x + max(0, ((point.x - origin.x) / cellWidth).rounded()) * cellWidth,
            y: origin.y + max(0, ((point.y - origin.y) / cellHeight).rounded()) * cellHeight
        )
    }

    /// Места для `count` новых предметов: первые ячейки, которые не задевают уже лежащие предметы.
    public static func freeCells(count: Int, avoiding placed: [LibraryPoint], columns: Int) -> [LibraryPoint] {
        var taken = placed
        var result: [LibraryPoint] = []
        var index = 0
        while result.count < count {
            let candidate = cell(index, columns: columns)
            if !taken.contains(where: { overlaps($0, candidate) }) {
                result.append(candidate)
                taken.append(candidate)
            }
            index += 1
        }
        return result
    }

    /// Пересекаются ли плитки с такими левыми верхними углами.
    public static func overlaps(_ a: LibraryPoint, _ b: LibraryPoint) -> Bool {
        abs(a.x - b.x) < tileWidth && abs(a.y - b.y) < tileHeight
    }
}
