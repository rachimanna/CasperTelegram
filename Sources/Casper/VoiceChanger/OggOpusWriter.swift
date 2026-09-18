import Foundation

/// Собирает контейнер OGG вокруг готовых Opus-пакетов.
///
/// Зачем это нужно. Telegram считает голосовым сообщением только файл
/// «Opus внутри OGG» (RFC 7845). iOS умеет кодировать Opus сама
/// (`kAudioFormatOpus` в AudioConverter, см. `OpusStreamEncoder`), но
/// упаковать поток в OGG системными средствами нельзя: AVFoundation такой
/// контейнер не пишет. Поэтому страницы OGG формируются здесь вручную.
/// Внешние библиотеки (libogg/libopus) не нужны.
///
/// Структура файла:
/// 1. страница с пакетом `OpusHead` — флаг BOS (начало потока);
/// 2. страница с пакетом `OpusTags`;
/// 3. страницы со звуком, у последней — флаг EOS (конец потока).
final class OggOpusWriter {
    enum Failure: LocalizedError {
        case cannotCreateFile(String)

        var errorDescription: String? {
            switch self {
            case .cannotCreateFile(let path): return "Не удалось создать файл \(path)"
            }
        }
    }

    /// Сколько пакетов складываем в одну страницу. 50 пакетов по 20 мс = 1 с звука.
    private static let packetsPerPage = 50
    /// Больше 255 отрезков в странице формат не допускает.
    private static let maxSegmentsPerPage = 255

    private let handle: FileHandle
    private let url: URL
    private let serial: UInt32
    private let sampleRate: UInt32
    private let channels: UInt8
    private let preSkip: UInt16

    private var pageSequence: UInt32 = 0
    private var granulePosition: UInt64 = 0
    /// Пакеты, ещё не записанные на диск, вместе с числом кадров в каждом.
    private var pending: [(data: Data, frames: UInt32)] = []
    private var finished = false

    init(url: URL,
         sampleRate: UInt32 = 48_000,
         channels: UInt8 = 1,
         preSkip: UInt16 = 0,
         serial: UInt32 = UInt32.random(in: 1...UInt32.max)) throws {
        let manager = FileManager.default
        try? manager.removeItem(at: url)
        guard manager.createFile(atPath: url.path, contents: nil) else {
            throw Failure.cannotCreateFile(url.path)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            throw Failure.cannotCreateFile(url.path)
        }
        self.handle = handle
        self.url = url
        self.serial = serial
        self.sampleRate = sampleRate
        self.channels = channels
        self.preSkip = preSkip

        try writeHeaderPages()
    }

    // MARK: Публичный интерфейс

    /// Добавляет один Opus-пакет. `frames` — сколько звуковых кадров он содержит
    /// (960 для стандартных 20 мс при 48 кГц).
    func append(packet: Data, frames: UInt32) throws {
        guard !finished else { return }
        pending.append((packet, frames))
        // Оставляем в буфере хотя бы один пакет: он понадобится, чтобы на
        // последней странице поставить флаг EOS.
        while pending.count > Self.packetsPerPage {
            try flushPage(count: Self.packetsPerPage, endOfStream: false)
        }
        if segmentCount(of: pending) > Self.maxSegmentsPerPage, pending.count > 1 {
            try flushPage(count: pending.count - 1, endOfStream: false)
        }
    }

    /// Закрывает поток: дописывает остаток и ставит флаг конца.
    func finish() throws {
        guard !finished else { return }
        while pending.count > 1, segmentCount(of: pending) > Self.maxSegmentsPerPage {
            try flushPage(count: pending.count - 1, endOfStream: false)
        }
        // Страниц без пакетов не бывает: если буфер пуст, поток был пустым —
        // тогда пишем пустую страницу с EOS, иначе файл будет незакрытым.
        try flushPage(count: pending.count, endOfStream: true)
        finished = true
        try handle.close()
    }

    var fileURL: URL { url }
    /// Общая длительность записанного звука в кадрах.
    var totalFrames: UInt64 { granulePosition }

    // MARK: Заголовочные страницы

    private func writeHeaderPages() throws {
        var head = Data()
        head.append(contentsOf: Array("OpusHead".utf8))
        head.append(1)                      // версия формата
        head.append(channels)
        head.append(uint16: preSkip)
        head.append(uint32: sampleRate)
        head.append(uint16: 0)              // output gain
        head.append(0)                      // channel mapping family
        try writePage(packets: [(head, 0)], headerType: 0x02, granule: 0)

        var tags = Data()
        tags.append(contentsOf: Array("OpusTags".utf8))
        let vendor = Array("Casper".utf8)
        tags.append(uint32: UInt32(vendor.count))
        tags.append(contentsOf: vendor)
        tags.append(uint32: 0)              // число пользовательских комментариев
        try writePage(packets: [(tags, 0)], headerType: 0x00, granule: 0)
    }

    // MARK: Страницы со звуком

    private func flushPage(count: Int, endOfStream: Bool) throws {
        let batch = Array(pending.prefix(count))
        pending.removeFirst(min(count, pending.count))
        granulePosition += batch.reduce(UInt64(0)) { $0 + UInt64($1.frames) }
        try writePage(packets: batch,
                      headerType: endOfStream ? 0x04 : 0x00,
                      granule: granulePosition)
    }

    private func segmentCount(of packets: [(data: Data, frames: UInt32)]) -> Int {
        packets.reduce(0) { $0 + $1.data.count / 255 + 1 }
    }

    private func writePage(packets: [(data: Data, frames: UInt32)],
                           headerType: UInt8,
                           granule: UInt64) throws {
        var segments: [UInt8] = []
        var body = Data()
        for packet in packets {
            var remaining = packet.data.count
            while remaining >= 255 {
                segments.append(255)
                remaining -= 255
            }
            segments.append(UInt8(remaining))
            body.append(packet.data)
        }

        var page = Data()
        page.append(contentsOf: Array("OggS".utf8))
        page.append(0)                                  // версия
        page.append(headerType)
        page.append(uint64: granule)
        page.append(uint32: serial)
        page.append(uint32: pageSequence)
        page.append(uint32: 0)                          // место под контрольную сумму
        page.append(UInt8(segments.count))
        page.append(contentsOf: segments)
        page.append(body)

        let checksum = Self.checksum(page)
        page.replaceSubrange(22..<26, with: Self.bytes(of: checksum))

        handle.write(page)
        pageSequence &+= 1
    }

    // MARK: Контрольная сумма

    /// CRC-32 в варианте OGG: полином 0x04C11DB7, без отражения бит,
    /// начальное значение 0 и без финального XOR. Именно этим он и отличается
    /// от привычного CRC-32 из zip и PNG, поэтому таблицу строим сами.
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index) << 24
        for _ in 0..<8 {
            value = (value & 0x8000_0000) != 0 ? (value << 1) ^ 0x04c1_1db7 : value << 1
        }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0
        for byte in data {
            let index = Int(((crc >> 24) ^ UInt32(byte)) & 0xFF)
            crc = (crc << 8) ^ table[index]
        }
        return crc
    }

    private static func bytes(of value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF),
         UInt8((value >> 8) & 0xFF),
         UInt8((value >> 16) & 0xFF),
         UInt8((value >> 24) & 0xFF)]
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func append(uint32 value: UInt32) {
        for shift in stride(from: 0, through: 24, by: 8) {
            append(UInt8((value >> UInt32(shift)) & 0xFF))
        }
    }

    mutating func append(uint64 value: UInt64) {
        for shift in stride(from: 0, through: 56, by: 8) {
            append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
    }
}
