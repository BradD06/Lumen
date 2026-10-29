// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LumenKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "LumenCore", targets: ["LumenCore"]),
        .library(name: "LumenStorage", targets: ["LumenStorage"]),
        .library(name: "LumenThemes", targets: ["LumenThemes"]),
        .library(name: "LumenReader", targets: ["LumenReader"]),
        .library(name: "LumenSync", targets: ["LumenSync"]),
        .library(name: "LumenUI", targets: ["LumenUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        // Модели и чистая логика без зависимостей: страницы, блоки, порядок, markdown-сокращения.
        .target(name: "LumenCore"),
        // SQLite через GRDB: схема, миграции, репозитории, полнотекстовый поиск FTS5.
        .target(
            name: "LumenStorage",
            dependencies: [
                "LumenCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        // Дизайн-токены, темы, фон и карточки-виджеты.
        .target(name: "LumenThemes"),
        // Читалка: EPUB, FB2, Word, презентации и текст переводятся в HTML для общего экрана чтения,
        // PDF показывает PDFKit, остальное системный просмотр.
        .target(
            name: "LumenReader",
            dependencies: [
                "LumenCore",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ]
        ),
        // Синхронизация через iCloud (CloudKit, CKSyncEngine). Включается только в сборке с контейнером iCloud.
        // Типы CloudKit пока не размечены для строгой проверки Swift 6, поэтому модуль в режиме Swift 5.
        .target(
            name: "LumenSync",
            dependencies: [
                "LumenStorage",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Экраны приложения на SwiftUI.
        .target(
            name: "LumenUI",
            dependencies: [
                "LumenCore",
                "LumenStorage",
                "LumenThemes",
                "LumenReader",
                "LumenSync",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(name: "LumenCoreTests", dependencies: ["LumenCore"]),
        .testTarget(name: "LumenStorageTests", dependencies: ["LumenStorage", "LumenCore"]),
        .testTarget(
            name: "LumenReaderTests",
            dependencies: ["LumenReader", "LumenCore", .product(name: "ZIPFoundation", package: "ZIPFoundation")]
        ),
        .testTarget(name: "LumenUITests", dependencies: ["LumenUI", "LumenStorage", "LumenCore"]),
    ]
)
