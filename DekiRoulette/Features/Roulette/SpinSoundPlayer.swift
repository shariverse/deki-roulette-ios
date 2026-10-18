import AVFAudio

/// スピン中の「カチッ」を鳴らす。止まる位置も回転角もスピン開始時に決まっているので、
/// 鳴らす時刻も先に分かる。`ClickTrack` で 1 本の波形にしてから一度に流し、リズムを揺らさない。
/// 指で盤面を動かしている間は、境目を越えるたびに `playClick()` で 1 回ずつ鳴らす。
/// 停止時の決まり音（`playChime()`）はクリックとは別のノードで鳴らすので、鳴っているクリックを止めたり差し替えたりしない。
/// 音が出せない環境（素材が読めない、オーディオが使えない等）では黙って何もしない。
@MainActor
final class SpinSoundPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var click: (samples: [Float], format: AVAudioFormat)?
    /// 決まり音を流すノードと音源。「スピンの演出」が「なし」のときは読み込まない（`prepare(chime:)` か最初の `playChime()` で読む）。
    private let chimePlayer = AVAudioPlayerNode()
    private var chime: AVAudioPCMBuffer?
    /// セッションを `.ambient` にして有効化する処理。成功したかを返す。
    /// 終わる前にエンジンを起動すると既定のカテゴリで有効化され、他のアプリの音を止めてしまう。
    private var sessionSetup: Task<Bool, Never>?
    /// `stop()` や次の `play(at:)` のあとに、待っていた古い再生が始まらないようにする。
    private var generation = 0
    /// 決まり音用。回転音の `generation` とは別に数え、クリックの再生で決まり音を取り消さない。
    private var chimeGeneration = 0

    /// 素材の読み込みとオーディオの準備。画面が出たところで呼んでおく。
    /// セッションの有効化はメインスレッドで待つと UI が固まるので、別スレッドで行い `play(at:)` はその完了を待つ。
    /// `chime` が true なら決まり音も読み込んでおく（最初の停止で読み込みを待たない）。
    func prepare(chime: Bool = false) {
        if chime { prepareChime() }
        if click == nil {
            guard let loaded = loadSound(named: "click") else { return }
            click = loaded
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: loaded.format)
        }
        // 前回の準備に失敗していれば nil に戻してあるので、ここでやり直す
        guard sessionSetup == nil else { return }
        sessionSetup = Task.detached(priority: .utility) {
            let session = AVAudioSession.sharedInstance()
            do {
                // 消音（マナー）スイッチに従い、他のアプリで鳴っている音も止めない
                try session.setCategory(.ambient, mode: .default)
                try session.setActive(true)
                return true
            } catch {
                return false
            }
        }
    }

    /// いますぐクリック音を 1 回鳴らす（指で動かしている盤面の針が境目を越えたとき）。
    /// セッションの準備を待った分だけ遅れても捨てずに鳴らす（`play(at: [0])` だと時刻が過ぎた扱いで鳴らない）。
    func playClick() {
        play(at: [0], keepsLate: true)
    }

    /// `times`（スピン開始からの秒）にクリック音を鳴らす。呼んだ時点が 0 秒。
    func play(at times: [TimeInterval]) {
        play(at: times, keepsLate: false)
    }

    /// `keepsLate` が true なら、準備を待つうちに過ぎた時刻も捨てずにすぐ鳴らす。
    private func play(at times: [TimeInterval], keepsLate: Bool) {
        prepare()
        guard !times.isEmpty, let click, let sessionSetup else { return }

        generation += 1
        let current = generation
        let requested = ContinuousClock.now
        Task { [weak self] in
            // セッションの準備が済むまでエンジンは起動しない。失敗していれば鳴らさず、次の再生で準備し直す
            let ready = await sessionSetup.value
            guard let self else { return }
            if !ready, self.sessionSetup == sessionSetup { self.sessionSetup = nil }
            guard ready, self.generation == current else { return }
            // 待った分だけ遅れて鳴り始めるので、時刻をずらして過ぎたものは捨てる
            let waited = requested.duration(to: .now) / .seconds(1)
            let shifted = times.map { $0 - waited }
            let remaining = keepsLate ? shifted.map { max($0, 0) } : shifted.filter { $0 >= 0 }
            self.start(remaining, click: click)
        }
    }

    /// 停止時の決まり音を 1 回鳴らす（スピンが止まって結果が出たとき）。鳴らすかどうかは呼び出し側が `StopChime.plays` で決める。
    /// 回転音のノードには触れないので、クリックの最後の音と重なってよい。続けて呼ぶと前の決まり音を頭から鳴らし直す。
    func playChime() {
        prepare()
        prepareChime()
        guard let chime, let sessionSetup else { return }

        chimeGeneration += 1
        let current = chimeGeneration
        Task { [weak self] in
            let ready = await sessionSetup.value
            guard let self else { return }
            if !ready, self.sessionSetup == sessionSetup { self.sessionSetup = nil }
            guard ready, self.chimeGeneration == current else { return }
            self.startChime(chime)
        }
    }

    private func startChime(_ chime: AVAudioPCMBuffer) {
        // 中断のあとはエンジンが止まっているので、鳴らすたびに確かめる
        guard engine.isRunning || (try? engine.start()) != nil else { return }
        chimePlayer.stop()
        chimePlayer.scheduleBuffer(chime, at: nil)
        chimePlayer.play()
    }

    /// 画面から離れるときなど、鳴らしている途中で止める。決まり音も止める。
    /// 決まり音は回転音（click.wav）と同じエンジン・セッションで鳴らすので、click が読めていなければ決まり音も鳴っていない。
    func stop() {
        guard click != nil else { return }
        generation += 1
        chimeGeneration += 1
        player.stop()
        chimePlayer.stop()
        engine.stop()
    }

    /// 決まり音を読み込んでノードをつなぐ。読めなければ何もしない（次の呼び出しでやり直す）。
    private func prepareChime() {
        guard chime == nil, let loaded = loadSound(named: "chime"),
              let buffer = makeBuffer(loaded.samples, format: loaded.format)
        else { return }
        chime = buffer
        engine.attach(chimePlayer)
        engine.connect(chimePlayer, to: engine.mainMixerNode, format: loaded.format)
        chimePlayer.volume = Config.chimeGain
    }

    private func start(_ times: [TimeInterval], click: (samples: [Float], format: AVAudioFormat)) {
        guard !times.isEmpty else { return }
        let track = ClickTrack.render(
            click: click.samples,
            sampleRate: click.format.sampleRate,
            times: times,
            gain: Config.clickGain
        )
        guard let buffer = makeBuffer(track, format: click.format) else { return }
        // 中断のあとはエンジンが止まっているので、鳴らすたびに確かめる
        guard engine.isRunning || (try? engine.start()) != nil else { return }

        player.stop()
        player.scheduleBuffer(buffer, at: nil)
        player.play()
    }

    private func loadSound(named name: String) -> (samples: [Float], format: AVAudioFormat)? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: file.processingFormat,
                  frameCapacity: AVAudioFrameCount(file.length)
              ),
              (try? file.read(into: buffer)) != nil,
              let channel = buffer.floatChannelData?.pointee
        else { return nil }

        return (Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))), file.processingFormat)
    }

    private func makeBuffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?.pointee
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }
}
