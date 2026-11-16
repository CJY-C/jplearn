import XCTest
@testable import LearningCore

final class SpeechVoiceSelectionTests: XCTestCase {
    private let basic = SpeechVoiceOption(id: "ja-basic", name: "A", language: "ja-JP", quality: .standard)
    private let enhanced = SpeechVoiceOption(id: "ja-enhanced", name: "Z", language: "ja-JP", quality: .enhanced)
    private let premium = SpeechVoiceOption(id: "ja-premium", name: "P", language: "ja-JP", quality: .premium)

    func testAutomaticChoiceUsesTheBestAvailableJapaneseQuality() {
        XCTAssertEqual(SpeechVoiceSelection.preferred([basic, enhanced]), enhanced)
        XCTAssertEqual(SpeechVoiceSelection.preferred([enhanced, basic, premium]), premium)
        XCTAssertEqual(SpeechVoiceSelection.preferred([basic]), basic)
    }
    func testExplicitBasicVoiceIsRespectedAfterAnEnhancedDownload() {
        XCTAssertEqual(SpeechVoiceSelection.preferred([enhanced, basic, premium], selectedID: basic.id), basic)
    }
    func testDeletedOrNonJapanesePreferenceFallsBackToJapanese() {
        let english = SpeechVoiceOption(id: "en-premium", name: "English", language: "en-US", quality: .premium)
        XCTAssertEqual(SpeechVoiceSelection.preferred([english, basic, enhanced], selectedID: "deleted"), enhanced)
        XCTAssertEqual(SpeechVoiceSelection.preferred([english, basic, enhanced], selectedID: english.id), enhanced)
    }
    func testJapaneseLanguageCodesAreValidatedRatherThanLoosePrefixes() {
        let plain = SpeechVoiceOption(id: "plain", name: "Plain", language: "ja", quality: .standard)
        let normalized = SpeechVoiceOption(id: "normalized", name: "Japan", language: "JA_jp", quality: .enhanced)
        let unrelated = SpeechVoiceOption(id: "unrelated", name: "Other", language: "jam", quality: .premium)
        XCTAssertEqual(SpeechVoiceSelection.ordered([plain, unrelated, normalized]), [normalized, plain])
    }
    func testNoJapaneseVoiceDoesNotSelectAnotherLanguage() {
        let english = SpeechVoiceOption(id: "en", name: "English", language: "en-US", quality: .standard)
        XCTAssertNil(SpeechVoiceSelection.preferred([]))
        XCTAssertNil(SpeechVoiceSelection.preferred([english], selectedID: english.id))
    }
    func testEqualQualityAndNameHaveStableOrderingAcrossRefreshes() {
        let other = SpeechVoiceOption(id: "ja-other", name: basic.name, language: "ja-JP", quality: .standard)
        let voices = [other, basic, enhanced]
        XCTAssertEqual(SpeechVoiceSelection.ordered(voices), SpeechVoiceSelection.ordered(Array(voices.reversed())))
    }
}
