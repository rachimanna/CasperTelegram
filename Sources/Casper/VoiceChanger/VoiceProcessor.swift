import AVFoundation

/// Оффлайновая обработка записанного голоса.
///
/// Результат пишется сразу в двух форматах:
/// * `.wav` — PCM 48 кГц моно. Нужен для прослушивания и в будущем для
///   кодирования в Opus (настоящее голосовое сообщение Telegram).
/// * `.m4a` — AAC. Им можно отправить обработанный звук уже сейчас,
///   но Telegram покажет его как аудиофайл, а не как голосовое сообщение.
///   Подробности и план — в docs/LIMITATIONS.md.
final class VoiceProcessor {
    struct Output: Equatable {
        var wavURL: URL
        var m4aURL: URL
        var duration: TimeInterval
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
        try? FileManager.default.removeItem(at: wavURL)
        try? FileManager.default.removeItem(at: m4aURL)

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

        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                            frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw Failure.renderFailed("не удалось выделить буфер")
        }

        let targetFrames = AVAudioFramePosition((sourceDuration + effect.tailSeconds) * Self.sampleRate)
        var written: AVAudioFramePosition = 0

        while written < targetFrames {
            let remaining = targetFrames - written
            let frameCount = AVAudioFrameCount(min(Int64(buffer.frameCapacity), remaining))
            let status = try engine.renderOffline(frameCount, to: buffer)

            switch status {
            case .success:
                try wavFile.write(from: buffer)
                try m4aFile.write(from: buffer)
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

        let duration = Double(written) / Self.sampleRate
        return Output(wavURL: wavURL, m4aURL: m4aURL, duration: duration)
    }

    /// Убирает старые временные файлы, чтобы папка не разрасталась.
    func cleanUp(directory: URL, keepNewest count: Int = 4) {
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
