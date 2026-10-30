import Foundation

extension Date {
    /// «сейчас», «5 минут назад», «вчера». Всегда по-русски: у приложения нет
    /// английского перевода, а системный формат иначе берёт язык сборки и пишет «now».
    public var lumenRelative: String {
        formatted(.relative(presentation: .named).locale(Locale(identifier: "ru_RU")))
    }
}
