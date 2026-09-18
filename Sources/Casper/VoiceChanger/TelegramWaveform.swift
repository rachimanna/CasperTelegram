import Foundation

/// Волна громкости для голосового сообщения — та самая «гребёнка» в пузырьке.
///
/// Telegram хранит её очень плотно: 100 значений по 5 бит (то есть 0…31),
/// упакованных подряд, младшими битами вперёд. Итого 63 байта на сообщение.
/// Если волну не передать, у получателя пузырёк будет плоским.
enum TelegramWaveform {
    /// Столько значений ожидают клиенты Telegram.
    static let sampleCount = 100
    private static let maxValue = 31

    /// Собирает волну из пиков громкости, снятых во время обработки звука.
    /// `peaks` — любое количество значений 0…1; они усредняются до 100 точек.
    static func encode(peaks: [Float]) -> Data {
        guard !peaks.isEmpty else {
            return pack(values: [UInt8](repeating: 0, count: sampleCount))
        }

        var values = [UInt8](repeating: 0, count: sampleCount)
        for index in 0..<sampleCount {
            let start = index * peaks.count / sampleCount
            let end = max(start + 1, (index + 1) * peaks.count / sampleCount)
            var peak: Float = 0
            for position in start..<min(end, peaks.count) {
                peak = max(peak, peaks[position])
            }
            // Корень сжимает динамику: тихие части перестают выглядеть пустыми.
            let scaled = sqrt(min(max(peak, 0), 1)) * Float(maxValue)
            values[index] = UInt8(min(Float(maxValue), scaled.rounded()))
        }
        return pack(values: values)
    }

    /// Упаковывает значения по 5 бит, младшими битами вперёд.
    static func pack(values: [UInt8]) -> Data {
        let totalBits = values.count * 5
        var bytes = [UInt8](repeating: 0, count: (totalBits + 7) / 8)
        for (index, rawValue) in values.enumerated() {
            let value = UInt32(min(rawValue, UInt8(maxValue)))
            for bit in 0..<5 where (value >> UInt32(bit)) & 1 == 1 {
                let position = index * 5 + bit
                bytes[position / 8] |= UInt8(1 << (position % 8))
            }
        }
        return Data(bytes)
    }

    /// Обратная распаковка — нужна тестам и отладке.
    static func unpack(_ data: Data, count: Int = sampleCount) -> [UInt8] {
        let bytes = [UInt8](data)
        return (0..<count).map { index in
            var value: UInt8 = 0
            for bit in 0..<5 {
                let position = index * 5 + bit
                let byteIndex = position / 8
                guard byteIndex < bytes.count else { continue }
                if (bytes[byteIndex] >> (position % 8)) & 1 == 1 {
                    value |= UInt8(1 << bit)
                }
            }
            return value
        }
    }
}
