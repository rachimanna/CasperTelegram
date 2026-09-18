import AVFoundation

/// Оффлайновая обработка записанного голоса.
///
/// Результат пишется сразу в трёх форматах:
/// * `.ogg` — Opus в контейнере OGG. Это и есть настоящее голосовое сообщение
///   Telegram: пузырёк с волной, а не вложенный файл. Кодирует сама iOS
///   (`OpusStreamEncoder`), контейнер собирает `OggOpusWriter`.
/// * `.m4a` — AAC. Нужен для локального прослушивания (AVAudioPlayer не играет
///   Opus) и как запасной путь отправки, если кодек Opus вдруг недоступен.
/// * `.wav` — PCM 48 кГц моно, для отладки и повторной обработки.
final class VoiceProcessor {
    struct Output: Equatable {
        var wavURL: URL
        var m4aURL: URL
        /// nil, если кодек Opus недоступен — тогда отправка пойдёт как аудиофайл.
        var oggURL: URL?
        /// Волна громкости для пузырька, 63 байта. nil вместе с `oggURL`.
        var waveform: Data?
        var duration: TimeInterval
        /// Почему не получилось сделать голосовое, если не получилось.
        var opusFailure: String?

        /// true — можно отправить как настоящее голосовое сообщение.
        var canSendAsVoiceNote: Bool { oggURL != nil }
    }

    enum Failure: LocalizedError {
        case unreadableInput
        case renderFailed(String)

        var errorDescription: String? {
            switch self {
            case .unreadableInput: return "Не удалось прочитать запись."
            case .renderFailed(let reason): return "Обработка не удалась: \(reason)"
            }
        }
    }

    static let sampleRate: Double = 48_000
    /// Одно значение волны на 10 мс звука.
    private static let framesPerPeak = 480

    func process(inputURL: URL, effect: VoiceEffect, outputDirectory: URL) throws -> Output {
        guard let input = try? AVAudioFile(forReading: inputURL) else {
            throw Failure.unreadableInput
        }

        let inputFormat = input.processingFormat
        let sourceDuration = Double(input.length) / inputFormat.sampleRate

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let pitch = AVAudioUnitTimePitch()
        let equalizer = AVAudioUnitEQ(numberOfBands: 2)
        let distortion = AVAudioUnitDistortion()

        pitch.pitch = effect.pitchCents
        pitch.rate = 1.0

        let low = equalizer.bands[0]
        low.filterType = .lowShelf
        low.frequency = 120
        low.gain = effect.lowShelfGain
        low.bypass = effect.lowShelfGain == 0

        let high = equalizer.bands[1]
        high.filterType = .highShelf
        high.frequency = 6_000
        high.gain = effect.highShelfGain
        high.bypass = effect.highShelfGain == 0

        if let preset = effect.distortionPreset {
            distortion.loadFactoryPreset(preset)
            distortion.wetDryMix = effect.distortionMix
        } else {
            distortion.wetDryMix = 0
        }

        engine.attach(player)
        engine.attach(pitch)
        engine.attach(equalizer)
        engine.attach(distortion)

        engine.connect(player, to: pitch, format: inputFormat)
        engine.connect(pitch, to: equalizer, format: inputFormat)
        engine.connect(equalizer, to: distortion, format: inputFormat)
        engine.connect(distortion, to: engine.mainMixerNode, format: inputFormat)

        guard let renderFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: Self.sampleRate,
                                               channels: 1,
                                               interleaved: false) else {
            throw Failure.renderFailed("не удалось создать формат рендеринга")
        }

        try engine.enableManualRenderingMode(.offline,
                                             format: renderFormat,
                                             maximumFrameCount: 4_096)
        player.scheduleFile(input, at: nil)
        try engine.start()
        player.play()

        let stamp = Int(Date().timeIntervalSince1970)
        let wavURL = outputDirectory.appendingPathComponent("casper-voice-\(stamp).wav")
        let m4aURL = outputDirectory.appendingPathComponent("casper-voice-\(stamp).m4a")
        let oggURL = outputDirectory.appendingPathComponent("casper-voice-\(stamp).ogg")
        try? FileManager.default.removeItem(at: wavURL)
        try? FileManager.default.removeItem(at: m4aURL)
        try? FileManager.default.removeItem(at: oggURL)

        let wavSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let m4aSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000
        ]

        let wavFile = try AVAudioFile(forWriting: wavURL, settings: wavSettings)
        let m4aFile = try AVAudioFile(forWriting: m4aURL, settings: m4aSettings)

        // Голосовое сообщение — вещь желательная, но не обязательная: если кодек
        // Opus в системе недоступен, обработка всё равно должна дойти до конца.
        var opus: OpusPipeline?
        var opusFailure: String?
        do {
            opus = try OpusPipeline(url: oggURL)
        } catch {
            opusFailure = error.localizedDescription
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                            frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw Failure.renderFailed("не удалось выделить буфер")
        }

        let targetFrames = AVAudioFramePosition((sourceDuration + effect.tailSeconds) * Self.sampleRate)
        var written: AVAudioFramePosition = 0
        var peaks: [Float] = []

        while written < targetFrames {
            let remaining = targetFrames - written
            let frameCount = AVAudioFrameCount(min(Int64(buffer.frameCapacity), remaining))
            let status = try engine.renderOffline(frameCount, to: buffer)

            switch status {
            case .success:
                try wavFile.write(from: buffer)
                try m4aFile.write(from: buffer)
                if opus != nil {
                    let samples = Self.integerSamples(from: buffer, appendingPeaksTo: &peaks)
                    do {
                        try opus?.append(samples: samples)
                    } catch {
                        opusFailure = error.localizedDescription
                        opus = nil
                    }
                }
                written += AVAudioFramePosition(buffer.frameLength)
            case .insufficientDataFromInputNode:
                // Файл доигран — на этом останавливаемся.
                written = targetFrames
            case .cannotDoInCurrentContext:
                continue
            case .error:
                throw Failure.renderFailed("ошибка движка на кадре \(written)")
            @unknown default:
                throw Failure.renderFailed("неизвестный статус рендеринга")
            }
        }

        player.stop()
        engine.stop()
        engine.disableManualRenderingMode()

        var finalOggURL: URL?
        var waveform: Data?
        if let opus {
            do {
                try opus.finish()
                finalOggURL = oggURL
                waveform = TelegramWaveform.encode(peaks: peaks)
            } catch {
                opusFailure = error.localizedDescription
                try? FileManager.default.removeItem(at: oggURL)
            }
        }

        let duration = Double(written) / Self.sampleRate
        return Output(wavURL: wavURL,
                      m4aURL: m4aURL,
                      oggURL: finalOggURL,
                      waveform: waveform,
                      duration: duration,
                      opusFailure: opusFailure)
    }

    /// Переводит кадры из Float32 в Int16 (этого ждёт кодек) и попутно
    /// снимает пики громкости для волны.
    private static func integerSamples(from buffer: AVAudioPCMBuffer,
                                       appendingPeaksTo peaks: inout [Float]) -> [Int16] {
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        let count = Int(buffer.frameLength)
        var samples = [Int16](repeating: 0, count: count)
        var peak: Float = 0
        var sinceLastPeak = 0

        for index in 0..<count {
            let value = channel[index]
            let clamped = min(max(value, -1), 1)
            samples[index] = Int16(clamped * 32_767)
            peak = max(peak, abs(clamped))
            sinceLastPeak += 1
            if sinceLastPeak == framesPerPeak {
                peaks.append(peak)
                peak = 0
                sinceLastPeak = 0
            }
        }
        if sinceLastPeak > 0 { peaks.append(peak) }
        return samples
    }

    /// Убирает старые временные файлы, чтобы папка не разрасталась.
    func cleanUp(directory: URL, keepNewest count: Int = 6) {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(at: directory,
                                                           includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let sorted = files.sorted { left, right in
            let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return leftDate > rightDate
        }
        for file in sorted.dropFirst(count) {
            try? manager.removeItem(at: file)
        }
    }
}

/// Связка «кодек + контейнер»: принимает PCM, пишет готовый OGG на диск.
final class OpusPipeline {
    private let encoder: OpusStreamEncoder
    private let writer: OggOpusWriter

    init(url: URL) throws {
        encoder = try OpusStreamEncoder()
        writer = try OggOpusWriter(url: url)
    }

    func append(samples: [Int16]) throws {
        for packet in try encoder.push(samples) {
            try writer.append(packet: packet, frames: OpusStreamEncoder.framesPerPacket)
        }
    }

    func finish() throws {
        for packet in try encoder.finish() {
            try writer.append(packet: packet, frames: OpusStreamEncoder.framesPerPacket)
        }
        try writer.finish()
    }
}
