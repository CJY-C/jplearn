import AVFoundation
import SwiftUI
import LearningCore

@MainActor final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    private var japaneseVoices: [AVSpeechSynthesisVoice] {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { option(for: $0).isJapanese }
        if !voices.isEmpty { return voices }
        if let voice = AVSpeechSynthesisVoice(language: "ja-JP"), option(for: voice).isJapanese { return [voice] }
        return []
    }
    var voiceOptions: [SpeechVoiceOption] {
        SpeechVoiceSelection.ordered(japaneseVoices.map { option(for: $0) })
    }
    private func option(for voice: AVSpeechSynthesisVoice) -> SpeechVoiceOption {
        let quality: SpeechVoiceOption.Quality
        if #available(iOS 16.0, *), voice.quality == .premium { quality = .premium }
        else if voice.quality == .enhanced { quality = .enhanced }
        else { quality = .standard }
        return SpeechVoiceOption(id: voice.identifier, name: voice.name, language: voice.language, quality: quality)
    }
    func speak(_ text: String, slow: Bool = false, voiceID: String = "") throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let voices = japaneseVoices
        let choice = SpeechVoiceSelection.preferred(voices.map { option(for: $0) }, selectedID: voiceID)
        guard let voice = voices.first(where: { $0.identifier == choice?.id }) else {
            throw LearningError.invalid("请先在系统设置的“辅助功能 → 朗读内容 → 声音”中准备日语声音。")
        }
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try AVAudioSession.sharedInstance().setActive(true)
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (slow ? 0.72 : 0.95)
        synthesizer.speak(utterance)
    }
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        releaseAudioSessionIfIdle()
    }
    private func releaseAudioSessionIfIdle() {
        guard !synthesizer.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.releaseAudioSessionIfIdle() }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.releaseAudioSessionIfIdle() }
    }
}
