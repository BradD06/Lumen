.PHONY: project test open

# Сгенерировать Lumen.xcodeproj из project.yml
project:
	xcodegen generate

# Тесты всех модулей
test:
	swift test --package-path Packages/LumenKit

open: project
	open Lumen.xcodeproj
