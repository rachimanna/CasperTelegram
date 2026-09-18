import AudioToolbox
import Foundation

/// Кодирует PCM в Opus средствами самой iOS.
///
/// В CoreAudio есть кодек `kAudioFormatOpus` — о нём мало кто знает, потому что
/// AVFoundation его не показывает и в OGG не пишет. Но AudioConverter выдаёт
/// готовые Opus-пакеты, а контейнер собирает `OggOpusWriter`. Благодаря этому
/// настоящие голосовые сообщения работают без libopus и без внешних зависимостей.
///
/// Данные подаются порциями (`push`), поэтому вся запись не держится в памяти.
final class OpusStreamEncoder {
    enum Failure: LocalizedError {
        case unavailable(OSStatus)
        case encodingFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unavailable(let code):
                return "Кодек Opus недоступен (код \(code)). Голосовое будет отправлено как аудиофайл."
            case .encodingFailed(let code):
                return "Ошибка кодирования Opus (код \(code))."
            }
        }
    }

    /// 960 кадров при 48 кГц — это 20 мс, стандартный размер кадра Opus
    /// и именно то, что использует сам Telegram.
    static let framesPerPacket: UInt32 = 960
    private static let maxPacketBytes = 4_000

    private let converter: AudioConverterRef
    private let source = Source()
    private let sourcePointer: UnsafeMutableRawPointer

    init(sampleRate: Double = 48_000, channels: UInt32 = 1, bitRate: UInt32 = 32_000) throws {
        var input = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2 * channels,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2 * channels,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var output = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatOpus,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: Self.framesPerPacket,
            mBytesPerFrame: 0,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 0,
            mReserved: 0
        )

        var created: AudioConverterRef?
        let status = AudioConverterNew(&input, &output, &created)
        guard status == noErr, let converter = created else {
            throw Failure.unavailable(status)
        }
        self.converter = converter

        var rate = bitRate
        // Битрейт — пожелание, а не требование: если кодек его не примет,
        // он выберет свой, и это не повод прерывать запись.
        AudioConverterSetProperty(converter,
                                  kAudioConverterEncodeBitRate,
                                  UInt32(MemoryLayout<UInt32>.size),
                                  &rate)

        sourcePointer = Unmanaged.passUnretained(source).toOpaque()
    }

    deinit {
        AudioConverterDispose(converter)
        source.release()
    }

    // MARK: Кодирование

    /// Добавляет очередную порцию PCM и возвращает готовые пакеты.
    func push(_ samples: [Int16]) throws -> [Data] {
        source.append(samples)
        return try drain(requireFullFrame: true)
    }

    /// Дописывает хвост: добирает последний кадр нулями и отдаёт остаток.
    func finish() throws -> [Data] {
        let tail = source.remaining % Int(Self.framesPerPacket)
        if tail != 0 {
            source.append([Int16](repeating: 0, count: Int(Self.framesPerPacket) - tail))
        }
        return try drain(requireFullFrame: true)
    }

    private func drain(requireFullFrame: Bool) throws -> [Data] {
        var packets: [Data] = []
        while true {
            if requireFullFrame, source.remaining < Int(Self.framesPerPacket) { break }

            source.starved = false
            var packetCount: UInt32 = 1
            var description = AudioStreamPacketDescription()
            var buffer = [UInt8](repeating: 0, count: Self.maxPacketBytes)
            var status: OSStatus = noErr
            var produced = 0

            buffer.withUnsafeMutableBytes { raw in
                var list = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(mNumberChannels: 1,
                                          mDataByteSize: UInt32(Self.maxPacketBytes),
                                          mData: raw.baseAddress)
                )
                status = AudioConverterFillComplexBuffer(converter,
                                                         Self.inputProc,
                                                         sourcePointer,
                                                         &packetCount,
                                                         &list,
                                                         &description)
                produced = Int(list.mBuffers.mDataByteSize)
            }

            guard status == noErr else { throw Failure.encodingFailed(status) }
            guard packetCount > 0 else { break }

            let size = description.mDataByteSize > 0 ? Int(description.mDataByteSize) : produced
            guard size > 0 else { break }
            packets.append(Data(buffer[0..<min(size, Self.maxPacketBytes)]))

            if source.starved, source.remaining == 0 { break }
        }
        return packets
    }

    /// Отдаёт кодеку накопленный PCM. Когда данных не осталось, сообщает об этом
    /// нулём пакетов — AudioConverter понимает это как «пока всё» и не ошибается.
    private static let inputProc: AudioConverterComplexInputDataProc = {
        _, packetCount, data, packetDescriptions, userData in
        guard let userData else {
            packetCount.pointee = 0
            return noErr
        }
        let source = Unmanaged<Source>.fromOpaque(userData).takeUnretainedValue()
        packetDescriptions?.pointee = nil

        let served = source.serve(upTo: Int(packetCount.pointee))
        guard served > 0 else {
            source.starved = true
            packetCount.pointee = 0
            data.pointee.mNumberBuffers = 1
            data.pointee.mBuffers.mDataByteSize = 0
            data.pointee.mBuffers.mData = nil
            return noErr
        }

        packetCount.pointee = UInt32(served)
        data.pointee.mNumberBuffers = 1
        data.pointee.mBuffers.mNumberChannels = 1
        data.pointee.mBuffers.mDataByteSize = UInt32(served * 2)
        data.pointee.mBuffers.mData = UnsafeMutableRawPointer(source.scratch.baseAddress)
        return noErr
    }
}

/// Очередь PCM между нашим кодом и обратным вызовом AudioConverter.
/// Отдельный класс нужен потому, что обратный вызов — это C-функция:
/// в неё можно передать только указатель, а не замыкание с захватом.
private final class Source {
    private static let scratchCapacity = 16_384

    let scratch: UnsafeMutableBufferPointer<Int16>
    private var queue: [Int16] = []
    private var offset = 0
    var starved = false

    init() {
        scratch = UnsafeMutableBufferPointer<Int16>.allocate(capacity: Self.scratchCapacity)
    }

    func release() {
        scratch.deallocate()
    }

    var remaining: Int { queue.count - offset }

    func append(_ samples: [Int16]) {
        if offset > 0 {
            queue.removeFirst(offset)
            offset = 0
        }
        queue.append(contentsOf: samples)
    }

    /// Копирует во временный буфер до `limit` кадров и возвращает их число.
    /// Буфер живёт вместе с объектом, поэтому указатель остаётся
    /// действительным до следующего вызова — как того и требует AudioConverter.
    func serve(upTo limit: Int) -> Int {
        let count = min(limit, remaining, Self.scratchCapacity)
        guard count > 0 else { return 0 }
        for index in 0..<count {
            scratch[index] = queue[offset + index]
        }
        offset += count
        return count
    }
}
