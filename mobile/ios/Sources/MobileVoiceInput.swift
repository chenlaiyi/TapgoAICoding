import AVFoundation
import Speech

/// On-device dictation for the composer: live partial transcripts, stop keeps text, cancel discards.
@MainActor
final class MobileVoiceInput: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var transcript = ""
    @Published private(set) var error: String?
    @Published private(set) var level: CGFloat = 0

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finalContinuation: CheckedContinuation<String, Never>?
    private var buffersSinceLevel = 0

    /// Starts dictation after asking for microphone and speech-recognition access.
    func start() async {
        guard !recording else { return }
        error = nil
        guard await authorized() else {
            error = "需要允许麦克风与语音识别权限才能语音输入"
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
              recognizer.isAvailable else {
            error = "当前设备暂时无法使用语音识别"
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request
            transcript = ""
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
                request.append(buffer)
                guard let self else { return }
                self.buffersSinceLevel += 1
                guard self.buffersSinceLevel % 4 == 0 else { return }
                let level = Self.level(of: buffer)
                Task { @MainActor in self.level = level }
            }
            engine.prepare()
            try engine.start()
            recording = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        if result.isFinal {
                            self.finish(keep: true)
                            self.deliverFinal()
                        }
                    }
                    if error != nil, self.recording {
                        self.finish(keep: true)
                        self.deliverFinal()
                    }
                }
            }
        } catch {
            self.error = "无法开始录音：\(error.localizedDescription)"
            finish(keep: false)
        }
    }

    /// Ends recording and waits briefly for the final transcript.
    /// - Returns: the best transcript available when recognition settles.
    func stop() async -> String {
        guard recording || task != nil else { return transcript }
        request?.endAudio()
        let text = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            finalContinuation = continuation
            Task {
                try? await Task.sleep(for: .milliseconds(1500))
                self.deliverFinal()
            }
        }
        finish(keep: true)
        return text
    }

    private func deliverFinal() {
        guard let continuation = finalContinuation else { return }
        finalContinuation = nil
        continuation.resume(returning: transcript)
    }

    /// Ends recording and discards the transcript.
    func cancel() {
        finish(keep: false)
    }

    private func finish(keep: Bool) {
        guard recording || task != nil else { return }
        recording = false
        level = 0
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if !keep { transcript = "" }
    }

    /// Peak amplitude of one tap buffer, normalized for the waveform bars.
    /// - Parameter buffer: captured microphone buffer.
    /// - Returns: a value between 0 and 1.
    private static func level(of buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channels = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<frames {
            let sample = channels[0][index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frames))
        return CGFloat(min(1, max(0, rms * 14)))
    }

    private func authorized() async -> Bool {
        let speech = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speech else { return false }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }
}
