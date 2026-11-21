import LumenReader
import LumenThemes
import SwiftUI

/// Настройки → «Нейроголос по своему ключу»: ключ ElevenLabs (в Связке ключей), проверка,
/// голос, модель, «Послушать» и переключатель «Читать нейроголосом».
struct NeuralVoiceSettingsSection: View {
    @Environment(\.lumenTheme) private var theme
    @State private var keyText = ""
    @State private var status: String?
    @State private var isWorking = false
    @State private var isConfirmingDelete = false
    @State private var cacheSize = 0
    /// Ползунки двигаются здесь, а в голос уходят, когда их отпустили: иначе каждый шаг
    /// перезапускал бы фразу и тратил знаки.
    @State private var tuning = ReadAloud.shared.elevenTuning
    private var readAloud: ReadAloud { .shared }

    var body: some View {
        Section {
            if readAloud.hasNeuralKey {
                LabeledContent("Ключ ElevenLabs") {
                    Text(readAloud.maskedNeuralKey ?? "")
                        .monospaced()
                        .foregroundStyle(theme.textSecondary)
                }
                Toggle("Читать нейроголосом", isOn: engineBinding)
                    .disabled(readAloud.elevenVoiceId == nil)
                Picker("Голос", selection: voiceBinding) {
                    if readAloud.neuralVoices.isEmpty, let name = readAloud.elevenVoiceName, let id = readAloud.elevenVoiceId {
                        Text(name).tag(Optional(id))
                    }
                    if readAloud.elevenVoiceId == nil { Text("Не выбран").tag(String?.none) }
                    ForEach(readAloud.neuralVoices) { voice in
                        Text(voice.shownDetails.isEmpty ? voice.name : "\(voice.name) · \(voice.shownDetails)").tag(Optional(voice.id))
                    }
                }
                Picker("Модель", selection: modelBinding) {
                    ForEach(NeuralVoiceModel.allCases, id: \.self) { model in
                        Text(model.title).tag(model)
                    }
                }
                tuningSlider("Ровность", value: $tuning.stability, low: "живее", high: "ровнее")
                tuningSlider("Выразительность", value: $tuning.style, low: "как диктор", high: "ярче")
                    .disabled(readAloud.elevenModel == .v3)
                HStack {
                    Text(tuningHint)
                        .font(.callout)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Как было") {
                        tuning = .standard
                        readAloud.elevenTuning = .standard
                    }
                    .buttonStyle(.borderless)
                    .disabled(readAloud.elevenTuning == .standard)
                }
                HStack(spacing: 10) {
                    Button("Послушать") { run { try await readAloud.playNeuralSample() } }
                        .disabled(readAloud.elevenVoiceId == nil)
                    Button("Проверить ключ") {
                        run {
                            let account = try await readAloud.neuralAccount()
                            status = describe(account)
                        }
                    }
                    Button("Обновить голоса") { run { try await readAloud.loadNeuralVoices() } }
                    if isWorking { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Удалить ключ", role: .destructive) { isConfirmingDelete = true }
                }
                .buttonStyle(.borderless)
                if cacheSize > 0 {
                    LabeledContent("Озвученное на устройстве") {
                        HStack(spacing: 10) {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(cacheSize), countStyle: .file))
                                .foregroundStyle(theme.textSecondary)
                            Button("Очистить") {
                                NeuralVoiceCache.clear()
                                cacheSize = 0
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } else {
                SecureField("Ключ API ElevenLabs", text: $keyText)
                    .textContentType(.password)
                    .onSubmit(saveKey)
                HStack(spacing: 10) {
                    Button("Сохранить ключ", action: saveKey)
                        .disabled(keyText.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
                    if isWorking { ProgressView().controlSize(.small) }
                    Spacer()
                    Link("Где взять ключ", destination: ElevenLabsClient.keysPage)
                }
                .buttonStyle(.borderless)
            }
            if let status {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Нейроголос по своему ключу")
        } footer: {
            Text(footer)
        }
        .task(id: readAloud.hasNeuralKey) {
            cacheSize = NeuralVoiceCache.size()
            guard readAloud.hasNeuralKey, readAloud.neuralVoices.isEmpty else { return }
            try? await readAloud.loadNeuralVoices()
        }
        .confirmationDialog("Удалить ключ ElevenLabs с этого устройства?", isPresented: $isConfirmingDelete) {
            Button("Удалить ключ", role: .destructive) {
                readAloud.deleteNeuralKey()
                status = nil
            }
        } message: {
            Text("Книги снова будет читать голос Apple. Ключ в самом ElevenLabs останется рабочим.")
        }
    }

    private func tuningSlider(_ title: String, value: Binding<Double>, low: String, high: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(low).font(.caption).foregroundStyle(theme.textTertiary)
                Slider(value: value, in: 0...1, step: 0.05, onEditingChanged: { isEditing in
                    if !isEditing { readAloud.elevenTuning = tuning }
                })
                .frame(minWidth: 140)
                Text(high).font(.caption).foregroundStyle(theme.textTertiary)
            }
        }
    }

    private var tuningHint: String {
        if readAloud.elevenModel == .v3 {
            return "У v3 у ровности три ступени, выразительность она подбирает сама. Странные ударения: попробуйте ровность повыше."
        }
        return "Странные ударения и скачки интонации: поднимите ровность и опустите выразительность. Новое звучание слышно с текущей фразы."
    }

    private var footer: String {
        if readAloud.hasNeuralKey {
            return "Ключ хранится только на этом устройстве, в Связке ключей, и отправляется только в ElevenLabs. Каждая озвученная фраза тратит знаки вашего тарифа; уже озвученное хранится на устройстве и второй раз не тратится."
        }
        return "ElevenLabs читает живым нейроголосом. На elevenlabs.io зайдите в профиль → API Keys, создайте ключ с правами «Text to Speech» и «Voices: Read» и вставьте его сюда. Ключ хранится только на этом устройстве, в Связке ключей."
    }

    private var engineBinding: Binding<Bool> {
        Binding(
            get: { readAloud.engine == .elevenLabs },
            set: { readAloud.engine = $0 ? .elevenLabs : .apple }
        )
    }

    private var voiceBinding: Binding<String?> {
        Binding(
            get: { readAloud.elevenVoiceId },
            set: { id in
                if let voice = readAloud.neuralVoices.first(where: { $0.id == id }) { readAloud.chooseNeuralVoice(voice) }
            }
        )
    }

    private var modelBinding: Binding<NeuralVoiceModel> {
        Binding(get: { readAloud.elevenModel }, set: { readAloud.elevenModel = $0 })
    }

    private func saveKey() {
        let key = keyText
        run {
            let account = try await readAloud.saveNeuralKey(key)
            keyText = ""
            readAloud.engine = .elevenLabs
            status = "Ключ сохранён. " + describe(account)
        }
    }

    private func describe(_ account: NeuralVoiceAccount?) -> String {
        guard let account else { return "Ключ рабочий. Сколько знаков осталось, ElevenLabs этому ключу не показывает." }
        let number = IntegerFormatStyle<Int>().locale(Locale(identifier: "ru"))
        var text = "Осталось \(account.remaining.formatted(number)) из \(account.limit.formatted(number)) знаков в этом месяце"
        if !account.tier.isEmpty { text += " (тариф \(account.tier))" }
        return text + "."
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await action()
            } catch {
                status = "Не получилось: \(error.localizedDescription)"
            }
        }
    }
}
