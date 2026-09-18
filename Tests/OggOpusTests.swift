import AVFoundation
import XCTest
@testable import CasperTelegram

/// Проверки настоящих голосовых сообщений: кодек Opus, контейнер OGG и волна.
final class OggOpusTests: XCTestCase {

    // MARK: Контрольная сумма

    /// Эталонные значения посчитаны независимой реализацией
    /// (полином 0x04C11DB7, без отражения бит, начальное значение 0).
    func testChecksumMatchesReferenceValues() {
        XCTAssertEqual(OggOpusWriter.checksum(Data()), 0)
        XCTAssertEqual(OggOpusWriter.checksum(Data("OggS".utf8)), 0x5fb0_a94f)
        XCTAssertEqual(OggOpusWriter.checksum(Data("123456789".utf8)), 0x89a1_897f)
    }

    // MARK: Волна громкости

    func testWaveformPackingIsFiveBitsPerSample() {
        let values: [UInt8] = (0..<100).map { UInt8($0 % 32) }
        let packed = TelegramWaveform.pack(values: values)
        XCTAssertEqual(packed.count, 63, "100 значений по 5 бит — это 63 байта")
        XCTAssertEqual(TelegramWaveform.unpack(packed), values)
    }

    func testWaveformClampsAndScalesPeaks() {
        let silence = TelegramWaveform.unpack(TelegramWaveform.encode(peaks: [Float](repeating: 0, count: 500)))
        XCTAssertEqual(silence.max(), 0)

        let loud = TelegramWaveform.unpack(TelegramWaveform.encode(peaks: [Float](repeating: 1, count: 500)))
        XCTAssertEqual(loud.min(), 31, "громкая запись должна давать максимум 31")

        let empty = TelegramWaveform.encode(peaks: [])
        XCTAssertEqual(empty.count, 63, "даже без данных волна должна быть нужного размера")
    }

    func testWaveformFollowsLoudnessShape() {
        // Первая половина тихая, вторая громкая — волна обязана это повторить.
        let peaks = [Float](repeating: 0.05, count: 200) + [Float](repeating: 1.0, count: 200)
        let values = TelegramWaveform.unpack(TelegramWaveform.encode(peaks: peaks))
        let firstHalf = values[0..<50].map(Int.init).reduce(0, +)
        let secondHalf = values[50..<100].map(Int.init).reduce(0, +)
        XCTAssertLessThan(firstHalf, secondHalf)
    }

    // MARK: Контейнер OGG

    func testWriterProducesValidPageStructure() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("casper-test-\(UUID().uuidString).ogg")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try OggOpusWriter(url: url, serial: 0x1234_5678)
        // 120 пакетов-пустышек, чтобы страниц получилось несколько.
        for index in 0..<120 {
            try writer.append(packet: Data([UInt8(index % 251), 0x01, 0x02]), frames: 960)
        }
        try writer.finish()

        let pages = try OggPage.parse(Data(contentsOf: url))
        XCTAssertGreaterThan(pages.count, 3, "ожидались две заголовочные страницы и несколько со звуком")

        // Заголовки.
        XCTAssertEqual(pages[0].headerType, 0x02, "первая страница должна быть началом потока")
        XCTAssertTrue(pages[0].body.starts(with: Array("OpusHead".utf8)))
        XCTAssertEqual(pages[0].granule, 0)
        XCTAssertTrue(pages[1].body.starts(with: Array("OpusTags".utf8)))

        // Служебные поля.
        for (index, page) in pages.enumerated() {
            XCTAssertEqual(page.serial, 0x1234_5678)
            XCTAssertEqual(page.sequence, UInt32(index), "номера страниц должны идти по порядку")
            XCTAssertTrue(page.checksumIsValid, "страница \(index): контрольная сумма не сходится")
        }

        // Конец потока и итоговая длительность.
        XCTAssertEqual(pages.last?.headerType, 0x04, "последняя страница должна закрывать поток")
        XCTAssertEqual(pages.last?.granule, 120 * 960, "granule должен равняться числу кадров")
        XCTAssertEqual(writer.totalFrames, 120 * 960)
    }

    func testWriterSplitsLongPacketsIntoSegments() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("casper-test-\(UUID().uuidString).ogg")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try OggOpusWriter(url: url)
        // 600 байт — это 2 отрезка по 255 и один на остаток.
        try writer.append(packet: Data(repeating: 0xAB, count: 600), frames: 960)
        try writer.finish()

        let pages = try OggPage.parse(Data(contentsOf: url))
        let audio = try XCTUnwrap(pages.last)
        XCTAssertEqual(audio.segments, [255, 255, 90])
        XCTAssertEqual(audio.body.count, 600)
    }

    // MARK: Кодек Opus

    func testEncodesSineWaveIntoPlayableVoiceNote() throws {
        let encoder: OpusStreamEncoder
        do {
            encoder = try OpusStreamEncoder()
        } catch {
            throw XCTSkip("Кодек Opus недоступен в этой среде: \(error.localizedDescription)")
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("casper-test-\(UUID().uuidString).ogg")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try OggOpusWriter(url: url)

        // Одна секунда тона 440 Гц при 48 кГц.
        let sampleRate = 48_000
        var samples = [Int16](repeating: 0, count: sampleRate)
        for index in 0..<sampleRate {
            let phase = 2 * Double.pi * 440 * Double(index) / Double(sampleRate)
            samples[index] = Int16(sin(phase) * 12_000)
        }

        var packetCount = 0
        var firstPacket: Data?
        // Подаём порциями по 4096 кадров — как это делает VoiceProcessor.
        for start in stride(from: 0, to: samples.count, by: 4_096) {
            let chunk = Array(samples[start..<min(start + 4_096, samples.count)])
            for packet in try encoder.push(chunk) {
                XCTAssertFalse(packet.isEmpty, "пустых пакетов быть не должно")
                if firstPacket == nil { firstPacket = packet }
                try writer.append(packet: packet, frames: OpusStreamEncoder.framesPerPacket)
                packetCount += 1
            }
        }
        for packet in try encoder.finish() {
            try writer.append(packet: packet, frames: OpusStreamEncoder.framesPerPacket)
            packetCount += 1
        }
        try writer.finish()

        // 1 секунда = 50 пакетов по 20 мс. Допускаем небольшой разбег на хвост.
        XCTAssertGreaterThanOrEqual(packetCount, 48)
        XCTAssertLessThanOrEqual(packetCount, 53)

        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 1_000, "секунда речи не может весить так мало")
        let pages = try OggPage.parse(data)
        for (index, page) in pages.enumerated() {
            XCTAssertTrue(page.checksumIsValid, "страница \(index): контрольная сумма не сходится")
        }
        let frames = try XCTUnwrap(pages.last?.granule)
        XCTAssertEqual(Double(frames) / 48_000, 1.0, accuracy: 0.05, "длительность должна выйти около секунды")

        // Главная проверка: первый байт пакета Opus (TOC) должен описывать
        // ровно то, что ждёт Telegram — моно и один кадр в пакете.
        let toc = try XCTUnwrap(firstPacket?.first)
        XCTAssertEqual(toc & 0x03, 0, "в пакете должен быть один кадр")
        XCTAssertEqual(toc & 0x04, 0, "поток должен быть моно")
        XCTAssertGreaterThan(toc >> 3, 0, "поле конфигурации Opus не заполнено")
    }

    func testProcessorProducesVoiceNoteFromRecording() throws {
        // Готовим «запись»: короткий тон в файле, как его оставил бы диктофон.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("casper-voice-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let inputURL = directory.appendingPathComponent("input.wav")
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                 sampleRate: 48_000,
                                                 channels: 1,
                                                 interleaved: false))
        let file = try AVAudioFile(forWriting: inputURL,
                                   settings: [AVFormatIDKey: kAudioFormatLinearPCM,
                                              AVSampleRateKey: 48_000,
                                              AVNumberOfChannelsKey: 1,
                                              AVLinearPCMBitDepthKey: 16,
                                              AVLinearPCMIsFloatKey: false,
                                              AVLinearPCMIsBigEndianKey: false,
                                              AVLinearPCMIsNonInterleaved: false])
        let frames: AVAudioFrameCount = 48_000
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<Int(frames) {
            channel[index] = Float(sin(2 * Double.pi * 220 * Double(index) / 48_000)) * 0.5
        }
        try file.write(from: buffer)

        let output = try VoiceProcessor().process(inputURL: inputURL,
                                                  effect: VoiceEffect.none,
                                                  outputDirectory: directory)

        XCTAssertTrue(FileManager.default.fileExists(atPath: output.m4aURL.path))
        XCTAssertEqual(output.duration, 1.0, accuracy: 0.3)

        guard let oggURL = output.oggURL else {
            throw XCTSkip("Opus недоступен: \(output.opusFailure ?? "причина не указана")")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: oggURL.path))
        XCTAssertEqual(output.waveform?.count, 63)
        XCTAssertTrue(output.canSendAsVoiceNote)

        let pages = try OggPage.parse(Data(contentsOf: oggURL))
        XCTAssertTrue(pages.allSatisfy(\.checksumIsValid))
        XCTAssertTrue(pages[0].body.starts(with: Array("OpusHead".utf8)))
    }
}

/// Минимальный разборщик OGG — нужен только тестам, чтобы проверять
/// то, что записал `OggOpusWriter`, независимой реализацией.
struct OggPage {
    var headerType: UInt8
    var granule: UInt64
    var serial: UInt32
    var sequence: UInt32
    var storedChecksum: UInt32
    var segments: [UInt8]
    var body: [UInt8]
    var checksumIsValid: Bool

    enum Failure: Error { case malformed(String) }

    static func parse(_ data: Data) throws -> [OggPage] {
        var pages: [OggPage] = []
        var bytes = [UInt8](data)
        var cursor = 0

        while cursor < bytes.count {
            guard cursor + 27 <= bytes.count else {
                throw Failure.malformed("обрезанный заголовок на позиции \(cursor)")
            }
            guard Array(bytes[cursor..<(cursor + 4)]) == Array("OggS".utf8) else {
                throw Failure.malformed("нет метки OggS на позиции \(cursor)")
            }
            let segmentCount = Int(bytes[cursor + 26])
            let headerSize = 27 + segmentCount
            guard cursor + headerSize <= bytes.count else {
                throw Failure.malformed("обрезанная таблица отрезков")
            }
            let segments = Array(bytes[(cursor + 27)..<(cursor + headerSize)])
            let bodySize = segments.reduce(0) { $0 + Int($1) }
            guard cursor + headerSize + bodySize <= bytes.count else {
                throw Failure.malformed("обрезанное тело страницы")
            }

            let stored = readUInt32(bytes, cursor + 22)
            // Сумма считается по странице с обнулённым полем суммы.
            var copy = Array(bytes[cursor..<(cursor + headerSize + bodySize)])
            for offset in 22..<26 { copy[offset] = 0 }
            let computed = OggOpusWriter.checksum(Data(copy))

            pages.append(OggPage(headerType: bytes[cursor + 5],
                                 granule: readUInt64(bytes, cursor + 6),
                                 serial: readUInt32(bytes, cursor + 14),
                                 sequence: readUInt32(bytes, cursor + 18),
                                 storedChecksum: stored,
                                 segments: segments,
                                 body: Array(bytes[(cursor + headerSize)..<(cursor + headerSize + bodySize)]),
                                 checksumIsValid: stored == computed))
            cursor += headerSize + bodySize
        }
        return pages
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << UInt32(8 * $1) }
    }

    private static func readUInt64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[offset + $1]) << UInt64(8 * $1) }
    }
}
