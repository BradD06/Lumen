import LumenThemes
import SwiftUI

/// Выбор значка для заметки, папки или базы: готовые эмодзи по группам и поле для любого своего.
struct IconPicker: View {
    let current: String?
    /// `nil`: значок убрали.
    var onPick: (String?) -> Void

    @State private var custom = ""
    @Environment(\.lumenTheme) private var theme

    static let groups: [(title: String, icons: [String])] = [
        ("Учёба и работа", ["📝", "📘", "📚", "📖", "🎓", "💡", "🧠", "🗂️", "📁", "📌", "📎", "✏️", "🖋️", "📐", "🧪", "💻", "📊", "🗒️"]),
        ("Дела", ["✅", "☑️", "📋", "⭐️", "🔥", "⏰", "📅", "🎯", "🚀", "🏁", "⚡️", "🔔", "🧭", "📈", "🛠️", "💼"]),
        ("Жизнь", ["🏠", "🌱", "🌅", "🌙", "☕️", "🍎", "🏃", "🧘", "🎵", "🎨", "✈️", "💬", "❤️", "🧩", "🎁", "🐾", "📷", "🎬"]),
        ("Метки", ["🔴", "🟠", "🟡", "🟢", "🔵", "🟣", "🟤", "⚫️", "⚪️", "🔺", "🔷", "✳️", "❗️", "❓", "💎", "🏷️"]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Свой эмодзи", text: $custom)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(pickCustom)
                    .onChange(of: custom) { _, value in
                        // Достаточно одного символа: вставили или выбрали, и значок готов.
                        if let first = Self.firstSymbol(value), first != value { custom = first }
                    }
                Button("Готово", action: pickCustom)
                    .disabled(Self.firstSymbol(custom) == nil)
                if current != nil {
                    Button("Убрать", role: .destructive) { onPick(nil) }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Self.groups, id: \.title) { group in
                        Text(group.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.textSecondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 4)], spacing: 4) {
                            ForEach(group.icons, id: \.self) { icon in
                                Button {
                                    onPick(icon)
                                } label: {
                                    Text(icon)
                                        .font(.system(size: 22))
                                        .frame(width: 36, height: 36)
                                        .background(
                                            theme.textPrimary.opacity(icon == current ? 0.16 : 0),
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        )
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(icon)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 340, height: 380)
    }

    private func pickCustom() {
        guard let icon = Self.firstSymbol(custom) else { return }
        onPick(icon)
    }

    /// Первый символ строки без пробелов: эмодзи с модификаторами считается одним символом.
    nonisolated static func firstSymbol(_ text: String) -> String? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init)
    }
}
