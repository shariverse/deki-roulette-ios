import Foundation
import Testing
@testable import DekiRoulette

struct SpinTeaseTests {
    private static let counts = [2, 3, 8, 24]
    private static let seeds: [UInt64] = [1, 7, 42, 2026]
    private static let directions: [SpinDirection] = [.clockwise, .counterclockwise]
    private static let teaseDuration = Config.spinDuration + Config.spinTeaseDuration

    /// `RouletteMath.nextRotation` で決めた最終角を持つスピンの条件。
    private struct Case {
        var from: Double
        var to: Double
        var count: Int
        var direction: SpinDirection
        var sign: Double { direction == .clockwise ? 1 : -1 }
        var slice: Double { 360 / Double(count) }
    }

    private static func cases() -> [Case] {
        var result: [Case] = []
        for count in counts {
            for direction in directions {
                for seed in seeds {
                    var rng = SeededGenerator(seed: seed)
                    let from = Double(seed % 360) - 17.5
                    let to = RouletteMath.nextRotation(
                        current: from, targetIndex: Int(seed) % count, count: count, direction: direction, using: &rng
                    )
                    result.append(Case(from: from, to: to, count: count, direction: direction))
                }
            }
        }
        return result
    }

    /// 細かい時刻で角度を引き、`floor(角度 / スライス幅)` が変わった回数（往復とも）を数える。境目の時刻の数の正解に使う。
    private func sampledCrossings(_ path: SpinPath, count: Int, step: TimeInterval = 0.0005) -> Int {
        let slice = 360 / Double(count)
        var previous = (path.angle(at: 0) / slice).rounded(.down)
        var crossings = 0
        var elapsed = step
        while elapsed <= path.duration + step {
            let current = (path.angle(at: elapsed) / slice).rounded(.down)
            crossings += Int(abs(current - previous))
            previous = current
            elapsed += step
        }
        return crossings
    }

    /// 回る向きを正にした角度の列（1 ミリ秒ごと）。
    private func forwardAngles(_ path: SpinPath, sign: Double) -> [Double] {
        (0...Int(path.duration * 1000)).map { sign * path.angle(at: Double($0) / 1000) }
    }

    // MARK: 最終角と長さ

    @Test(arguments: SpinTease.allCases)
    func 最終角は変えず長さは固定(tease: SpinTease) {
        for spin in Self.cases() {
            for release: Double? in [nil, spin.sign * 900] {
                let path = SpinPath.teased(tease, from: spin.from, to: spin.to, count: spin.count, releaseVelocity: release)
                #expect(path.tease == tease)
                #expect(abs(path.to - spin.to) < 1e-9)
                #expect(abs(path.angle(at: path.duration) - spin.to) < 1e-9)
                #expect(abs(path.angle(at: path.duration + 1) - spin.to) < 1e-9)
                #expect(abs(path.angle(at: 0) - spin.from) < 1e-9)
                #expect(abs(path.duration - Self.teaseDuration) < 1e-9)
                #expect(abs(path.segments[0].duration - Config.spinDuration) < 1e-9)
            }
        }
    }

    @Test func 焦らし込みの長さと保険() {
        #expect(abs(Self.teaseDuration - 6.5) < 1e-9)
        #expect(abs(Config.spinTeaseFallback - (Self.teaseDuration + 0.6)) < 1e-9)
    }

    // MARK: 回り始め

    @Test(arguments: SpinTease.allCases)
    func 回り始めは主の曲線と同じ(tease: SpinTease) {
        for spin in Self.cases() {
            let path = SpinPath.teased(tease, from: spin.from, to: spin.to, count: spin.count)
            let main = SpinMotion(
                from: spin.from, to: path.segments[0].to, duration: Config.spinDuration, easing: Config.spinEasing
            )
            #expect(path.segments[0] == main)
            for elapsed in [0, 0.1, 0.5, 2.0] {
                #expect(abs(path.angle(at: elapsed) - main.angle(at: elapsed)) < 1e-9)
            }
            #expect(abs(path.angularVelocity(at: 0) - main.angularVelocity(at: 0)) < 1e-9)
        }
    }

    @Test(arguments: SpinTease.allCases)
    func フリックの初速が保たれる(tease: SpinTease) {
        for spin in Self.cases() {
            let release = spin.sign * 900
            let path = SpinPath.teased(tease, from: spin.from, to: spin.to, count: spin.count, releaseVelocity: release)
            let expected = FlickSpin.easing(
                angularVelocity: release, distance: abs(path.segments[0].to - spin.from), duration: Config.spinDuration
            )
            #expect(path.segments[0].easing == expected)
            // 曲線の始点の傾きは端のわずかに内側で測るので、離した速さと 1% 以内で一致すればよい
            #expect(abs(path.angularVelocity(at: 0) - release) < abs(release) * 0.01)
        }
    }

    // MARK: つなぎ目

    @Test(arguments: SpinTease.allCases)
    func つなぎ目で角度と角速度が連続(tease: SpinTease) {
        for spin in Self.cases() {
            let path = SpinPath.teased(tease, from: spin.from, to: spin.to, count: spin.count)
            for (previous, next) in zip(path.segments, path.segments.dropFirst()) {
                #expect(abs(previous.to - next.from) < 1e-12)
            }
            for junction in path.startTimes.dropFirst() {
                #expect(abs(path.angle(at: junction - 1e-7) - path.angle(at: junction + 1e-7)) < 1e-4)
                // つなぎ目はどちらの区間も傾き 0 で、前後 1 ミリ秒でも 2 度/秒に満たない
                #expect(abs(path.angularVelocity(at: junction)) < 1e-6)
                #expect(abs(path.angularVelocity(at: junction - 1e-3)) < 2)
                #expect(abs(path.angularVelocity(at: junction + 1e-3)) < 2)
            }
        }
    }

    // MARK: 入り方ごとの形

    @Test func ためらいは境目か止まる角度の手前で止まりかけてから行き過ぎ戻り過ぎて止まる() {
        for spin in Self.cases() {
            let path = SpinPath.teased(.hesitate, from: spin.from, to: spin.to, count: spin.count)
            #expect(path.segments.count == 4)
            let stop = spin.sign * spin.to
            let boundary = (stop / spin.slice).rounded(.down) * spin.slice
            let approach = min(spin.slice * Config.spinTeaseApproachFraction, Config.spinTeaseApproachMax)
            let swing = min(spin.slice * Config.spinTeaseSwingFraction, Config.spinTeaseSwingMax)
            let turns = path.segments.map { spin.sign * $0.to }
            // 境目の手前 a か、止まる角度の `spinTeaseCreepMax` 手前の、止まる角度に近い方で止まりかける
            #expect(abs(turns[0] - max(boundary - approach, stop - Config.spinTeaseCreepMax)) < 1e-9)
            #expect(turns[0] < stop)
            #expect(stop - turns[0] <= Config.spinTeaseCreepMax + 1e-9)
            // そこから w だけ行き過ぎ、k·w だけ戻り過ぎてから止まる
            #expect(abs(turns[1] - (stop + swing)) < 1e-9)
            #expect(abs(turns[2] - (stop - swing * Config.spinTeaseSwingDecay)) < 1e-9)
            #expect(abs(turns[3] - stop) < 1e-9)
            // 止まりかけるまでは戻らない
            let main = forwardAngles(path, sign: spin.sign).prefix(Int(Config.spinDuration * 1000))
            #expect(zip(main, main.dropFirst()).allSatisfy { $1 >= $0 - 1e-9 })
        }
    }

    @Test func 止まる角度が境目の近くならためらいは境目の手前で止まりかける() {
        // 8 件（45°）で境目の 2° 先に止まる。手前の距離は上限（スライス幅の 25% = 11.25° より小さい `spinTeaseApproachMax`）
        let path = SpinPath.teased(.hesitate, from: 0, to: 1440 + 92, count: 8)
        #expect(abs(path.segments[0].to - (1440 + 90 - Config.spinTeaseApproachMax)) < 1e-9)
    }

    @Test(arguments: [SpinTease.hesitate, .rollBack], [2, 3])
    func 広いスライスの奥で止まっても焦らしの区間で加速し直さない(tease: SpinTease, count: Int) {
        // スライスの 99% の位置で止まる。焦らしの区間の角速度は、止まりかけた角度から c（＋戻り）だけ進む速さに収まる
        let slice = 360 / Double(count)
        let to = 1440 + slice * 0.99
        let path = SpinPath.teased(tease, from: 0, to: to, count: count)
        let peak = stride(from: Config.spinDuration, through: path.duration, by: 0.001)
            .map { abs(path.angularVelocity(at: $0)) }.max() ?? 0
        // ease-in-out の最大の傾きは 1.6 倍ほど。いちばん速い区間は、ためらいでは最初の区間（1 秒）で c + w を、
        // 戻りかけでは進み直す区間（1.2 秒）で c + r + k·w を進む
        let swing = Config.spinTeaseSwingMax
        let (distance, shortest) = switch tease {
        case .rollBack:
            (Config.spinTeaseCreepMax + Config.spinTeaseRollBackMax + swing * Config.spinTeaseSwingDecay,
             Config.spinTeaseDuration * Config.spinTeaseRollBackShares[1])
        default:
            (Config.spinTeaseCreepMax + swing, Config.spinTeaseDuration * Config.spinTeaseSwingShares[0])
        }
        #expect(peak < 2 * distance / shortest)
        #expect(abs(path.to - to) < 1e-9)
    }

    @Test func 保険は長さの0_6秒後() {
        let teased = SpinPath.teased(.hesitate, from: 0, to: 1532, count: 8)
        #expect(abs(teased.fallback - Config.spinTeaseFallback) < 1e-9)
        // 焦らしを入れられずに 1 本の曲線になったスピンも、同じ長さなので同じ保険
        let short = SpinPath.teased(.hesitate, from: 0, to: 10, count: 8)
        #expect(short.tease == nil)
        #expect(abs(short.fallback - Config.spinTeaseFallback) < 1e-9)
        let plain = SpinPath.spin(from: 0, to: 1532, count: 8, effects: .none)
        #expect(abs(plain.fallback - Config.spinFallback) < 1e-9)
    }

    /// 焦らしを入れるかは `tease` だけで決まり、ほかの演出のフラグには依らない（乱数の引き方も同じ）。
    @Test func 焦らしはteaseのフラグだけで入れる() {
        var teaseOnly = SpinEffects.none
        teaseOnly.tease = true
        var allButTease = SpinEffects.all
        allButTease.tease = false
        for spin in Self.cases() {
            var first = SeededGenerator(seed: 7)
            var second = SeededGenerator(seed: 7)
            let teased = SpinPath.spin(from: spin.from, to: spin.to, count: spin.count, effects: teaseOnly, using: &first)
            let all = SpinPath.spin(from: spin.from, to: spin.to, count: spin.count, effects: .all, using: &second)
            #expect(teased.tease != nil)
            #expect(teased == all)

            var third = SeededGenerator(seed: 7)
            var fourth = SeededGenerator(seed: 7)
            let plain = SpinPath.spin(from: spin.from, to: spin.to, count: spin.count, effects: allButTease, using: &third)
            #expect(plain.tease == nil)
            #expect(plain == SpinPath.spin(from: spin.from, to: spin.to, count: spin.count, effects: .none, using: &fourth))
            // 焦らしを入れないときは乱数を引かない
            var untouched = SeededGenerator(seed: 7)
            #expect(third.next() == untouched.next())
        }
    }

    @Test func 戻りかけは境目か止まる角度の手前で戻ってから進み直し少し行き過ぎて止まる() {
        for spin in Self.cases() {
            let path = SpinPath.teased(.rollBack, from: spin.from, to: spin.to, count: spin.count)
            #expect(path.segments.count == 4)
            let stop = spin.sign * spin.to
            let boundary = (stop / spin.slice).rounded(.down) * spin.slice
            let swing = min(spin.slice * Config.spinTeaseSwingFraction, Config.spinTeaseSwingMax)
            let turns = path.segments.map { spin.sign * $0.to }
            // 止まる角度の手前で止まりかけ、隣（1 つ前）のスライスの手前の境目は越えずに戻り、
            // 進み直して k·w だけ行き過ぎてから止まる
            #expect(turns[0] < stop)
            #expect(stop - turns[0] <= Config.spinTeaseCreepMax + 1e-9)
            #expect(turns[1] < turns[0])
            #expect(turns[1] > boundary - spin.slice)
            #expect(turns[0] - turns[1] <= Config.spinTeaseRollBackMax + 1e-9)
            #expect(abs(turns[2] - (stop + swing * Config.spinTeaseSwingDecay)) < 1e-9)
            #expect(abs(turns[3] - stop) < 1e-9)
            let angles = forwardAngles(path, sign: spin.sign)
            #expect(abs((angles.max() ?? 0) - turns[2]) < 1e-6)
            #expect(spin.sign * path.angularVelocity(at: Config.spinDuration + 0.2) < 0)
        }
    }

    @Test func 行き過ぎは行き過ぎ戻り過ぎ少し行き過ぎて止まる() {
        for spin in Self.cases() {
            let path = SpinPath.teased(.overshoot, from: spin.from, to: spin.to, count: spin.count)
            #expect(path.segments.count == 4)
            let stop = spin.sign * spin.to
            let overshoot = min(spin.slice * Config.spinTeaseOvershootFraction, Config.spinTeaseOvershootMax)
            let decay = Config.spinTeaseSwingDecay
            let turns = path.segments.map { spin.sign * $0.to }
            #expect(turns[0] > stop)
            // 隣のスライスには入ってもよいが、その次には入らない
            #expect(turns[0] - stop < spin.slice)
            #expect(abs(turns[0] - stop - overshoot) < 1e-9)
            #expect(abs(turns[1] - (stop - overshoot * decay)) < 1e-9)
            #expect(abs(turns[2] - (stop + overshoot * decay * decay)) < 1e-9)
            #expect(abs(turns[3] - stop) < 1e-9)
            let angles = forwardAngles(path, sign: spin.sign)
            #expect(abs((angles.max() ?? 0) - turns[0]) < 1e-6)
            #expect(spin.sign * path.angularVelocity(at: Config.spinDuration + 0.6) < 0)
        }
    }

    @Test(arguments: SpinTease.allCases, [2, 3, 8, 24])
    func 振れ幅はスライス幅に収まる(tease: SpinTease, count: Int) {
        let slice = 360 / Double(count)
        let approach = min(slice * Config.spinTeaseApproachFraction, Config.spinTeaseApproachMax)
        let back = min(slice * Config.spinTeaseRollBackFraction, Config.spinTeaseRollBackMax)
        let overshoot = min(slice * Config.spinTeaseOvershootFraction, Config.spinTeaseOvershootMax)
        let swing = min(slice * Config.spinTeaseSwingFraction, Config.spinTeaseSwingMax)
        // 戻りは隣（1 つ前）のスライスの中に収まり、行き過ぎは隣（1 つ先）のスライスの中に収まる
        #expect(approach + back < slice)
        #expect(overshoot < slice)
        #expect(swing < slice)
        // 境目すれすれ（直後・直前・ちょうど）でも最終角は変わらず、区間はそれぞれの向きに単調に進む
        for offset in [0, 1e-9, slice / 2, slice - 1e-9] {
            let to = 1440 + 5 * slice + offset
            let path = SpinPath.teased(tease, from: 0, to: to, count: count)
            #expect(path.tease == tease)
            #expect(abs(path.to - to) < 1e-12)
            for segment in path.segments {
                #expect(segment.from != segment.to)
            }
        }
    }

    // MARK: 隣のスライスまでの振れ幅

    @Test(arguments: SpinTease.allCases, [2, 3, 5, 8, 12, 24, 36])
    func 焦らしの区間は隣のスライスまでで隣の1つ先には入らない(tease: SpinTease, count: Int) {
        let slice = 360 / Double(count)
        for sign in [1.0, -1.0] {
            // 止まる位置をスライスの端から端まで動かす（境目の直後・中ほど・直前）
            for offset in [1e-9, 0.01, 0.25, 0.5, 0.75, 0.99].map({ $0 * slice }) {
                let stop = 1440 + 5 * slice + offset
                let boundary = 1440 + 5 * slice
                let path = SpinPath.teased(tease, from: sign * 0.5, to: sign * stop, count: count)
                #expect(path.tease == tease)
                // 主の区間の終わりから止まるまで、手前の隣のスライスの始まり（B − スライス幅）より先、
                // 先の隣のスライスの終わり（B + 2 × スライス幅）より手前にいる
                for step in 0...Int(Config.spinTeaseDuration * 1000) {
                    let angle = sign * path.angle(at: Config.spinDuration + Double(step) / 1000)
                    #expect(angle > boundary - slice)
                    #expect(angle < boundary + 2 * slice)
                }
            }
        }
    }

    @Test(arguments: [SpinDirection.clockwise, .counterclockwise])
    func 戻りかけは止まるスライスの中で止まりかけると境目を越えて隣まで戻る(direction: SpinDirection) {
        let sign: Double = direction == .clockwise ? 1 : -1
        let count = 2
        let slice = 180.0
        // 境目の 12° 先に止まる。止まりかける角度は止まる角度の `spinTeaseCreepMax`（10°）手前（境目の 2° 先）で、
        // そこから `spinTeaseRollBackMax`（7°）戻るので、境目を越えて手前の隣のスライスに入ってから戻る
        let boundary = 1440 + slice
        let path = SpinPath.teased(.rollBack, from: sign * 0.5, to: sign * (boundary + 12), count: count)
        let turn = sign * path.segments[0].to
        let bottom = sign * path.segments[1].to
        #expect(abs(turn - (boundary + 12 - Config.spinTeaseCreepMax)) < 1e-9)
        #expect(abs(turn - bottom - Config.spinTeaseRollBackMax) < 1e-9)
        #expect(bottom < boundary)
        // 境目は主の区間で越え、戻りで越え、進み直して越える（往復とも数える）
        let crossings = path.boundaryCrossings(count: count, minInterval: 0)
        let atBoundary = crossings.filter { abs(path.angle(at: $0) - sign * boundary) < 1e-6 }
        #expect(atBoundary.count == 3)
        #expect(atBoundary.filter { $0 > Config.spinDuration }.count == 2)
        #expect(crossings.count == sampledCrossings(path, count: count))
    }

    @Test(arguments: [SpinDirection.clockwise, .counterclockwise])
    func 行き過ぎは広いスライスでも上限まで振れて隣のスライスに入る(direction: SpinDirection) {
        let sign: Double = direction == .clockwise ? 1 : -1
        let count = 8
        let slice = 45.0
        // 境目の 35° 先（次の境目の 10° 手前）に止まる。行き過ぎは上限の `spinTeaseOvershootMax`（14°）で、次の境目を越えて戻る
        // （戻り過ぎ・少し行き過ぎは止まる角度のまわり 5.6°・2.24° で、境目には届かない）
        let next = 1440 + 2 * slice
        let to = sign * (next - 10)
        let path = SpinPath.teased(.overshoot, from: sign * 0.5, to: to, count: count)
        let peak = sign * path.segments[0].to
        #expect(abs(peak - (next - 10 + Config.spinTeaseOvershootMax)) < 1e-9)
        #expect(peak > next)
        #expect(peak < next + slice)
        let crossings = path.boundaryCrossings(count: count, minInterval: 0)
        let atNext = crossings.filter { abs(path.angle(at: $0) - sign * next) < 1e-6 }
        #expect(atNext.count == 2)
        #expect(crossings.count == sampledCrossings(path, count: count))
    }

    @Test(arguments: [(2, false), (8, false), (30, true), (36, true)])
    func 狭いスライスでは振れ幅をスライス幅の割合で抑える(count: Int, narrow: Bool) {
        let slice = 360 / Double(count)
        let back = min(slice * Config.spinTeaseRollBackFraction, Config.spinTeaseRollBackMax)
        let overshoot = min(slice * Config.spinTeaseOvershootFraction, Config.spinTeaseOvershootMax)
        if narrow {
            // 30 件（12°）・36 件（10°）では上限より割合の方が小さい
            #expect(back < Config.spinTeaseRollBackMax)
            #expect(overshoot < Config.spinTeaseOvershootMax)
        } else {
            #expect(abs(back - Config.spinTeaseRollBackMax) < 1e-9)
            #expect(abs(overshoot - Config.spinTeaseOvershootMax) < 1e-9)
        }
        // スライスの中ほどに止まるスピンで、実際の振れ幅がその値になる
        let to = 1440 + 3 * slice + slice / 2
        let rollBack = SpinPath.teased(.rollBack, from: 0.5, to: to, count: count)
        #expect(abs(rollBack.segments[0].to - rollBack.segments[1].to - back) < 1e-9)
        let overshot = SpinPath.teased(.overshoot, from: 0.5, to: to, count: count)
        #expect(abs(overshot.segments[0].to - to - overshoot) < 1e-9)
        let swing = min(slice * Config.spinTeaseSwingFraction, Config.spinTeaseSwingMax)
        #expect(narrow == (swing < Config.spinTeaseSwingMax))
        let hesitated = SpinPath.teased(.hesitate, from: 0.5, to: to, count: count)
        #expect(abs(hesitated.segments[1].to - to - swing) < 1e-9)
    }

    // MARK: 境目を越える時刻

    @Test(arguments: SpinTease.allCases)
    func 境目は往復とも数え時刻にちょうど境目にある(tease: SpinTease) {
        for spin in Self.cases() {
            let path = SpinPath.teased(tease, from: spin.from, to: spin.to, count: spin.count)
            let crossings = path.boundaryCrossings(count: spin.count, minInterval: 0)
            #expect(crossings.count == sampledCrossings(path, count: spin.count))
            for (a, b) in zip(crossings, crossings.dropFirst()) {
                #expect(b >= a)
            }
            for time in crossings {
                let angle = path.angle(at: time)
                let nearest = (angle / spin.slice).rounded() * spin.slice
                #expect(abs(angle - nearest) < 1e-6)
            }
        }
    }

    @Test(arguments: [SpinDirection.clockwise, .counterclockwise])
    func 行き過ぎで隣のスライスに出入りすると往復のたびに数える(direction: SpinDirection) {
        let sign: Double = direction == .clockwise ? 1 : -1
        let count = 24
        let slice = 15.0
        // 止まる角度が境目の 1 度手前なので、9 度（スライス幅の 60%）の行き過ぎで次の境目を越えて戻り、
        // 3.6 度戻り過ぎたあと 1.44 度の少し行き過ぎでもう一度越えて戻る
        let to = sign * (1440 + 7 * slice + slice - 1)
        // 始点はどの境目にも置かない（境目ちょうどから回り出すと、数え方の端の扱いが向きで違う）
        let path = SpinPath.teased(.overshoot, from: sign * 0.5, to: to, count: count)
        let crossings = path.boundaryCrossings(count: count, minInterval: 0)
        let next = sign * (1440 + 8 * slice)
        let atNext = crossings.filter { abs(path.angle(at: $0) - next) < 1e-6 }
        #expect(atNext.count == 4)
        #expect(atNext.filter { $0 < Config.spinDuration }.count == 1)
        #expect(atNext.filter { $0 > Config.spinDuration }.count == 3)
        #expect(crossings.count == sampledCrossings(path, count: count))
    }

    @Test(arguments: SpinTease.allCases)
    func 間引きは全体で掛ける(tease: SpinTease) {
        for spin in Self.cases() {
            let path = SpinPath.teased(tease, from: spin.from, to: spin.to, count: spin.count)
            let raw = path.boundaryCrossings(count: spin.count, minInterval: 0)
            for interval in [Config.clickMinInterval, Config.hapticMinInterval] {
                let thinned = path.boundaryCrossings(count: spin.count, minInterval: interval)
                #expect(!thinned.isEmpty)
                #expect(abs((thinned.first ?? -1) - (raw.first ?? -2)) < 1e-12)
                for (a, b) in zip(thinned, thinned.dropFirst()) {
                    #expect(b - a >= interval - 1e-12)
                }
                #expect(thinned.allSatisfy { time in raw.contains { abs($0 - time) < 1e-12 } })
                #expect(SpinTicks.boundaryCrossings(along: path, count: spin.count, minInterval: interval) == thinned)
                #expect(HapticSchedule.boundaryCrossings(along: path, count: spin.count, minInterval: interval) == thinned)
            }
        }
    }

    // MARK: 選び方

    @Test func 同じ乱数なら同じ動き() {
        for spin in Self.cases() {
            for seed in Self.seeds {
                var first = SeededGenerator(seed: seed)
                var second = SeededGenerator(seed: seed)
                let a = SpinPath.spin(from: spin.from, to: spin.to, count: spin.count, effects: .all, using: &first)
                let b = SpinPath.spin(from: spin.from, to: spin.to, count: spin.count, effects: .all, using: &second)
                #expect(a == b)
                #expect(a.tease != nil)
            }
        }
    }

    @Test func 入り方は乱数だけで選ぶ() {
        // 同じ乱数なら、最終角（止まるスライス）が違っても同じ入り方になる。指定の有無は最終角にしか効かないので、
        // 指定を付けた/付けないスピンでも同じ乱数なら同じ焦らしになる
        for seed in Self.seeds {
            var reference = SeededGenerator(seed: seed)
            let expected = SpinTease.random(using: &reference)
            for spin in Self.cases() {
                var rng = SeededGenerator(seed: seed)
                let path = SpinPath.spin(from: spin.from, to: spin.to, count: spin.count, effects: SpinEffectsFixtures.lights, using: &rng)
                #expect(path.tease == expected)
            }
        }
    }

    @Test func 入り方は3通りに散る() {
        var tally: [SpinTease: Int] = [:]
        for seed in UInt64(0)..<300 {
            var rng = SeededGenerator(seed: seed)
            tally[SpinTease.random(using: &rng), default: 0] += 1
        }
        for tease in SpinTease.allCases {
            #expect((tally[tease] ?? 0) > 60)
        }
    }

    @Test(arguments: SpinEffectsFixtures.withCommon)
    func なし以外のスタイルでは毎回入れる(effects: SpinEffects) {
        for spin in Self.cases() {
            var rng = SeededGenerator(seed: 5)
            let path = SpinPath.spin(from: spin.from, to: spin.to, count: spin.count, effects: effects, using: &rng)
            #expect(path.tease != nil)
            #expect(abs(path.duration - Self.teaseDuration) < 1e-9)
            #expect(abs(path.to - spin.to) < 1e-9)
        }
    }

    // MARK: なし

    @Test func なしでは今のスピンと同じ動き() {
        for spin in Self.cases() {
            for release: Double? in [nil, spin.sign * 900] {
                var rng = SeededGenerator(seed: 3)
                let path = SpinPath.spin(
                    from: spin.from, to: spin.to, count: spin.count, effects: .none, releaseVelocity: release, using: &rng
                )
                let easing = if let release {
                    FlickSpin.easing(angularVelocity: release, distance: abs(spin.to - spin.from), duration: Config.spinDuration)
                } else {
                    Config.spinEasing
                }
                let motion = SpinMotion(from: spin.from, to: spin.to, duration: Config.spinDuration, easing: easing)
                #expect(path == SpinPath(motion))
                #expect(path.tease == nil)
                for step in 0...45 {
                    let elapsed = Double(step) / 10
                    #expect(abs(path.angle(at: elapsed) - motion.angle(at: elapsed)) < 1e-9)
                    #expect(abs(path.angularVelocity(at: elapsed) - motion.angularVelocity(at: elapsed)) < 1e-9)
                }
                let ticks = SpinTicks.boundaryCrossings(
                    from: spin.from, to: spin.to, count: spin.count, duration: Config.spinDuration,
                    easing: easing, minInterval: Config.clickMinInterval
                )
                #expect(path.boundaryCrossings(count: spin.count, minInterval: Config.clickMinInterval) == ticks)
                let haptics = HapticSchedule.boundaryCrossings(
                    from: spin.from, to: spin.to, count: spin.count, duration: Config.spinDuration,
                    easing: easing, minInterval: Config.hapticMinInterval
                )
                #expect(path.boundaryCrossings(count: spin.count, minInterval: Config.hapticMinInterval) == haptics)
                // 乱数を引かない（モデルのほかの乱数の並びを変えない）
                var fresh = SeededGenerator(seed: 3)
                #expect(rng.next() == fresh.next())
            }
        }
    }

    // MARK: 区分の動き

    @Test func 区間の始まる時刻と範囲外() {
        let path = SpinPath.teased(.rollBack, from: 0, to: 1500, count: 8)
        let starts = path.startTimes
        #expect(starts.count == 4)
        #expect(abs(starts[0]) < 1e-12)
        #expect(abs(starts[1] - Config.spinDuration) < 1e-9)
        let shares = Config.spinTeaseRollBackShares
        #expect(abs(starts[2] - (Config.spinDuration + Config.spinTeaseDuration * shares[0])) < 1e-9)
        #expect(abs(starts[3] - (Config.spinDuration + Config.spinTeaseDuration * (shares[0] + shares[1]))) < 1e-9)
        #expect(abs(path.angle(at: -1)) < 1e-12)
        #expect(abs(path.angularVelocity(at: -1)) < 1e-12)
        #expect(abs(path.angularVelocity(at: path.duration + 1)) < 1e-12)
        #expect(abs(path.intensity(at: path.duration + 1)) < 1e-12)
        #expect(path.intensity(at: 0.1) > 0)
    }

    @Test func 回る距離が短すぎれば焦らしを入れず同じ長さ() {
        // スライス 1 つ分も回らず、止まりかける角度（境目の手前・止まる角度の `spinTeaseCreepMax` 手前）が回り始めより手前になる
        let path = SpinPath.teased(.hesitate, from: 0, to: 3, count: 2)
        #expect(path.tease == nil)
        #expect(path.segments.count == 1)
        #expect(abs(path.duration - Self.teaseDuration) < 1e-9)
        #expect(abs(path.to - 3) < 1e-12)
    }

    // MARK: 補間の割合と開始時刻つきの動き

    @Test(arguments: SpinTease.allCases)
    func 補間の割合は角度を回る距離で割ったもの(tease: SpinTease) {
        for spin in Self.cases() {
            let path = SpinPath.teased(tease, from: spin.from, to: spin.to, count: spin.count)
            #expect(abs(path.progress(at: 0)) < 1e-12)
            #expect(abs(path.progress(at: path.duration) - 1) < 1e-12)
            #expect(abs(path.progress(at: path.duration + 1) - 1) < 1e-12)
            for step in 0...57 {
                let elapsed = Double(step) / 10
                let expected = (path.angle(at: elapsed) - spin.from) / (spin.to - spin.from)
                #expect(abs(path.progress(at: elapsed) - expected) < 1e-12)
            }
        }
    }

    @Test func 行き過ぎでは補間の割合が1を超えてから戻る() {
        let path = SpinPath.teased(.overshoot, from: 0, to: 1532, count: 8)
        #expect(path.progress(at: Config.spinDuration) > 1)
        #expect(abs(path.progress(at: path.duration) - 1) < 1e-12)
        // 回らない動きは常に止まった扱い
        let still = SpinPath(SpinMotion(from: 30, to: 30, duration: 1, easing: Config.spinEasing))
        #expect(still.progress(at: 0.5) == 1)
    }

    @Test func 開始時刻つきの動きは焦らしの区間の角度と角速度を引く() {
        let path = SpinPath.teased(.rollBack, from: 10, to: 1532, count: 8)
        let timed = TimedSpinMotion(path: path, start: 100)
        // 100 + elapsed - 100 は elapsed に丸めの誤差が乗るので、角度（千度単位）・角速度の差は 1e-11 ほど出る
        for step in 0...60 {
            let elapsed = Double(step) / 10
            #expect(abs(timed.angle(now: 100 + elapsed) - path.angle(at: elapsed)) < 1e-9)
            #expect(abs(timed.angularVelocity(now: 100 + elapsed) - path.angularVelocity(at: elapsed)) < 1e-9)
            #expect(abs(timed.intensity(now: 100 + elapsed) - path.intensity(at: elapsed)) < 1e-9)
        }
        // 戻る区間では角速度が負になる（電飾の流れも逆向きに引ける）
        #expect(timed.angularVelocity(now: 100 + Config.spinDuration + 0.2) < 0)
        // 長さは焦らしを含む
        #expect(timed.isMoving(now: 100 + Config.spinDuration + 1))
        #expect(!timed.isMoving(now: 100 + path.duration))
        #expect(abs(timed.remaining(now: 100 + Config.spinDuration) - Config.spinTeaseDuration) < 1e-9)
    }
}
