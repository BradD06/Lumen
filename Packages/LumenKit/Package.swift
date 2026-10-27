// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LumenKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "LumenCore", targets: ["LumenCore"]),
        .library(name: "LumenStorage", targets: ["LumenStorage"]),
        .library(name: "LumenThemes", targets: ["LumenThemes"]),
        .library(name: "LumenUI", targets: ["LumenUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
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
        // Экраны приложения на SwiftUI.
        .target(
            name: "LumenUI",
            dependencies: [
                "LumenCore",
                "LumenStorage",
                "LumenThemes",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(name: "LumenCoreTests", dependencies: ["LumenCore"]),
        .testTarget(name: "LumenStorageTests", dependencies: ["LumenStorage", "LumenCore"]),
        .testTarget(name: "LumenUITests", dependencies: ["LumenUI", "LumenStorage", "LumenCore"]),
    ]
)
