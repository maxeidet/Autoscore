//
//  Announcer.swift
//  Dartify
//

import AVFoundation

/// Speaks scores like a darts caller.
final class Announcer {
    static let shared = Announcer()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {
        // Speak over other audio, and even with the ringer switch on silent.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }

    func say(_ text: String, interrupt: Bool = false) {
        try? AVAudioSession.sharedInstance().setActive(true)
        if interrupt { synthesizer.stopSpeaking(at: .word) }
        let utterance = AVSpeechUtterance(string: text)
        // Always English (British, like a darts caller), whatever language the phone is set to.
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        utterance.rate = 0.5
        synthesizer.speak(utterance)
    }
}
