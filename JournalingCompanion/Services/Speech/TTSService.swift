import AVFoundation

final class TTSService: NSObject {
    private let synthesizer = AVSpeechSynthesizer()

    var isEnabled: Bool = true

    func speak(_ text: String) {
        guard isEnabled, !synthesizer.isSpeaking else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
