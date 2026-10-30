import AVFoundation
import os

/// 게임 시계는 시스템 업타임(NSEvent.timestamp와 같은 기준)으로 잰다
enum Clock {
    static func now() -> Double { ProcessInfo.processInfo.systemUptime }
}

enum SoundEffect: Int {
    case don, ka, pop, click
}

final class AudioService {
    private let engine = AVAudioEngine()
    private let music = AVAudioPlayerNode()
    private let sfx = EffectMixer(sounds: [Synth.donSound, Synth.kaSound, Synth.popSound, Synth.clickSound])
    private var buffer: AVAudioPCMBuffer?
    private var file: AVAudioFile?
    private var connectedFormat: AVAudioFormat?

    /// 곡 시각 0이 들리는 시스템 업타임
    private(set) var startUptime = 0.0
    private(set) var isPlaying = false

    init() {
        engine.attach(music)
        engine.attach(sfx.node)
        engine.connect(sfx.node, to: engine.mainMixerNode, format: sfx.format)
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                               queue: .main) { [weak self] _ in
            self?.isPlaying = false
            try? self?.engine.start()
        }
        try? engine.start()
        applyVolumes()
    }

    func applyVolumes() {
        music.volume = Float(Settings.shared.musicVolume)
        sfx.node.volume = Float(Settings.shared.sfxVolume)
    }

    func load(samples: [Float], sampleRate: Double = 44_100) {
        stop()
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buf.frameLength = buf.frameCapacity
        samples.withUnsafeBufferPointer { src in
            buf.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        buffer = buf
        file = nil
        connect(format)
    }

    func load(url: URL) throws {
        stop()
        let f = try AVAudioFile(forReading: url)
        file = f
        buffer = nil
        connect(f.processingFormat)
    }

    private func connect(_ format: AVAudioFormat) {
        if connectedFormat == format { return }
        engine.disconnectNodeOutput(music)
        engine.connect(music, to: engine.mainMixerNode, format: format)
        connectedFormat = format
    }

    /// 지금부터 delay초 뒤에 곡 시각 songTime이 들리도록 재생한다. 음수면 그만큼 기다렸다가 처음부터.
    func play(from songTime: Double, delay: Double = 0.1) {
        music.stop()
        if !engine.isRunning { try? engine.start() }
        let now = Clock.now()
        let latency = engine.outputNode.presentationLatency
        startUptime = now + delay - songTime + latency
        isPlaying = true

        let sampleRate = connectedFormat?.sampleRate ?? 44_100
        let startFrame = AVAudioFramePosition(max(0, songTime) * sampleRate)
        let playAt = now + delay + max(0, -songTime)

        if let f = file {
            guard startFrame < f.length else { return }
            music.scheduleSegment(f, startingFrame: startFrame,
                                  frameCount: AVAudioFrameCount(f.length - startFrame), at: nil)
        } else if let b = buffer {
            guard startFrame < AVAudioFramePosition(b.frameLength) else { return }
            music.scheduleBuffer(startFrame == 0 ? b : slice(b, from: AVAudioFrameCount(startFrame)), at: nil)
        } else {
            return
        }
        music.play(at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: playAt)))
    }

    func stop() {
        music.stop()
        isPlaying = false
    }

    func songTime(atUptime uptime: Double) -> Double { uptime - startUptime }

    var songTime: Double { songTime(atUptime: Clock.now()) }

    func play(_ effect: SoundEffect) { sfx.trigger(effect.rawValue) }

    private func slice(_ b: AVAudioPCMBuffer, from frame: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let count = b.frameLength - frame
        let out = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: count)!
        out.frameLength = count
        for ch in 0..<Int(b.format.channelCount) {
            out.floatChannelData![ch].update(from: b.floatChannelData![ch] + Int(frame), count: Int(count))
        }
        return out
    }
}

/// 효과음을 오디오 스레드에서 바로 섞는다. AVAudioPlayerNode를 매번 시작하는 것보다 지연이 짧다.
private final class EffectMixer {
    let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private let sounds: [[Float]]
    private let lock = OSAllocatedUnfairLock(initialState: [Int]())
    private var voices: [(sound: Int, position: Int)] = []
    private(set) var node: AVAudioSourceNode!

    init(sounds: [[Float]]) {
        self.sounds = sounds
        voices.reserveCapacity(64)
        node = AVAudioSourceNode(format: format) { [unowned self] _, _, frameCount, list in
            self.render(Int(frameCount), UnsafeMutableAudioBufferListPointer(list))
            return noErr
        }
    }

    func trigger(_ sound: Int) {
        lock.withLock { $0.append(sound) }
    }

    private func render(_ n: Int, _ buffers: UnsafeMutableAudioBufferListPointer) {
        guard let out = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        out.initialize(repeating: 0, count: n)
        lock.withLock { pending in
            for s in pending where voices.count < 48 { voices.append((s, 0)) }
            pending.removeAll(keepingCapacity: true)
        }
        var k = 0
        while k < voices.count {
            let (s, pos) = voices[k]
            let len = min(n, sounds[s].count - pos)
            sounds[s].withUnsafeBufferPointer { p in
                for i in 0..<len { out[i] += p[pos + i] }
            }
            if pos + len >= sounds[s].count {
                voices.remove(at: k)
            } else {
                voices[k].position = pos + len
                k += 1
            }
        }
        for i in 0..<n { out[i] = max(-1, min(1, out[i])) }
    }
}
