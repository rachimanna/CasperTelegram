import AVFoundation
import SwiftUI

struct VoiceChangerView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settingsStore: CasperSettingsStore
    @Environment(\.dismiss) private var dismiss

    /// Если экран открыт из чата — можно сразу отправить результат.
    var targetChat: ChatSummary?

    @StateObject private var recorder = VoiceRecorder()
    @State private var effect: VoiceEffect = .none
    @State private var sourceURL: URL?
    @State private var output: VoiceProcessor.Output?
    @State private var isProcessing = false
    @State private var isSending = false
    @State private var status: String?
    @State private var player: AVAudioPlayer?

    private let processor = VoiceProcessor()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    recordCard
                    effectsGrid

                    if let output {
                        resultCard(output: output)
                    }

                    if let status {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    notesCard
                }
                .padding(16)
            }
            .navigationTitle("Voice Changer")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") { cleanUpAndDismiss() }
                }
            }
            .onAppear { effect = settingsStore.settings.voice.lastEffect }
        }
    }

    // MARK: Запись

    private var recordCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(recorder.isRecording ? Color.red.opacity(0.18) : Color.accentColor.opacity(0.14))
                    .frame(width: 128, height: 128)
                    .scaleEffect(1 + CGFloat(recorder.level) * 0.25)
                    .animation(.easeOut(duration: 0.08), value: recorder.level)

                Button {
                    recorder.isRecording ? finishRecording() : startRecording()
                } label: {
                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white)
                        .frame(width: 82, height: 82)
                        .background(Circle().fill(recorder.isRecording ? Color.red : Color.accentColor))
                }
                .buttonStyle(.plain)
            }

            Text(recorder.isRecording
                 ? String(format: "Запись · %.1f с", recorder.duration)
                 : (sourceURL == nil ? "Нажмите, чтобы записать" : "Запись готова"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .casperSurface(cornerRadius: 22)
    }

    // MARK: Эффекты

    private var effectsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Эффект")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                ForEach(VoiceEffect.allCases) { item in
                    Button {
                        effect = item
                        settingsStore.settings.voice.lastEffect = item
                        if sourceURL != nil { applyEffect() }
                    } label: {
                        VStack(spacing: 6) {
                            Text(item.emoji).font(.title2)
                            Text(item.title).font(.caption.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(effect == item ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(effect == item ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Обрабатываю локально…").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Результат

    private func resultCard(output: VoiceProcessor.Output) -> some View {
        VStack(spacing: 12) {
            HStack {
                Label(String(format: "%.1f с", output.duration), systemImage: "waveform")
                    .font(.footnote)
                Spacer()
                Text(effect.title).font(.footnote.weight(.semibold))
            }

            HStack(spacing: 10) {
                Button {
                    play(url: output.wavURL)
                } label: {
                    Label("Прослушать", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    resetRecording()
                } label: {
                    Label("Перезаписать", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button {
                send(output: output)
            } label: {
                HStack {
                    if isSending { ProgressView().tint(.white) }
                    Label(targetChat == nil ? "Отправка доступна из чата" : "Отправить в «\(targetChat?.title ?? "")»",
                          systemImage: "paperplane.fill")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(targetChat == nil || isSending)

            sendModeHint(output: output)
        }
        .padding(16)
        .casperSurface(cornerRadius: 20)
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Как это работает", systemImage: "info.circle")
                .font(.footnote.weight(.semibold))
            Text("Обработка идёт полностью на устройстве средствами AVAudioEngine: сдвиг тона, эквалайзер и фабричные пресеты искажения. Звук никуда не загружается, внешний API не нужен.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Пока результат отправляется как аудиофайл: настоящее голосовое сообщение Telegram — это Opus в контейнере OGG, и кодировщик Opus подключается на Этапе 5 (см. docs/LIMITATIONS.md).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .casperSurface(cornerRadius: 20)
    }

    // MARK: Действия

    private func startRecording() {
        status = nil
        Task {
            guard await VoiceRecorder.requestPermission() else {
                status = "Нужен доступ к микрофону: Настройки → Casper → Микрофон."
                return
            }
            do {
                sourceURL = try recorder.start(in: AppPaths.voiceDirectory)
                output = nil
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private func finishRecording() {
        sourceURL = recorder.stop()
        applyEffect()
    }

    private func applyEffect() {
        guard let sourceURL else { return }
        isProcessing = true
        status = nil
        // Оффлайновый рендеринг короткой записи занимает десятки миллисекунд,
        // поэтому отдельный поток здесь только усложнил бы код.
        Task {
            do {
                output = try processor.process(inputURL: sourceURL,
                                               effect: effect,
                                               outputDirectory: AppPaths.voiceDirectory)
            } catch {
                status = error.localizedDescription
            }
            isProcessing = false
        }
    }

    /// Честно показывает, чем именно уйдёт запись: голосовым или файлом.
    @ViewBuilder
    private func sendModeHint(output: VoiceProcessor.Output) -> some View {
        if output.canSendAsVoiceNote {
            Label("Уйдёт как голосовое сообщение", systemImage: "waveform.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Label(output.opusFailure ?? "Кодек Opus недоступен — уйдёт как аудиофайл.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func play(url: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
        } catch {
            status = "Не удалось воспроизвести: \(error.localizedDescription)"
        }
    }

    private func resetRecording() {
        player?.stop()
        player = nil
        output = nil
        sourceURL = nil
        status = nil
    }

    private func send(output: VoiceProcessor.Output) {
        guard let chat = targetChat else { return }
        isSending = true
        Task {
            do {
                let duration = Int(output.duration.rounded())
                if let oggURL = output.oggURL {
                    // Настоящее голосовое сообщение: пузырёк с волной.
                    try await environment.telegram.sendVoiceNote(path: oggURL.path,
                                                                 duration: duration,
                                                                 waveform: output.waveform,
                                                                 to: chat.id)
                } else {
                    // Кодек Opus недоступен — уходит как аудиофайл.
                    try await environment.telegram.sendAudioFile(path: output.m4aURL.path,
                                                                 duration: duration,
                                                                 title: "Casper · \(effect.title)",
                                                                 to: chat.id)
                }
                isSending = false
                cleanUpAndDismiss()
            } catch {
                status = error.localizedDescription
                isSending = false
            }
        }
    }

    private func cleanUpAndDismiss() {
        player?.stop()
        if recorder.isRecording { recorder.cancel() }
        processor.cleanUp(directory: AppPaths.voiceDirectory)
        dismiss()
    }
}
