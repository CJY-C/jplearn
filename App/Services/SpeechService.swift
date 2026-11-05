import AVFoundation
import SwiftUI
import LearningCore

@MainActor final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    var japaneseVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("ja") }
            .sorted { $0.name < $1.name }
    }
    func speak(_ text: String, slow: Bool = false, voiceID: String = "") throws {
        let voice = (voiceID.isEmpty ? nil : AVSpeechSynthesisVoice(identifier: voiceID))
            ?? AVSpeechSynthesisVoice(language: "ja-JP")
        guard let voice = voice, voice.language.hasPrefix("ja") else {
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
