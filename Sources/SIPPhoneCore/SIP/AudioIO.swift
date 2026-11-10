import Foundation
import AVFoundation

/// Bridges live RTP audio to CoreAudio:
/// - captures the system default input (after mic permission is granted),
///   converts it to 8 kHz mono frames for RTP
/// - plays back received G.711 frames through a player node
/// All engine mutations are serialized on `ioQueue`; mic permission is requested
/// asynchronously so `start()` never blocks on the TCC prompt.
final class AudioIO {

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let eightK = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 8000, channels: 1, interleaved: false)!

    private let ioQueue = DispatchQueue(label: "sip.audioio")
    private var converter: AVAudioConverter?
    private var pending = [Float]()
    private var scheduledCount = 0
    private var tapInstalled = false
    private var started = false
    private var muted = false
    private let lock = NSLock()

    /// 8 kHz mono frames (multiples of 160 samples) ready for RTP.
    var onSendAudio: (([Float]) -> Void)?

    /// Starts capture/playback without blocking the caller. Engine bring-up can
    /// stall for seconds (e.g. under xctest or while TCC resolves), so it must
    /// never run on the SIP signalling queue.
    func start() {
        ioQueue.async { [weak self] in
            guard let self else { return }
            do { try self.startLocked() } catch {
                NSLog("[SIPPhone] AudioIO start failed: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        ioQueue.async { [weak self] in self?.stopLocked() }
    }

    func setMuted(_ flag: Bool) {
        lock.lock()
        muted = flag
        lock.unlock()
    }

    // MARK: Engine setup

    private func startLocked() throws {
        stopLocked()
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            try startEngineLocked(withInput: true)

        case .notDetermined:
            // Output-only immediately; the mic prompt is async, input joins when granted.
            try startEngineLocked(withInput: false)
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                guard granted else { return }
                self?.ioQueue.async {
                    self?.stopLocked()
                    try? self?.startEngineLocked(withInput: true)
                }
            }

        default: // denied / restricted
            try startEngineLocked(withInput: false)
        }
    }

    private func startEngineLocked(withInput: Bool) throws {
        if withInput {
            let input = engine.inputNode
            let inFormat = input.outputFormat(forBus: 0)
            guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
                throw NSError(domain: "SIPPhone", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Kein Mikrofon verfügbar (Zugriff verweigert?)"])
            }
            converter = AVAudioConverter(from: inFormat, to: eightK)
            input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
                self?.handleTap(buffer, inFormat: inFormat)
            }
            tapInstalled = true
        }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: eightK)
        engine.prepare()
        try engine.start()
        player.play()
        started = true
    }

    private func stopLocked() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        player.stop()
        engine.stop()
        engine.reset()
        if engine.attachedNodes.contains(player) {
            engine.disconnectNodeOutput(player)
            engine.detach(player)
        }
        converter = nil
        started = false
        lock.lock()
        pending.removeAll()
        scheduledCount = 0
        lock.unlock()
    }

    // MARK: Capture path

    private func handleTap(_ buffer: AVAudioPCMBuffer, inFormat: AVAudioFormat) {
        guard let conv = converter else { return }

        let ratio = 8000.0 / inFormat.sampleRate
        let cap = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: eightK, frameCapacity: cap) else { return }

        var fed = false
        var err: NSError?
        let status = conv.convert(to: out, error: &err) { _, st -> AVAudioPCMBuffer? in
            if fed {
                st.pointee = .noDataNow
                return nil
            }
            fed = true
            st.pointee = .haveData
            return buffer
        }
        guard (status == .haveData || status == .inputRanDry), out.frameLength > 0 else { return }

        let samples = Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
        lock.lock()
        let isMuted = muted
        pending.append(contentsOf: samples)
        lock.unlock()
        if isMuted { return }

        // Emit complete 20 ms frames.
        while true {
            lock.lock()
            guard pending.count >= 160 else { lock.unlock(); return }
            let chunk = Array(pending.prefix(160))
            pending.removeFirst(160)
            lock.unlock()
            onSendAudio?(chunk)
        }
    }

    // MARK: Playback path

    func play(pt: UInt8, payload: Data) {
        guard started, payload.count > 0 else { return }
        let samples = pt == 8 ? G711.alawDecode(payload) : G711.ulawDecode(payload)
        guard !samples.isEmpty,
              let buf = AVAudioPCMBuffer(pcmFormat: eightK, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buf.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }

        lock.lock()
        let backlogHigh = scheduledCount > 12 // ~250 ms: drop to bound latency
        if !backlogHigh { scheduledCount += 1 }
        lock.unlock()

        if backlogHigh { return }
        player.scheduleBuffer(buf) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.scheduledCount = max(0, self.scheduledCount - 1)
            self.lock.unlock()
        }
    }
}
