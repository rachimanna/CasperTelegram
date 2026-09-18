import XCTest
@testable import CasperTelegram

final class VoiceEffectTests: XCTestCase {

    func testPitchStaysInsideSupportedRange() {
        // AVAudioUnitTimePitch принимает -2400…2400 центов.
        for effect in VoiceEffect.allCases {
            XCTAssertTrue((-2400...2400).contains(effect.pitchCents), "\(effect.title)")
        }
    }

    func testNeutralEffectDoesNotChangeAnything() {
        let effect = VoiceEffect.none
        XCTAssertEqual(effect.pitchCents, 0)
        XCTAssertNil(effect.distortionPreset)
        XCTAssertEqual(effect.distortionMix, 0)
        XCTAssertEqual(effect.lowShelfGain, 0)
    }

    func testEveryEffectExceptNeutralChangesSomething() {
        for effect in VoiceEffect.allCases where effect != .none {
            let changesSomething = effect.pitchCents != 0
                || effect.distortionPreset != nil
                || effect.lowShelfGain != 0
                || effect.highShelfGain != 0
            XCTAssertTrue(changesSomething, "\(effect.title) ничего не меняет")
        }
    }

    func testDistortionMixIsValidPercentage() {
        for effect in VoiceEffect.allCases {
            XCTAssertTrue((0...100).contains(effect.distortionMix), "\(effect.title)")
            if effect.distortionPreset == nil {
                XCTAssertEqual(effect.distortionMix, 0, "\(effect.title)")
            }
        }
    }

    func testTitlesAndEmojiAreUnique() {
        let titles = Set(VoiceEffect.allCases.map(\.title))
        let emoji = Set(VoiceEffect.allCases.map(\.emoji))
        XCTAssertEqual(titles.count, VoiceEffect.allCases.count)
        XCTAssertEqual(emoji.count, VoiceEffect.allCases.count)
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(VoiceEffect.alien)
        XCTAssertEqual(try JSONDecoder().decode(VoiceEffect.self, from: data), .alien)
    }
}
