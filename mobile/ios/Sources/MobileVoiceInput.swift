import AVFoundation
import Speech

/// On-device dictation for the composer: live partial transcripts, stop keeps text, cancel discards.
@MainActor
final class MobileVoiceInput: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var starting = false
    private(set) var transcript = ""
    @Published private(set) var error: String?
    /// Latest microphone levels, oldest first; only the recording bar reads this window.
    private(set) var samples: [CGFloat] = Array(repeating: 0, count: 32)

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finalContinuation: CheckedContinuation<String, Never>?
    private var buffersSinceLevel = 0
    private var cancelled = false

    /// Starts dictation after asking for microphone and speech-recognition access.
    func start() async {
        guard !recording, !starting else { return }
        starting = true
        cancelled = false
        error = nil
        defer { starting = false }
        guard await authorized() else {
            error = "需要允许麦克风与语音识别权限才能语音输入"
            return
        }
        guard !cancelled else { return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
              recognizer.isAvailable else {
            error = "当前设备暂时无法使用语音识别"
            return
        }
        guard !cancelled else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request
            transcript = ""
            let input = engine.inputNode
            let format = input.inputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw NSError(domain: "MobileVoiceInput", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "麦克风输入不可用"])
            }
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                guard let self else { return }
                self.buffersSinceLevel += 1
                guard self.buffersSinceLevel % 2 == 0 else { return }
                let level = Self.level(of: buffer)
                Task { @MainActor in self.pushLevel(level) }
            }
            engine.prepare()
            try engine.start()
            recording = true
            samples = Array(repeating: 0, count: 32)
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
        // Return the composer to its normal controls while the final transcript settles.
        recording = false
        samples = Array(repeating: 0, count: 32)
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

    /// Ends recording or a pending start and discards the transcript.
    func cancel() {
        cancelled = true
        starting = false
        finish(keep: false)
    }

    private func finish(keep: Bool) {
        guard recording || task != nil else { return }
        recording = false
        samples = Array(repeating: 0, count: 32)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if !keep { transcript = "" }
    }

    /// Level of one tap buffer, normalized between silence and loud speech.
    /// - Parameter buffer: captured microphone buffer.
    /// - Returns: a value between 0 and 1.
    private static func level(of buffer: AVAudioPCMBuffer) -> CGFloat {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        if let channels = buffer.floatChannelData {
            for index in 0..<frames {
                let sample = channels[0][index]
                sum += sample * sample
            }
        } else if let channels = buffer.int16ChannelData {
            for index in 0..<frames {
                let sample = Float(channels[0][index]) / 32_768
                sum += sample * sample
            }
        } else {
            return 0
        }
        let rms = sqrt(sum / Float(frames))
        // -50 dBFS is silence, -10 dBFS is loud speech.
        let decibels = 20 * log10(max(rms, 1e-7))
        return CGFloat(min(1, max(0, (decibels + 50) / 40)))
    }

    /// Appends one smoothed level to the scrolling waveform.
    /// - Parameter level: normalized level from the current buffer.
    private func pushLevel(_ level: CGFloat) {
        guard recording else { return }
        let previous = samples.last ?? 0
        let smoothed = previous * 0.35 + level * 0.65
        samples.removeFirst()
        samples.append(smoothed)
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
