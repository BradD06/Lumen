import LumenCore
import LumenStorage
import LumenThemes
import SwiftUI

/// Фон за страницей: фон темы, многослойные обои или своя картинка.
/// Поверх лежит лёгкое затемнение, чтобы текст читался на любом фоне.
struct PageBackgroundView: View {
    let background: PageBackground?
    let attachments: AttachmentStore
    /// Насколько зашло солнце на обоях, см. `LayeredWallpaper.sunset`.
    var sunset: Double = 0

    var body: some View {
        switch background {
        case nil:
            ThemedBackground()
        case .wallpaper(let wallpaper):
            LayeredWallpaper(
                palette: wallpaper.palette,
                layers: wallpaper.layers,
                hasSun: wallpaper.hasSun,
                isFaceted: wallpaper.isFaceted,
                seed: wallpaper.seed,
                sunset: sunset
            )
                .overlay(Color.black.opacity(0.22))
                .ignoresSafeArea()
        case .image(let name):
            Color.black
                .overlay {
                    AttachmentImage(name: name, attachments: attachments, contentMode: .fill)
                }
                .clipped()
                .overlay(Color.black.opacity(0.35))
                .ignoresSafeArea()
        }
    }
}

/// Конструктор фона страницы: палитра, число слоёв гор, солнце и форма гор.
/// Изменения сразу видны на странице за листом.
struct PageBackgroundPicker: View {
    let model: PageEditorModel
    var onPickPhoto: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.lumenTheme) private var theme

    private var wallpaper: Wallpaper? {
        if case .wallpaper(let wallpaper) = model.page?.pageBackground { wallpaper } else { nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageBackgroundView(background: model.page?.pageBackground, attachments: model.database.attachments)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous))

                    section("Обои") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                            ForEach(WallpaperPalette.all) { palette in
                                paletteButton(palette)
                            }
                        }
                    }

                    if let wallpaper {
                        section("Слои") {
                            Picker("Горы", selection: binding(\.isFaceted, wallpaper)) {
                                Text("Скалистые").tag(false)
                                Text("Гранёные").tag(true)
                            }
                            .pickerStyle(.segmented)
                            Stepper(value: binding(\.layers, wallpaper), in: Wallpaper.layerRange) {
                                Text("Гряд гор: \(wallpaper.layers)")
                            }
                            Toggle("Солнце", isOn: binding(\.hasSun, wallpaper))
                            Button {
                                var changed = wallpaper
                                changed.seed = Int.random(in: 0..<100_000)
                                model.setBackground(.wallpaper(changed))
                            } label: {
                                Label("Другие горы", systemImage: "shuffle")
                            }
                        }
                    }

                    section("Ещё") {
                        Button {
                            dismiss()
                            onPickPhoto()
                        } label: {
                            Label("Своё фото…", systemImage: "photo")
                        }
                        Button {
                            model.setBackground(nil)
                        } label: {
                            Label("Как в теме", systemImage: "paintpalette")
                        }
                        .disabled(model.page?.background == nil)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Фон страницы")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 520)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(theme.textSecondary)
            content()
        }
    }

    private func paletteButton(_ palette: WallpaperPalette) -> some View {
        let isSelected = wallpaper?.palette == palette.id
        return Button {
            var changed = wallpaper ?? Wallpaper()
            changed.palette = palette.id
            model.setBackground(.wallpaper(changed))
        } label: {
            VStack(spacing: 6) {
                LayeredWallpaper(
                    palette: palette.id,
                    layers: wallpaper?.layers ?? 5,
                    hasSun: wallpaper?.hasSun ?? true,
                    isFaceted: wallpaper?.isFaceted ?? false,
                    seed: wallpaper?.seed ?? Wallpaper().seed
                )
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? theme.accent : .white.opacity(0.1), lineWidth: isSelected ? 2.5 : 1)
                }
                Text(palette.name)
                    .font(.caption)
                    .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Wallpaper, Value>, _ wallpaper: Wallpaper) -> Binding<Value> {
        Binding(
            get: { wallpaper[keyPath: keyPath] },
            set: { value in
                var changed = wallpaper
                changed[keyPath: keyPath] = value
                model.setBackground(.wallpaper(changed))
            }
        )
    }
}
