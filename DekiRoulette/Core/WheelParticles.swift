import CoreGraphics
import Foundation

/// 2D の盤面に重ねる針の先の火花と停止の瞬間の紙吹雪（`docs/SPEC.md` の §5.5）の、時刻 → 粒の位置・大きさ・濃さ。
/// 粒の状態はフレームごとに積み上げず、生まれた時刻からの経過と粒ごとの乱数だけで決める（どのフレームから描いても同じ絵になり、
/// 描画が遅れても溜まった計算が音・触覚の時刻を押し出さない）。粒ごとの乱数は、演出の開始時に引いた種（`seed(using:)`。
/// 乱数は注入できる）と粒の番号から作る `ParticleRandom` で引くので、同じ種なら毎フレーム同じ粒になる。
/// 入力は盤面が自分で回る動き・時刻・種・盤面の大きさ・低電力モード・動きを減らす設定だけで、項目・指定（`targetId`）・印・
/// 止まったスライスは受け取らない（紙吹雪は指定の有無・結果に依らず同じ）。
enum WheelParticles {
    // MARK: 火花

    /// 火花の初速（基準直径 `WheelLabel.referenceDiameter` での pt/秒）。強さ 1 で上の範囲、強さ 0 に近いほど `sparkSlowFactor` 倍に落とす。
    static let sparkSpeed: ClosedRange<Double> = 150...320
    static let sparkSlowFactor = 0.5
    /// 火花が飛ぶ向きの、盤面の表面が針の下を動く向き（時計回りなら右）から上へ持ち上げる角度の範囲（度）。
    static let sparkLift: ClosedRange<Double> = -10...55
    /// 火花の寿命の下限の割合（`Config.wheelSparkLifetime` に掛ける）。
    static let sparkMinLifeFraction = 0.6
    /// 火花に掛かる重力（基準直径での pt/秒²、下向き）。
    static let sparkGravity = 700.0
    /// 火花の半径（基準直径での pt）。
    static let sparkRadius: ClosedRange<Double> = 1.0...1.8
    /// 火花の尾の長さ（今の速度 × この秒数）。速く飛ぶ粒ほど長い筋になる。
    static let sparkStreakTime = 0.025

    /// 火花 1 粒。
    struct Spark: Equatable, Sendable {
        /// 今の位置（盤面の枠の左上を原点とする pt）。
        var position: CGPoint
        /// 尾の向きと長さ（今の位置から尾の先までのずれ、pt）。速度の逆向き。
        var tail: CGVector
        /// 半径（pt）。
        var radius: CGFloat
        /// 不透明度（0...1）。寿命の終わりへ向けて 0 にする。
        var opacity: Double
    }

    /// 同時に出す火花の上限。低電力モードでは 1/3。
    static func sparkCapacity(lowPower: Bool) -> Int {
        lowPower ? Config.wheelSparkMaxCount / Config.wheelParticleLowPowerDivisor : Config.wheelSparkMaxCount
    }

    /// 火花が生まれうる時刻の間隔（秒）。寿命の最大 ÷ 上限なので、寿命の間に生まれうるのは上限の数まで（同時に出る数は上限を超えない）。
    static func sparkSlotInterval(lowPower: Bool) -> TimeInterval {
        Config.wheelSparkLifetime / Double(sparkCapacity(lowPower: lowPower))
    }

    /// 時刻 `now` に出ている火花。盤面が自分で回っている動き（`motion`）の、生まれうる時刻ごとに、その時刻の強さ（0...1）の確率で
    /// 1 粒生まれる（数は強さに比例し、強さ 1 で上限）。粒は針の先 `origin` から盤面の表面が動く向きへ飛び、重力で落ちながら消える。
    /// 動きを減らす設定・動きが無い（指で動かしている間も含む）ときは何も出さない。
    /// - Parameters:
    ///   - scale: 盤面の直径 ÷ 基準直径。速さ・重力・大きさに掛ける。
    static func sparks(
        motion: TimedSpinMotion?,
        now: TimeInterval,
        seed: UInt64,
        origin: CGPoint,
        scale: CGFloat,
        lowPower: Bool,
        reduceMotion: Bool
    ) -> [Spark] {
        guard !reduceMotion, let motion, motion.motion.duration > 0 else { return [] }
        let elapsed = now - motion.start
        let interval = sparkSlotInterval(lowPower: lowPower)
        let lifetime = Config.wheelSparkLifetime
        // 寿命の間（elapsed - lifetime, elapsed] に生まれうる番号。動きの外（始まる前・止まり切ったあと）では生まれない
        let first = max(Int(((elapsed - lifetime) / interval).rounded(.down)) + 1, 0)
        let last = min(Int((elapsed / interval).rounded(.down)), Int((motion.motion.duration / interval).rounded(.up)) - 1)
        guard first <= last else { return [] }

        var sparks: [Spark] = []
        for slot in first...last {
            let birth = Double(slot) * interval
            var random = ParticleRandom(seed: seed, index: slot)
            guard let spark = spark(
                age: elapsed - birth,
                intensity: motion.motion.intensity(at: birth),
                velocity: motion.motion.angularVelocity(at: birth),
                origin: origin,
                scale: scale,
                using: &random
            ) else { continue }
            sparks.append(spark)
        }
        return Array(sparks.prefix(sparkCapacity(lowPower: lowPower)))
    }

    /// 生まれてから `age` 秒の火花 1 粒。生まれた時刻の強さ `intensity` の確率で生まれ（生まれなければ nil）、
    /// 生まれた時刻の角速度 `velocity` の符号で飛ぶ向き（時計回りなら右、反時計回りなら左）を決める。寿命を過ぎたら nil。
    static func spark<G: RandomNumberGenerator>(
        age: TimeInterval,
        intensity: Double,
        velocity: Double,
        origin: CGPoint,
        scale: CGFloat,
        using random: inout G
    ) -> Spark? {
        // 乱数を引く数は生まれるかどうかに依らず同じにする（同じ種なら同じ粒）
        let roll = Double.random(in: 0..<1, using: &random)
        let lifeFraction = Double.random(in: sparkMinLifeFraction...1, using: &random)
        let speedRoll = Double.random(in: sparkSpeed, using: &random)
        let lift = Double.random(in: sparkLift, using: &random)
        let radius = Double.random(in: sparkRadius, using: &random)
        let strength = min(max(intensity.isFinite ? intensity : 0, 0), 1)
        guard roll < strength, age >= 0 else { return nil }
        let life = Config.wheelSparkLifetime * lifeFraction
        guard age < life else { return nil }

        let scale = Double(scale)
        let speed = speedRoll * (sparkSlowFactor + (1 - sparkSlowFactor) * strength) * scale
        let sideways: Double = velocity < 0 ? -1 : 1
        let radians = lift * .pi / 180
        let vx = sideways * speed * cos(radians)
        let vy = -speed * sin(radians)
        let gravity = sparkGravity * scale
        let x = Double(origin.x) + vx * age
        let y = Double(origin.y) + vy * age + gravity * age * age / 2
        let currentVY = vy + gravity * age
        let progress = age / life
        return Spark(
            position: CGPoint(x: x, y: y),
            tail: CGVector(dx: -vx * sparkStreakTime, dy: -currentVY * sparkStreakTime),
            radius: CGFloat(radius * scale * (1 - 0.5 * progress)),
            opacity: (1 - progress) * (1 - progress)
        )
    }

    // MARK: 紙吹雪

    /// 紙吹雪がはじける位置（盤面の枠の大きさに対する割合。中心のやや上）。
    static let confettiOrigin = CGPoint(x: 0.5, y: 0.45)
    /// はじける位置の散らばり（基準直径での pt、中心からの半径）。
    static let confettiSpread = 24.0
    /// 初速（基準直径での pt/秒）と、真上から左右へ振る角度の範囲（度）。
    static let confettiSpeed: ClosedRange<Double> = 110...260
    static let confettiAngle: ClosedRange<Double> = -70...70
    /// 空気の抵抗（1/秒）。初速はこれで指数に弱まり、落ちる速さは `confettiFallSpeed` に近づく。
    static let confettiDrag = 2.4
    /// ひらひら落ちるときの落下の速さ（基準直径での pt/秒）。
    static let confettiFallSpeed = 70.0
    /// 左右に揺れる幅（基準直径での pt）と速さ（ラジアン/秒）。
    static let confettiSway = 6.0
    static let confettiSwayRate: ClosedRange<Double> = 5...9
    /// 紙片の大きさ（基準直径での pt）。
    static let confettiWidth: ClosedRange<Double> = 4...6
    static let confettiHeight: ClosedRange<Double> = 7...10
    /// 回る速さ（ラジアン/秒、向きは乱数）と、裏返る速さ（ラジアン/秒）。
    static let confettiSpinRate: ClosedRange<Double> = 3...9
    static let confettiFlipRate: ClosedRange<Double> = 6...12
    /// 粒ごとの寿命の下限の割合（`Config.wheelConfettiDuration` に掛ける）と、寿命のうち薄くし始める割合。
    static let confettiMinLifeFraction = 0.75
    static let confettiFadeStart = 0.7

    /// 紙吹雪 1 片。
    struct Confetto: Equatable, Sendable {
        /// 今の中心（盤面の枠の左上を原点とする pt）。
        var position: CGPoint
        /// 紙片の大きさ（pt）。裏返りは `flip` で幅に掛ける。
        var size: CGSize
        /// 回転（ラジアン、画面上の時計回りが正）。
        var rotation: Double
        /// 裏返り（幅に掛ける 0...1。0 に近いほど細く見える）。
        var flip: Double
        /// 色（`Theme.confettiColors` の添字）。
        var colorIndex: Int
        /// 不透明度（0...1）。
        var opacity: Double
    }

    /// 同時に出す紙吹雪の上限（1 回にはじける数）。低電力モードでは 1/3。
    static func confettiCapacity(lowPower: Bool) -> Int {
        lowPower ? Config.wheelConfettiMaxCount / Config.wheelParticleLowPowerDivisor : Config.wheelConfettiMaxCount
    }

    /// はじけてから `elapsed` 秒の紙吹雪。`Config.wheelConfettiDuration` を過ぎた・始まる前・動きを減らす設定では何も出さない。
    /// - Parameters:
    ///   - side: 盤面の枠の一辺（pt）。はじける位置はこれに対する割合で、速さ・大きさは基準直径との比で掛ける。
    ///   - colorCount: 色の数（`Theme.confettiColors.count`）。
    static func confetti(
        elapsed: TimeInterval,
        seed: UInt64,
        side: CGFloat,
        colorCount: Int,
        lowPower: Bool,
        reduceMotion: Bool
    ) -> [Confetto] {
        guard !reduceMotion, elapsed >= 0, elapsed < Config.wheelConfettiDuration, colorCount > 0 else { return [] }
        let origin = CGPoint(x: side * confettiOrigin.x, y: side * confettiOrigin.y)
        let scale = side / CGFloat(WheelLabel.referenceDiameter)
        return (0..<confettiCapacity(lowPower: lowPower)).compactMap { index in
            var random = ParticleRandom(seed: seed, index: index)
            return confetto(
                age: elapsed, origin: origin, scale: scale, colorCount: colorCount, using: &random
            )
        }
    }

    /// はじけてから `age` 秒の紙片 1 枚。寿命を過ぎたら nil。
    static func confetto<G: RandomNumberGenerator>(
        age: TimeInterval,
        origin: CGPoint,
        scale: CGFloat,
        colorCount: Int,
        using random: inout G
    ) -> Confetto? {
        let spreadAngle = Double.random(in: 0..<(2 * .pi), using: &random)
        let spreadRadius = confettiSpread * Double.random(in: 0...1, using: &random).squareRoot()
        let speed = Double.random(in: confettiSpeed, using: &random)
        let angle = Double.random(in: confettiAngle, using: &random) * .pi / 180
        let swayRate = Double.random(in: confettiSwayRate, using: &random)
        let swayPhase = Double.random(in: 0..<(2 * .pi), using: &random)
        let width = Double.random(in: confettiWidth, using: &random)
        let height = Double.random(in: confettiHeight, using: &random)
        let spinRate = Double.random(in: confettiSpinRate, using: &random) * (Bool.random(using: &random) ? 1 : -1)
        let spinPhase = Double.random(in: 0..<(2 * .pi), using: &random)
        let flipRate = Double.random(in: confettiFlipRate, using: &random)
        let flipPhase = Double.random(in: 0..<(2 * .pi), using: &random)
        let colorIndex = Int.random(in: 0..<max(colorCount, 1), using: &random)
        let lifeFraction = Double.random(in: confettiMinLifeFraction...1, using: &random)
        let life = Config.wheelConfettiDuration * lifeFraction
        guard age >= 0, age < life else { return nil }

        let scale = Double(scale)
        // 抵抗のある放物運動の閉じた式。速度は初速から落下の速さ（下向き）へ指数で寄る
        let vx = speed * sin(angle) * scale
        let vy = -speed * cos(angle) * scale
        let fall = confettiFallSpeed * scale
        let decay = (1 - exp(-confettiDrag * age)) / confettiDrag
        let x = Double(origin.x) + spreadRadius * scale * cos(spreadAngle) + vx * decay
            + confettiSway * scale * sin(swayRate * age + swayPhase)
        let y = Double(origin.y) + spreadRadius * scale * sin(spreadAngle) + (vy - fall) * decay + fall * age
        let progress = age / life
        let opacity = progress < confettiFadeStart ? 1 : max(1 - (progress - confettiFadeStart) / (1 - confettiFadeStart), 0)
        return Confetto(
            position: CGPoint(x: x, y: y),
            size: CGSize(width: width * scale, height: height * scale),
            rotation: spinPhase + spinRate * age,
            flip: max(abs(cos(flipPhase + flipRate * age)), 0.15),
            colorIndex: colorIndex,
            opacity: opacity
        )
    }

    // MARK: 共通

    /// 演出を始めるときに引く種。乱数は注入できる（画面では `SystemRandomNumberGenerator`、テストでは固定の種）。
    static func seed<G: RandomNumberGenerator>(using random: inout G) -> UInt64 {
        random.next()
    }

    /// 毎フレーム描き直す必要があるか（`TimelineView` を止める条件の反対）。盤面が自分で回っている間か、紙吹雪が出ている間だけ動かし、
    /// 動きを減らす設定では止める。
    static func animates(reduceMotion: Bool, moving: Bool, bursting: Bool) -> Bool {
        !reduceMotion && (moving || bursting)
    }
}

/// 粒ごとの乱数。演出の種と粒の番号から決まる SplitMix64 で、同じ種・番号なら毎フレーム同じ値を返す。
struct ParticleRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64, index: Int) {
        // 番号ごとに種を散らす（黄金比の定数を掛けて足す）
        state = seed ^ (UInt64(bitPattern: Int64(index)) &* 0x9E37_79B9_7F4A_7C15)
        _ = next()
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
