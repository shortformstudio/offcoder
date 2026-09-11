import Foundation
import Speech
import AVFoundation

final class VoiceTranscriptionService: ObservableObject {
    static let shared = VoiceTranscriptionService()

    @Published var isRecording: Bool = false
    @Published var audioLevel: Float = 0.0
    @Published var errorMessage: String? = nil

    private var audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var baselineTextBeforeSpeech: String = ""

    func toggleRecording(onTextChange: @escaping (String) -> Void, currentText: String) {
        if isRecording {
            stopRecording()
        } else {
            startRecording(onTextChange: onTextChange, initialText: currentText)
        }
    }

    func startRecording(onTextChange: @escaping (String) -> Void, initialText: String) {
        stopRecording()
        baselineTextBeforeSpeech = initialText

        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch authStatus {
                case .authorized:
                    self.beginAudioEngineRecording(onTextChange: onTextChange)
                case .denied:
                    self.errorMessage = "Speech recognition access denied. Enable in macOS System Settings > Privacy & Security."
                case .restricted:
                    self.errorMessage = "Speech recognition restricted on this device."
                case .notDetermined:
                    self.errorMessage = "Speech recognition authorization not determined."
                @unknown default:
                    self.errorMessage = "Unknown speech authorization state."
                }
            }
        }
    }

    private func beginAudioEngineRecording(onTextChange: @escaping (String) -> Void) {
        audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            self.errorMessage = "Unable to initialize speech recognition request."
            return
        }

        recognitionRequest.shouldReportPartialResults = true

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let recognizedString = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    let separator = self.baselineTextBeforeSpeech.isEmpty || self.baselineTextBeforeSpeech.hasSuffix(" ") ? "" : " "
                    let combined = self.baselineTextBeforeSpeech.isEmpty ? recognizedString : "\(self.baselineTextBeforeSpeech)\(separator)\(recognizedString)"
                    onTextChange(combined)
                }
            }

            if error != nil || (result?.isFinal ?? false) {
                DispatchQueue.main.async {
                    self.stopRecording()
                }
            }
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)

            // Compute audio meter level for live wave visualization
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }

            var sum: Float = 0
            for i in 0..<frameCount {
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frameCount))
            let normalized = min(max(rms * 10, 0), 1.0)
            DispatchQueue.main.async {
                self?.audioLevel = normalized
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            errorMessage = nil
        } catch {
            errorMessage = "Audio engine failed to start: \(error.localizedDescription)"
            stopRecording()
        }
    }

    func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
        audioLevel = 0.0
    }
}
