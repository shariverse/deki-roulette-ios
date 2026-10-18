import Foundation

/// 2D の盤面に重ねる光の尾と残像（`docs/SPEC.md` の §5.5）の、時刻と動き → 残像の角度・濃さと光の尾の長さ・濃さ。
/// 盤面が速く回っている間（演出の強さが `Config.wheelTrailThreshold` 以上）だけ出し、減速につれて薄くして閾値で 0 につなぐ。
/// 指で速く動かしている間も、その動き（`WheelDragMotion`）の角速度から同じように出す。
/// 入力は盤面の動き（自分で回る動きか指で動かしている動き）・時刻・角度・スライスの数・低電力モード・動きを減らす設定だけで、
/// 項目のラベル・指定（`targetId`）・印・止まったスライスは受け取らない。
enum WheelTrails {
    /// いちばん手前（遅れの少ない）の残像の不透明度（強さ 1 のとき）。後ろの残像ほど薄くする（`ghostOpacity`）。
    static let ghostPeakOpacity = 0.3
    /// 光の尾の頭（針の下）の不透明度（強さ 1 のとき）。尾の先へ向けて 0 まで薄くする。
    static let trailPeakOpacity = 0.85

    /// 盤面の残像 1 枚。
    struct Ghost: Equatable, Sendable {
        /// 残像を描く盤面の累積回転角（度）。今の角度から回転の向きと逆へずらしてある。
        var angle: Double
        /// 不透明度（0...1）。
        var opacity: Double
    }

    /// 外周に沿った光の尾。頭は針の位置（12 時）に置き、回転の向きと逆へ `length` 度伸ばす（回らない層に描く）。
    struct Trail: Equatable, Sendable {
        /// 尾の長さ（度、盤面の中心から見た角度）。
        var length: Double
        /// 頭の不透明度（0...1）。尾の先では 0。
        var opacity: Double
        /// 回転の向き。尾は逆へ伸びる（時計回りなら 12 時から反時計回りの側）。
        var direction: SpinDirection

        /// 尾が占める範囲（度、12 時を 0 として時計回り）。`start < end` で、頭は時計回りなら `end`、反時計回りなら `start`。
        var range: ClosedRange<Double> {
            direction == .clockwise ? -length...0 : 0...length
        }

        /// 頭から尾に沿って `distance` 度の位置の不透明度。尾を `segments` 区間に等分して区間ごとに一定にし、頭の区間で `opacity`、
        /// 先の区間ほど（頭からの近さ）² で薄くする（いちばん先の区間は 1/segments の 2 乗）。尾の外（0 未満・長さ以上）は 0。
        /// 2D は区間ごとの弧を、3D は長さに依らない細かい弧の切れ端をこの値で塗るので、同じ位置は同じ濃さになる。
        func opacity(atDistance distance: Double, segments: Int) -> Double {
            guard segments > 0, length > 0, distance.isFinite, distance >= 0, distance < length else { return 0 }
            let index = min(Int(distance / (length / Double(segments))), segments - 1)
            let nearHead = Double(segments - index) / Double(segments)
            return opacity * nearHead * nearHead
        }
    }

    /// 1 フレームに描くもの。何も描かないときは `none`。
    struct Frame: Equatable, Sendable {
        /// 手前（遅れの少ない）から順の残像。
        var ghosts: [Ghost]
        var trail: Trail?

        static let none = Frame(ghosts: [], trail: nil)

        var isEmpty: Bool { ghosts.isEmpty && trail == nil }
    }

    /// 残像の枚数。低電力モードでは 1 枚に減らす。
    static func ghostCount(lowPower: Bool) -> Int {
        lowPower ? Config.wheelTrailLowPowerGhostCount : Config.wheelTrailMaxGhostCount
    }

    /// 演出の強さ（0...1）を光の尾・残像の濃さ（0...1）に写す。閾値未満は 0 で、閾値から 1 まで比例して濃くする
    /// （閾値ちょうどで 0 なので、減速して閾値を割るときに急に消えない）。
    static func strength(intensity: Double) -> Double {
        let threshold = Config.wheelTrailThreshold
        guard intensity.isFinite, intensity > threshold, threshold < 1 else { return 0 }
        return min((intensity - threshold) / (1 - threshold), 1)
    }

    /// `index` 枚目（0 が手前）の残像が、今からどれだけ前（秒）の盤面か。`Config.wheelTrailGhostWindow` を枚数で等分する
    /// （3 枚なら約 17・33・50 ミリ秒前、1 枚なら 50 ミリ秒前）。
    static func lag(index: Int, count: Int) -> TimeInterval {
        guard count > 0 else { return 0 }
        return Config.wheelTrailGhostWindow * Double(index + 1) / Double(count)
    }

    /// `index` 枚目（0 が手前）の残像の不透明度。濃さに比例し、後ろの残像ほど薄くする（3 枚なら 3/4・2/4・1/4、1 枚なら 1/2 を掛ける）。
    static func ghostOpacity(index: Int, count: Int, strength: Double) -> Double {
        guard count > 0 else { return 0 }
        let falloff = Double(count - index) / Double(count + 1)
        return ghostPeakOpacity * strength * falloff
    }

    /// いちばん後ろの残像をずらしてよい角度の上限（度）。`Config.wheelTrailMaxGhostOffset` と、スライス 1 枚の角度 ×
    /// `Config.wheelTrailMaxGhostSliceFraction` の小さい方（最高速でも残像が隣のスライスを越えてずれない）。
    static func maxGhostOffset(sliceCount: Int) -> Double {
        let slice = 360 / Double(max(sliceCount, 1))
        return min(Config.wheelTrailMaxGhostOffset, slice * Config.wheelTrailMaxGhostSliceFraction)
    }

    /// 遅れた時刻の角度との差（今の角度 − 遅れた角度、度）を、いちばん大きい差が上限に収まるようにそろえて縮める。
    /// 縮めるときも差どうしの比は保つので、残像は等間隔のまま並ぶ。向きは差の符号のまま（角速度が負ならずれも逆）。
    static func clampedOffsets(_ offsets: [Double], limit: Double) -> [Double] {
        let largest = offsets.map { abs($0) }.filter(\.isFinite).max() ?? 0
        guard largest > limit, largest > 0 else { return offsets.map { $0.isFinite ? $0 : 0 } }
        let ratio = max(limit, 0) / largest
        return offsets.map { $0.isFinite ? $0 * ratio : 0 }
    }

    /// 光の尾の長さ（度）。濃さに比例し、`Config.wheelTrailMaxLength` で最大。
    static func trailLength(strength: Double) -> Double {
        Config.wheelTrailMaxLength * min(max(strength, 0), 1)
    }

    /// 時刻 `now` に描くもの。`motion` は区間の列（`SpinPath`）の動きで、焦らしの区間も同じ時刻の角度・角速度で引く。
    /// 動きを減らす設定・盤面が自分で回っていない（`motion` が nil）・止まり切った・閾値未満のときは何も描かない。
    /// `dragRotation` は指で回した角度（回っている間はふつう 0）で、残像の角度に足す。
    static func frame(
        motion: TimedSpinMotion?,
        now: TimeInterval,
        dragRotation: Double = 0,
        sliceCount: Int,
        lowPower: Bool,
        reduceMotion: Bool
    ) -> Frame {
        frame(
            effect: motion.map(WheelEffectMotion.spin), now: now, dragRotation: dragRotation,
            sliceCount: sliceCount, lowPower: lowPower, reduceMotion: reduceMotion
        )
    }

    /// 時刻 `now` に描くもの。`effect` は盤面が自分で回る動き（スピン・惰性）か、指で動かしている動き（`WheelDragMotion`）。
    /// 動きを減らす設定・動きが無い・止まり切った・閾値未満のときは何も描かない。
    /// 残像は盤面に見えている角度（`WheelEffectMotion.displayedAngle`。指で動かしている間は `rotation + dragRotation`）から、
    /// その動きの基準の時刻（`WheelEffectMotion.offsetReferenceTime`。指で動かしている間は最後に指が動いた時刻）の角度と、
    /// そこから遅れた時刻の角度の差だけずらす。向きは角速度（指で動かしている間は平滑した値）の符号から取る。
    static func frame(
        effect: WheelEffectMotion?,
        now: TimeInterval,
        rotation: Double = 0,
        dragRotation: Double = 0,
        sliceCount: Int,
        lowPower: Bool,
        reduceMotion: Bool
    ) -> Frame {
        guard !reduceMotion, let effect, effect.isMoving(now: now) else { return .none }
        let strength = strength(intensity: effect.intensity(now: now))
        guard strength > 0 else { return .none }

        let velocity = effect.angularVelocity(now: now)
        let direction: SpinDirection = velocity < 0 ? .counterclockwise : .clockwise
        let displayed = effect.displayedAngle(now: now, rotation: rotation, dragRotation: dragRotation)
        // ずらしは盤面に見えている角度と同じ時刻から測る（ドラッグは最後に指が動いた時刻。指のイベントの間で伸び縮みしない）
        let reference = effect.offsetReferenceTime(now: now)
        let angle = effect.angle(now: reference)
        let count = ghostCount(lowPower: lowPower)
        let raw = (0..<count).map { angle - effect.angle(now: reference - lag(index: $0, count: count)) }
        let offsets = clampedOffsets(raw, limit: maxGhostOffset(sliceCount: sliceCount))
        let ghosts = offsets.enumerated().map { index, offset in
            Ghost(angle: displayed - offset, opacity: ghostOpacity(index: index, count: count, strength: strength))
        }
        let trail = Trail(length: trailLength(strength: strength), opacity: trailPeakOpacity * strength, direction: direction)
        return Frame(ghosts: ghosts, trail: trail)
    }

    /// 毎フレーム描き直す必要があるか（`TimelineView` を止める条件の反対）。盤面が動いている間（指で動かした動きの残りを含む）だけ動かし、
    /// 動きを減らす設定では止める。
    static func animates(reduceMotion: Bool, moving: Bool) -> Bool {
        !reduceMotion && moving
    }
}
