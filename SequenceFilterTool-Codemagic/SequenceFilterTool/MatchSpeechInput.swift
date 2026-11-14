import AVFoundation
import Foundation
import Speech

@MainActor
final class MatchSpeechInput: ObservableObject {
    enum Mode: Equatable {
        case fourMatches
        case threeFixedMatches
    }

    @Published private(set) var isListening = false
    @Published private(set) var listeningMode: Mode?
    @Published private(set) var transcript = ""
    @Published private(set) var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var tapInstalled = false

    func toggleFourMatches(onRecognized: @escaping ([String]) -> Void) {
        toggle(mode: .fourMatches) { text in
            let numbers = Self.parseMatchNumbers(from: text)
            guard numbers.count >= 4 else { return false }
            onRecognized(Array(numbers.prefix(4)))
            return true
        }
    }

    func toggleFixedMatches(onRecognized: @escaping ([(match: String, outcome: String)]) -> Void) {
        toggle(mode: .threeFixedMatches) { text in
            guard let selections = Self.parseFixedSelections(from: text) else { return false }
            onRecognized(selections)
            return true
        }
    }

    private func toggle(mode: Mode, onTranscript: @escaping (String) -> Bool) {
        if isListening {
            stop()
            return
        }
        listeningMode = mode
        Task { await start(onTranscript: onTranscript) }
    }

    func stop() {
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false
        listeningMode = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func start(onTranscript: @escaping (String) -> Bool) async {
        errorMessage = nil
        transcript = ""
        guard await speechPermissionGranted() else {
            errorMessage = "请在系统设置中允许语音识别权限。"
            listeningMode = nil
            return
        }
        guard await microphonePermissionGranted() else {
            errorMessage = "请在系统设置中允许麦克风权限。"
            listeningMode = nil
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "当前语音识别服务不可用，请稍后重试。"
            listeningMode = nil
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            recognitionRequest = request
            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                request.append(buffer)
            }
            tapInstalled = true
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        let text = result.bestTranscription.formattedString
                        self.transcript = text
                        if onTranscript(text) {
                            self.stop()
                            return
                        }
                    }
                    if let error {
                        self.errorMessage = "语音识别失败：\(error.localizedDescription)"
                        self.stop()
                    }
                }
            }
        } catch {
            errorMessage = "无法启动语音输入：\(error.localizedDescription)"
            stop()
        }
    }

    nonisolated static func parseMatchNumbers(from text: String) -> [String] {
        let arabic = captures(pattern: #"\d+"#, in: text)
        if arabic.count >= 4 { return Array(arabic.prefix(4)) }

        let chineseTokens = captures(pattern: #"[零〇一二三四五六七八九十百两]+"#, in: text)
        let chinese = chineseTokens.compactMap(chineseNumber).map(String.init)
        if chinese.count >= 4 { return Array(chinese.prefix(4)) }
        return arabic + chinese
    }

    nonisolated static func parseFixedSelections(
        from text: String
    ) -> [(match: String, outcome: String)]? {
        var tokens = captures(pattern: #"\d+"#, in: text)
        if tokens.count < 6 {
            tokens = captures(pattern: #"[零〇一二三四五六七八九十百两]+"#, in: text)
                .compactMap(chineseNumber)
                .map(String.init)
        }
        guard tokens.count >= 6 else { return nil }
        let selections = [
            (match: tokens[0], outcome: tokens[1]),
            (match: tokens[2], outcome: tokens[3]),
            (match: tokens[4], outcome: tokens[5])
        ]
        guard validOutcome(selections[0].outcome, count: 1),
              validOutcome(selections[1].outcome, count: 2),
              validOutcome(selections[2].outcome, count: 3),
              Set(selections.map(\.match)).count == 3 else { return nil }
        return selections.map { selection in
            let normalized = ["3", "1", "0"].filter { selection.outcome.contains($0) }.joined()
            return (selection.match, normalized)
        }
    }

    nonisolated private static func validOutcome(_ text: String, count: Int) -> Bool {
        let characters = text.map(String.init)
        return characters.count == count
            && Set(characters).count == count
            && Set(characters).isSubset(of: Set(["3", "1", "0"]))
    }

    private func speechPermissionGranted() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func microphonePermissionGranted() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    nonisolated private static func captures(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }

    nonisolated private static func chineseNumber(_ text: String) -> Int? {
        let digits: [Character: Int] = [
            "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3,
            "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
        ]
        if !text.contains("十"), !text.contains("百") {
            let values = text.compactMap { digits[$0] }
            guard values.count == text.count else { return nil }
            return values.reduce(0) { $0 * 10 + $1 }
        }
        var total = 0
        var current = 0
        for character in text {
            if let digit = digits[character] {
                current = digit
            } else if character == "十" {
                total += (current == 0 ? 1 : current) * 10
                current = 0
            } else if character == "百" {
                total += (current == 0 ? 1 : current) * 100
                current = 0
            } else {
                return nil
            }
        }
        return total + current
    }
}
