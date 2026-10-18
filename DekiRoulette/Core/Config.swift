import Foundation
import SwiftUI

/// ドメイン定数。Web 版 `src/config.ts` に対応する。
enum Config {
    static let spinDuration: TimeInterval = 4.5

    /// アニメーション完了コールバックが呼ばれない環境（バックグラウンド等）向けの保険。
    static let spinFallback: TimeInterval = spinDuration + 0.6
    static let reducedMotionSpinDuration: TimeInterval = 0.32

    static let minItems = 2
    static let maxItems = 24
    static let maxLabelLength = 20

    /// 当たり指定の隠しジェスチャ。短すぎると通常のタップで誤爆する。
    static let longPressDuration: TimeInterval = 0.6

    /// 指定直後だけ印を見せる時間。以降はリストに触れない限り痕跡を残さない。
    static let targetHintDuration: TimeInterval = 1.6

    /// 順番の結果を 1 件ずつ出すときの間隔。
    static let orderRevealStep: TimeInterval = 0.16

    /// 結果 1 件が現れるアニメーションの長さ。演出の終了時刻の計算に使う。
    static let revealAnimationDuration: TimeInterval = 0.36

    /// 視差効果を減らす設定のときは 1 件ずつ出さないので、演出はこの時間で終わる。
    static let reducedMotionRevealDuration: TimeInterval = 0.2

    /// コピーできたことを伝える表示を出しておく時間。
    static let copyFeedbackDuration: TimeInterval = 1.8

    /// スピンのイージング（Web 版 `SPIN_EASING`）。`Theme.spinAnimation` と、触覚とクリック音の時刻の逆算で使う。
    static let spinEasing = CubicBezierCurve(0.15, 0.85, 0.3, 1)

    /// 追加の入力欄が伸びる行数の上限。改行区切りの貼り付けはこの行数を超えるとスクロールする。
    static let bulkInputVisibleLines = 5
    /// 名前を付けて保存できる項目リストの数。
    static let maxSavedLists = 20
    /// 保存するリストの名前の最大文字数（正規化後）。
    static let maxSavedListNameLength = 30

    /// スピンの周回数の範囲。フリックの強さもこの範囲の中に写す。
    static let fullSpinRange: ClosedRange<Int> = 4...8

    /// 盤面のフリックをスピンとみなす角速度（度/秒）の下限。これ未満ではスピンを始めず、少し惰性で回して止める（`FlickCoast`）。
    static let flickMinAngularVelocity: Double = 240

    /// 閾値未満で離したときに惰性で回る角度の係数（秒）。回る角度 = 離した角速度（度/秒）× これ（`FlickCoast`）。
    /// 閾値ちょうどの手前で 60 度ほど回る。止まるまでの時間は 2 倍の 0.5 秒（等減速なので角速度に依らない）。
    static let flickCoastFactor: TimeInterval = 0.25

    /// 惰性で回る角度の上限（度）。
    static let flickCoastMaxAngle: Double = 60

    /// 惰性で回る角度がこれ未満（止めてから離した）なら、惰性を付けずに離した角度のまま止める（度）。
    static let flickCoastMinAngle: Double = 3

    /// 周回数が上限に達する角速度（度/秒）。これ以上はすべて最大の周回数になる。
    static let flickMaxAngularVelocity: Double = 1800

    /// 盤面中心からこの半径（pt）の内側では角度が定まらないので、フリックの計算に使わない。
    static let flickDeadZoneRadius: Double = 24

    /// フリックの角速度を、指を離す直前のこの時間（秒）に回った角度から求める。
    static let flickSampleWindow: TimeInterval = 0.15

    // MARK: スピンの演出

    /// 速さに連動する演出の強さが 1（最大）になる角速度（度/秒）。これ未満は角速度に比例して弱める（`SpinEffectIntensity`）。
    static let effectFullIntensityVelocity: Double = 720

    /// 演出用にドラッグ中の角速度を滑らかにする時定数（秒）。フレームごとに新しい値へこの時間で約 63% 寄せる。
    static let effectSmoothingTime: TimeInterval = 0.08

    /// 指で盤面を動かしている間の演出（`WheelDragMotion`）で、最後に指が動いてからこの時間（秒）がたったら止まり切ったとみなす。
    /// 角速度は窓（`flickSampleWindow`）の 0.15 秒で 0 に落ち、平滑の残り（時定数 0.08 秒）も 0.35 秒で約 1% になる。
    /// 火花の寿命の最大（`wheelSparkLifetime`）と同じなので、最後に生まれた火花も消え切る。
    static let dragEffectSettleTime: TimeInterval = 0.5

    /// 指で盤面を動かしている間の演出で、指の位置の記録を残す長さ（秒）。演出が引く過去の時刻（火花の寿命 + 窓）より長くする。
    static let dragEffectHistory: TimeInterval = 1.0

    /// 2D の盤面の外周に並べる電飾の数（`WheelLights`）。12 時から時計回りに等間隔に置く。
    static let wheelLightCount = 24

    /// 電飾の光の並びが流れる角度の、盤面の回転角に対する比（`WheelLights.phase`）。並びは盤面の 1/4 の速さで同じ向きに流れる。
    /// 盤面が 1 周したとき並びが元に戻るよう、`wheelLightCount` × これは `WheelLights.litStride` の倍数にする（24 × 0.25 = 6）。
    static let wheelLightFlowFactor = 0.25

    /// 電飾の光の並びが 1 フレームに進む上限（電球の個数）。速く回すと並びが 1 フレームに大きく飛び、流れではなく明滅に見えるので抑える
    /// （並びは 3 個おきなので、1.5 個で向きが分からなくなる）。上限を超える速さでは並びが盤面より遅れて流れる（`WheelLights.Flow`）。
    static let wheelLightMaxFlowPerFrame = 0.5

    /// 電飾の光の並びが盤面より遅れてよい上限（電球の個数）。1 フレームの上限で流し切れなかった分はここまで次の描き直しに持ち越して追いつかせ、
    /// 超える分は捨てる。指で動かしている間は指の動き（親の描き直し）と `TimelineView` の描き直しの時刻がずれ、角度が変わった描き直しの
    /// 経過時間が短くなるので、持ち越さないと上限より遅い動きでも流れを捨ててしまう。1 個（盤面で 60 度）は上限の速さの 2 フレーム分で、
    /// 速く回したあとも 2 フレームで追いつく（`WheelLights.Flow`）。
    static let wheelLightMaxFlowLag = 1.0

    /// 演出の上限を時間あたりに直すときの 1 フレームの長さ（秒）。iPhone のアプリは 60Hz で描くので 1/60 秒
    /// （120Hz・90Hz の画面では 1 フレームあたりはもっと小さくなる）。
    static let effectReferenceFrameInterval: TimeInterval = 1.0 / 60

    /// 停止の瞬間の電飾の全灯の点滅の周期（秒）と回数。0.6 秒周期の 2 回（停止の瞬間と 0.6 秒後が明るい）で、
    /// 停止の瞬間のフラッシュと 1 回目を重ねるので、合わせても 1 秒に 3 回未満の明滅に収まる。
    static let wheelLightBlinkPeriod: TimeInterval = 0.6
    static let wheelLightBlinkCount = 2

    /// 結果表示中に電飾の全灯がゆっくり脈打つ周期（秒）。止まったスライスの光彩の余韻（`WheelStopEffects`）も同じ周期・同じ位相で脈打つ。
    static let wheelLightAfterglowPeriod: TimeInterval = 2.4

    /// 停止の瞬間のフラッシュ（`WheelStopEffects.flashOpacity`）が消えるまでの長さ（秒）。1 回だけ光らせる。
    static let stopFlashDuration: TimeInterval = 0.25

    /// 脈動だけを描いている間（電飾の点滅の後・光彩の余韻）の描き直しの最短間隔（秒）。周期 2.4 秒のゆっくりした変化なので、
    /// 毎フレームでなくても段差は見えない（1 回の変化は不透明度で 0.04 未満）。
    static let effectPulseFrameInterval: TimeInterval = 1.0 / 20

    /// 止まり際の焦らし（`SpinTease`）でスピンに足す長さ（秒）。焦らしを入れるスピンは入り方に依らず
    /// `spinDuration + spinTeaseDuration`（5.7 秒）で、主の区間は `spinDuration` のまま。
    static let spinTeaseDuration: TimeInterval = 1.2

    /// 焦らしを入れたスピンの完了の保険（`spinFallback` と同じく、長さの 0.6 秒後）。
    static let spinTeaseFallback: TimeInterval = spinDuration + spinTeaseDuration + 0.6

    /// 焦らしの区間の曲線（ease-in-out）。始点・終点の傾きが 0 なので、主の区間（終点の傾きが 0 の `spinEasing`）や
    /// 前後の焦らしの区間と角速度 0 でつながる。
    static let spinTeaseEasing = CubicBezierCurve(0.42, 0, 0.58, 1)

    /// ためらい・戻りかけで主の区間を止める、止まるスライスに入る境目の手前の距離。スライス幅に対する割合と上限（度）の小さい方。
    static let spinTeaseApproachFraction: Double = 0.25
    static let spinTeaseApproachMax: Double = 5

    /// ためらい・戻りかけの焦らしの区間で、止まりかけた角度から止まる角度まで進む距離の上限（度）。広いスライスの奥で止まるときも、
    /// 止まりかけてから加速し直して大きく回らないようにする（`docs/SPEC.md` §5.5）。
    static let spinTeaseCreepMax: Double = 12

    /// 戻りかけで戻る角度。スライス幅に対する割合と上限（度）の小さい方。手前の距離と足してもスライス幅の半分に収まり、
    /// 戻りで 1 つ前の境目を越えない。
    static let spinTeaseRollBackFraction: Double = 0.2
    static let spinTeaseRollBackMax: Double = 3

    /// 戻りかけの焦らしの長さのうち、戻る区間に使う割合。残りで越えて止まる。
    static let spinTeaseRollBackShare: Double = 1.0 / 3

    /// 行き過ぎで止まる角度を越える角度。スライス幅に対する割合と上限（度）の小さい方。スライス幅未満なので、
    /// 隣のスライスに入ることはあってもその次には入らない。
    static let spinTeaseOvershootFraction: Double = 0.4
    static let spinTeaseOvershootMax: Double = 8

    /// 光の尾・残像（`WheelTrails`）を出し始める演出の強さ（0...1）。これ未満では出さず、ここから 1 まで比例して濃くする。
    static let wheelTrailThreshold = 0.35

    /// 盤面の残像の枚数の上限と、低電力モードでの枚数。
    static let wheelTrailMaxGhostCount = 3
    static let wheelTrailLowPowerGhostCount = 1

    /// いちばん後ろの残像が今から何秒前の盤面か。手前の残像はこれを枚数で等分した時刻（3 枚なら約 17・33・50 ミリ秒前）。
    static let wheelTrailGhostWindow: TimeInterval = 0.05

    /// いちばん後ろの残像をずらす角度の上限（度）と、スライス 1 枚の角度に対する上限の比。小さい方を使い、
    /// 最高速（2000°/秒を超える）でも残像が隣のスライスを越えてずれないようにする。
    static let wheelTrailMaxGhostOffset: Double = 18
    static let wheelTrailMaxGhostSliceFraction = 0.6

    /// 光の尾の長さの最大（度、強さ 1 のとき）。
    static let wheelTrailMaxLength: Double = 120

    /// 針の先の火花（`WheelParticles`）と停止の瞬間の紙吹雪の、同時に出す粒子の数の上限。
    static let wheelSparkMaxCount = 60
    static let wheelConfettiMaxCount = 80

    /// 低電力モードで粒子の数の上限を割る数（上限の 1/3。火花 20・紙吹雪 26）。
    static let wheelParticleLowPowerDivisor = 3

    /// 火花 1 粒の寿命の最大（秒）。この間に生まれた分だけが同時に出ているので、生まれる間隔は これ ÷ 上限（`WheelParticles.sparkSlotInterval`）。
    static let wheelSparkLifetime: TimeInterval = 0.5

    /// 紙吹雪がはじけてから消え切るまでの長さ（秒）。粒ごとの寿命はこれ以下。
    static let wheelConfettiDuration: TimeInterval = 1.6

    /// 削除した項目を「元に戻す」で戻せる時間。過ぎると削除が確定する。
    static let undoDuration: TimeInterval = 5

    // MARK: スワイプ削除

    /// 行のスワイプを始めるまでに指が動く距離（pt）。長押しが不成立になる 10pt より大きくして、
    /// 長押しの途中でスワイプが始まらないようにする。
    static let swipeMinimumDistance: CGFloat = 20
    /// 行幅に対してこれより多く左に引いたら、指を離した時点で削除する。
    static let swipeDeleteRatio: CGFloat = 0.5

    // MARK: 触覚

    /// 触覚フィードバックの ON/OFF を保存する `UserDefaults` のキー。未設定なら ON。
    static let hapticsEnabledKey = "hapticsEnabled"

    /// スピン開始の手応え。
    static let hapticSpinStartWeight: SensoryFeedback.Weight = .medium

    /// 長押しで指定が切り替わった瞬間の、本人の指にだけ伝わる軽い手応え。
    static let hapticMarkToggleWeight: SensoryFeedback.Weight = .light

    /// 盤面を指で動かしている間に境目を越えた手応え。スピン中の刻み（`.selection`）より強くする。
    static let hapticDragBoundaryWeight: SensoryFeedback.Weight = .medium

    /// スピン中に境目を越える触覚を鳴らす最短間隔。序盤は境目を越える間隔がこれより短いので間引く。
    static let hapticMinInterval: TimeInterval = 0.06

    // MARK: 停止の強調

    /// 止まったスライスの光彩の色（`GlowStyle.rawValue`）を保存する `UserDefaults` のキー。未設定なら `GlowStyle.default`。
    static let glowStyleKey = "glowStyle"

    // MARK: スピンの演出

    /// スピンに付ける演出（`SpinEffectStyle.rawValue`）を保存する `UserDefaults` のキー。未設定なら `SpinEffectStyle.default`（なし）。
    static let spinEffectStyleKey = "spinEffectStyle"

    // MARK: 3D 表示

    /// 盤面を 3D で描くかを保存する `UserDefaults` のキー。未設定なら OFF（今の 2D の盤面）。
    static let wheel3DEnabledKey = "wheel3DEnabled"

    /// 3D の盤を傾ける基準（`TiltReference.rawValue`）を保存する `UserDefaults` のキー。未設定なら `TiltReference.default`。
    static let tiltReferenceKey = "tiltReference"

    /// 3D の盤が目標の傾きへ戻るばねの周期（秒）。短いほど素早く追従する。
    static let wheelSwayResponse: TimeInterval = 0.6

    /// 3D の盤のばねの減衰比。1 で揺り返さずに止まり、小さいほど長く揺れる。
    static let wheelSwayDampingRatio: Double = 0.3

    /// 端末を動かした勢い（`userAcceleration`、g）を盤の揺れの角速度（度/秒）に写す係数。
    static let wheelSwayKickGain: Double = 240

    /// 1 回の更新で盤の揺れに足す角速度の上限（度/秒）。強く振っても盤が回り込まないようにする。
    static let wheelSwayMaxKick: Double = 120

    /// これより小さい勢い（g）は手の震えとみなして揺れに足さない。
    static let wheelSwayKickThreshold: Double = 0.03

    // MARK: 効果音

    /// 効果音の ON/OFF を保存する `UserDefaults` のキー。未設定なら ON。
    static let soundEnabledKey = "soundEnabled"

    /// スピン中にクリック音を鳴らす最短間隔。序盤は境目を越える間隔がこれより短いので間引く。
    static let clickMinInterval: TimeInterval = 0.032

    /// クリック音の音量。密に重なっても耳に刺さらないところまで下げてある。
    static let clickGain: Float = 0.7

    /// 停止時の決まり音（`StopChime`）の音量。音源は最大振幅 0.8 で書き出してあり、伸びる音なのでクリックより下げて
    /// 結果の読み上げや周りの会話の邪魔にならないところに置く。クリックの最後の音と重なっても割れない。
    static let chimeGain: Float = 0.5

    /// スピン中のうなり（`SpinHum`）の音量。回転音（`clickGain`）より小さくして、カチカチの粒立ちを埋めない。
    /// 音源は最大振幅 0.8 で書き出してあり、速いときは打ちが重なるので、さらに下げておく。
    static let humGain: Float = 0.35

    /// うなりを打つ最小の演出の強さ（`SpinEffectIntensity`）。これ以下（既定では 36°/秒以下）では打たない。
    /// 止まり際と焦らしの区間はこれを下回るので、うなりは止まる前に消える。
    static let humMinIntensity = 0.05

    /// うなりを打つ間隔（秒）。強さ 1 で `humFastInterval`（1 秒に約 18 打ちのロール）、強さ 0 に近づくほど `humSlowInterval` に広げる。
    static let humFastInterval: TimeInterval = 0.055
    static let humSlowInterval: TimeInterval = 0.16

    /// うなりの 1 打ちの再生の速さ（ピッチ）。強さ 0 で `humMinRate`、強さ 1 で `humMaxRate`。速いほど高く、遅くなるにつれて低く沈む。
    static let humMinRate = 0.85
    static let humMaxRate = 1.15

    /// ドラムロールの左右の手の強弱。1 打ちおきにこの割合で弱める。
    static let humAccent = 0.8

    // MARK: 3D の盤の傾き

    /// 3D の盤を端末の姿勢に合わせて倒す最大角（度）。これより大きく傾けても盤はここで止める。
    static let wheelMaxTilt: Double = 25

    /// 3D の盤を傾けるために端末の姿勢を読む間隔（秒）。
    static let motionUpdateInterval: TimeInterval = 1.0 / 60
}
