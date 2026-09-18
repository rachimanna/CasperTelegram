import AVFoundation

/// Эффекты Voice Changer.
///
/// Всё считается локально на устройстве стандартными узлами AVAudioEngine:
/// сдвиг тона (AVAudioUnitTimePitch), эквалайзер (AVAudioUnitEQ) и
/// фабричные пресеты искажения (AVAudioUnitDistortion).
/// Никакие внешние сервисы и никакие аудиоданные из приложения не уходят.
enum VoiceEffect: String, Codable, CaseIterable, Identifiable {
    case none
    case robot
    case deep
    case alien
    case electronic
    case bass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Обычный"
        case .robot: return "Robot"
        case .deep: return "Deep"
        case .alien: return "Alien"
        case .electronic: return "Electronic"
        case .bass: return "Bass"
        }
    }

    var emoji: String {
        switch self {
        case .none: return "🎙"
        case .robot: return "🤖"
        case .deep: return "👹"
        case .alien: return "👽"
        case .electronic: return "⚡"
        case .bass: return "🔊"
        }
    }

    /// Сдвиг тона в центах: 100 центов = полутон. Допустимый диапазон -2400…2400.
    var pitchCents: Float {
        switch self {
        case .none: return 0
        case .robot: return -180
        case .deep: return -620
        case .alien: return 760
        case .electronic: return -120
        case .bass: return -360
        }
    }

    var distortionPreset: AVAudioUnitDistortionPreset? {
        switch self {
        case .none: return nil
        case .robot: return .speechCosmicInterference
        case .deep: return nil
        case .alien: return .speechAlienChatter
        case .electronic: return .multiDecimated2
        case .bass: return nil
        }
    }

    /// Насколько сильно подмешивается искажение, 0…100.
    var distortionMix: Float {
        switch self {
        case .robot: return 42
        case .alien: return 30
        case .electronic: return 55
        default: return 0
        }
    }

    /// Усиление низких частот (полка 120 Гц), дБ.
    var lowShelfGain: Float {
        switch self {
        case .deep: return 6
        case .bass: return 10
        default: return 0
        }
    }

    /// Усиление верхних частот (полка 6 кГц), дБ.
    var highShelfGain: Float {
        switch self {
        case .deep: return -3
        case .bass: return -5
        case .alien: return 3
        default: return 0
        }
    }

    /// Запас на «хвост» эффекта (эхо, реверберация), секунды.
    var tailSeconds: Double {
        switch self {
        case .robot, .alien, .electronic: return 0.4
        default: return 0.1
        }
    }
}
