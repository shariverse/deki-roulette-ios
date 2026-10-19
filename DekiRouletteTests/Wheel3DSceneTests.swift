import Metal
import SceneKit
import SwiftUI
import Testing
@testable import DekiRoulette

/// 3D の盤面を画面外で描き、スライスの並び・回る向き・塗りの色を画素で確かめる。
@MainActor
struct Wheel3DSceneTests {
    /// 盤面の直径。直径 480 の確かめでは、値を変えた写しで同じ手順を描く。
    private var size: CGFloat = 320
    /// 描く範囲（盤面の枠より `overscan` だけ広い）。
    private var canvas: CGFloat { size * (1 + 2 * Theme.Wheel3D.overscan) }

    /// 場面を描いた画素（RGBA8、sRGB）。
    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        func color(at point: CGPoint) -> SIMD3<Double> {
            let x = min(max(Int(point.x), 0), width - 1)
            let y = min(max(Int(point.y), 0), height - 1)
            let offset = (y * width + x) * 4
            return SIMD3(Double(bytes[offset]), Double(bytes[offset + 1]), Double(bytes[offset + 2])) / 255
        }
    }

    /// 場面を描く。`time` は描く時刻（システムの時計の秒）。0 では、`SCNTransaction` で動かし始めた値は動きの始まり（変える前の値）で描かれる。
    /// 動きが終わったあとを描くときは `CACurrentMediaTime()` より先の時刻を渡す。
    private func render(_ scene: Wheel3DScene, atTime time: TimeInterval = 0) throws -> Pixels {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene.scene
        renderer.pointOfView = scene.cameraNode
        let image = renderer.snapshot(atTime: time, with: CGSize(width: canvas, height: canvas), antialiasingMode: .none)
        let cgImage = try #require(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        #expect(drawn)
        return Pixels(width: width, height: height, bytes: bytes)
    }

    /// 盤面の角度 `angle`（12 時が 0 度、時計回り）・半径の割合 `fraction` の画素の位置（画像は y が下向き）。
    private func location(angle: Double, fraction: Double, pixels: Pixels) -> CGPoint {
        let radius = (Double(size) / 2 - 16 * Double(size) / WheelLabel.referenceDiameter) * fraction
        let point = WheelGeometry.point(angle: angle, radius: radius)
        return location(x: point.x, y: point.y, pixels: pixels)
    }

    /// 盤の平面の座標（中心が原点、y が上）の画素の位置。
    private func location(x: Double, y: Double, pixels: Pixels) -> CGPoint {
        let scale = Double(pixels.width) / Double(canvas)
        return CGPoint(x: (Double(canvas) / 2 + x) * scale, y: (Double(canvas) / 2 - y) * scale)
    }

    private func srgb(_ color: Color) -> SIMD3<Double> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD3(Double(r), Double(g), Double(b))
    }

    private func isClose(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Bool {
        let d = a - b
        return max(abs(d.x), abs(d.y), abs(d.z)) < 0.04
    }

    private func makeScene(count: Int, rotation: Double) -> Wheel3DScene {
        makeScene(labels: Array(repeating: "", count: count), rotation: rotation)
    }

    private func makeScene(labels: [String], rotation: Double) -> Wheel3DScene {
        let scene = Wheel3DScene()
        scene.update(labels: labels, diameter: size)
        scene.spin(to: rotation)
        return scene
    }

    /// `center` のまわり（一辺 `box` px）で、ラベルの文字色（`onSlice`）に近い画素の数。
    private func inkCount(around center: CGPoint, box: Int = 10, pixels: Pixels) -> Int {
        let ink = srgb(Theme.onSlice)
        var count = 0
        for dx in -box / 2..<box / 2 {
            for dy in -box / 2..<box / 2 {
                let color = pixels.color(at: CGPoint(x: center.x + CGFloat(dx), y: center.y + CGFloat(dy)))
                if isClose(color, ink) { count += 1 }
            }
        }
        return count
    }

    @Test func スライスは12時から時計回りに並び塗りの色のまま出る() throws {
        let pixels = try render(makeScene(count: 4, rotation: 0))
        for index in 0..<4 {
            let color = pixels.color(at: location(angle: 45 + 90 * Double(index), fraction: 0.6, pixels: pixels))
            #expect(isClose(color, srgb(Theme.sliceColor(at: index, count: 4))), "slice \(index): \(color)")
        }
    }

    /// 回転角だけ時計回りに回る（2D の `rotationEffect` と同じ向き）。
    @Test func 時計回りに回る() throws {
        let pixels = try render(makeScene(count: 4, rotation: 90))
        let color = pixels.color(at: location(angle: 135, fraction: 0.6, pixels: pixels))
        #expect(isClose(color, srgb(Theme.sliceColor(at: 0, count: 4))), "\(color)")
    }

    @Test func 項目1件は円1枚() throws {
        let pixels = try render(makeScene(count: 1, rotation: 0))
        for angle in [30.0, 200, 300] {
            let color = pixels.color(at: location(angle: angle, fraction: 0.6, pixels: pixels))
            #expect(isClose(color, srgb(Theme.sliceColor(at: 0, count: 1))), "\(angle): \(color)")
        }
    }

    @Test func 件数が変わると組み直す() throws {
        let scene = makeScene(count: 4, rotation: 0)
        scene.update(labels: ["", "", ""], diameter: size)
        let pixels = try render(scene)
        let color = pixels.color(at: location(angle: 180, fraction: 0.6, pixels: pixels))
        #expect(isClose(color, srgb(Theme.sliceColor(at: 1, count: 3))), "\(color)")
    }

    /// ラベルは自分のスライスの上に出る（上下・左右に反転しない）。
    @Test func ラベルは自分のスライスに出る() throws {
        let pixels = try render(makeScene(labels: ["", "■■■", "", ""], rotation: 0))
        let own = location(angle: 135, fraction: WheelLabel.radiusFraction, pixels: pixels)
        #expect(inkCount(around: own, pixels: pixels) > 30)
        for angle in [45.0, 225, 315] {
            let other = location(angle: angle, fraction: WheelLabel.radiusFraction, pixels: pixels)
            #expect(inkCount(around: other, pixels: pixels) == 0, "\(angle)")
        }
    }

    /// 文字は半径方向に左から右へ並び、右半分では中心側から、左半分では外周側から読み始める（2D と同じ向き）。
    /// 先頭にだけ印のあるラベルで、印が出る側を確かめる（左右に反転すると逆の側に出る）。
    @Test func ラベルの文字は2Dと同じ向きに並ぶ() throws {
        let label = "■\u{3000}\u{3000}\u{3000}"
        let pixels = try render(makeScene(labels: ["", label, "", label], rotation: 0))
        let inner = WheelLabel.radiusFraction - 0.13
        let outer = WheelLabel.radiusFraction + 0.13
        // 右半分（135 度）は中心側が先頭
        #expect(inkCount(around: location(angle: 135, fraction: inner, pixels: pixels), pixels: pixels) > 30)
        #expect(inkCount(around: location(angle: 135, fraction: outer, pixels: pixels), pixels: pixels) == 0)
        // 左半分（315 度）は逆さまにしないよう返すので、外周側が先頭
        #expect(inkCount(around: location(angle: 315, fraction: outer, pixels: pixels), pixels: pixels) > 30)
        #expect(inkCount(around: location(angle: 315, fraction: inner, pixels: pixels), pixels: pixels) == 0)
    }

    @Test func ラベルは盤と一緒に回る() throws {
        let pixels = try render(makeScene(labels: ["", "■■■", "", ""], rotation: 180))
        let moved = location(angle: 315, fraction: WheelLabel.radiusFraction, pixels: pixels)
        #expect(inkCount(around: moved, pixels: pixels) > 30)
        let original = location(angle: 135, fraction: WheelLabel.radiusFraction, pixels: pixels)
        #expect(inkCount(around: original, pixels: pixels) == 0)
    }

    @Test func ラベルが変わると組み直す() throws {
        let scene = makeScene(labels: ["", "■■■", "", ""], rotation: 0)
        scene.update(labels: ["", "", "", ""], diameter: size)
        let pixels = try render(scene)
        let own = location(angle: 135, fraction: WheelLabel.radiusFraction, pixels: pixels)
        #expect(inkCount(around: own, pixels: pixels) == 0)
    }

    // MARK: 停止の強調

    private func makeStoppedScene(index: Int, glowStyle: GlowStyle = .white, items: [Item]? = nil) -> Wheel3DScene {
        let scene = makeScene(count: 4, rotation: 0)
        if let items { scene.update(items: items, diameter: size) }
        scene.highlight(Wheel3DHighlight(index: index, glowStyle: glowStyle), reduceMotion: true)
        return scene
    }

    private func distance(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let d = a - b
        return max(abs(d.x), abs(d.y), abs(d.z))
    }

    @Test func 止まっていないスライスは沈み止まったスライスは塗りの色のまま() throws {
        let pixels = try render(makeStoppedScene(index: 2))
        let stopped = pixels.color(at: location(angle: 225, fraction: 0.6, pixels: pixels))
        #expect(isClose(stopped, srgb(Theme.sliceColor(at: 2, count: 4))), "\(stopped)")
        let ink = srgb(Theme.onSlice)
        for index in [0, 1, 3] {
            let original = srgb(Theme.sliceColor(at: index, count: 4))
            let color = pixels.color(at: location(angle: 45 + 90 * Double(index), fraction: 0.6, pixels: pixels))
            #expect(!isClose(color, original), "slice \(index): \(color)")
            // `onSlice` を重ねた分だけ近づく
            #expect(distance(color, ink) < distance(original, ink), "slice \(index): \(color)")
        }
    }

    @Test func 止まったスライスに縁取りが付く() throws {
        let pixels = try render(makeStoppedScene(index: 2))
        // 止まったスライスの始まりの境目（180 度）の上
        let color = pixels.color(at: location(angle: 180, fraction: 0.6, pixels: pixels))
        #expect(isClose(color, srgb(Theme.stopOutline)), "\(color)")
    }

    @Test func 止まったスライスの外側に光彩が出る() throws {
        let pixels = try render(makeStoppedScene(index: 2))
        // 境目から隣のスライスへ 5pt 入った位置は、沈めた隣の色より明るい（白系の光彩）
        let radius = (Double(size) / 2 - 16 * Double(size) / WheelLabel.referenceDiameter) * 0.6
        let near = pixels.color(at: location(angle: 180 - 5 / radius * 180 / .pi, fraction: 0.6, pixels: pixels))
        let plain = pixels.color(at: location(angle: 135, fraction: 0.6, pixels: pixels))
        #expect(near.x + near.y + near.z > plain.x + plain.y + plain.z + 0.1, "near: \(near) plain: \(plain)")
    }

    /// `afterglow` が true（停止の演出が ON）のときは、止まったスライスを光彩ごと焼いた板と光彩の無い板の 2 枚にするが、見た目は同じ。
    @Test(arguments: [false, true])
    func 押し出しが終わったあとも止まったスライスは前に出した大きさで残る(afterglow: Bool) throws {
        let scene = makeScene(count: 4, rotation: 0)
        scene.highlight(Wheel3DHighlight(index: 2, glowStyle: .white), reduceMotion: false, afterglow: afterglow)
        // 押し出し（0.14 秒 + ばね約 0.5 秒）と暗くする動き（0.25 秒）が終わったあとを描く
        let pixels = try render(scene, atTime: CACurrentMediaTime() + 2)
        let slice2 = srgb(Theme.sliceColor(at: 2, count: 4))
        // 止まったスライス（180〜270 度）は塗りの色、境目は縁取り、隣のスライス 1 は沈んだ色（止まったスライスの塗りが広がっていない）
        let inside = pixels.color(at: location(angle: 225, fraction: 0.6, pixels: pixels))
        #expect(isClose(inside, slice2), "\(inside)")
        let edge = pixels.color(at: location(angle: 180, fraction: 0.6, pixels: pixels))
        #expect(isClose(edge, srgb(Theme.stopOutline)), "\(edge)")
        let neighbor = pixels.color(at: location(angle: 135, fraction: 0.6, pixels: pixels))
        #expect(!isClose(neighbor, slice2), "\(neighbor)")
        #expect(distance(neighbor, srgb(Theme.onSlice)) < distance(srgb(Theme.sliceColor(at: 1, count: 4)), srgb(Theme.onSlice)), "\(neighbor)")
        // 1.07 倍に前に出したままなので、スライスの円の 4% 外（縁の上）にも止まったスライスの塗りが乗る
        // （元の大きさなら半径 144pt の外は縁。前に出した塗りは 144 × 1.07 ≈ 154pt まで、縁取りはその内側 1.6pt から。
        // 縁取りの光彩が少し混ざるので、縁の色ではなく塗りの色に寄っていることを見る）
        let beyond = pixels.color(at: location(angle: 225, fraction: 1.04, pixels: pixels))
        #expect(distance(beyond, slice2) < 0.1, "\(beyond)")
        #expect(distance(beyond, srgb(Theme.wheelRim)) > 0.5, "\(beyond)")
        // 針も跳ねたあと元の位置に戻っている（`針は12時に塗りの色のまま出る` と同じ、針の先より少し上の中央）
        let pointer = pixels.color(at: location(x: 0, y: Double(size) / 2 - 8, pixels: pixels))
        #expect(isClose(pointer, srgb(Theme.flare)), "\(pointer)")
    }

    @Test func 強調を解くと元の色に戻る() throws {
        let scene = makeStoppedScene(index: 2)
        scene.highlight(nil, reduceMotion: true)
        let pixels = try render(scene)
        for index in 0..<4 {
            let color = pixels.color(at: location(angle: 45 + 90 * Double(index), fraction: 0.6, pixels: pixels))
            #expect(isClose(color, srgb(Theme.sliceColor(at: index, count: 4))), "slice \(index): \(color)")
        }
        let edge = pixels.color(at: location(angle: 180, fraction: 0.6, pixels: pixels))
        #expect(!isClose(edge, srgb(Theme.stopOutline)), "\(edge)")
    }

    @Test func 盤を組み直しても強調を出し直す() throws {
        let scene = makeStoppedScene(index: 2)
        scene.update(labels: Array(repeating: "", count: 4), diameter: size + 1)
        scene.update(labels: Array(repeating: "", count: 4), diameter: size)
        scene.highlight(Wheel3DHighlight(index: 2, glowStyle: .white), reduceMotion: true)
        let pixels = try render(scene)
        let color = pixels.color(at: location(angle: 45, fraction: 0.6, pixels: pixels))
        #expect(!isClose(color, srgb(Theme.sliceColor(at: 0, count: 4))), "\(color)")
    }

    // MARK: 傾き

    @Test func 傾けると針も盤と一緒に動き正面に戻すと元に戻る() throws {
        let scene = makeScene(count: 4, rotation: 0)
        let pointer = { (pixels: Pixels) in pixels.color(at: self.location(x: 0, y: Double(self.size) / 2 - 8, pixels: pixels)) }
        scene.tilt(to: WheelTilt(pitch: 25, roll: 0))
        // 上端が奥へ倒れるので、針は画面上で下（中心寄り）に動いて元の位置から外れる
        #expect(!isClose(pointer(try render(scene)), srgb(Theme.flare)))
        scene.tilt(to: .zero)
        #expect(isClose(pointer(try render(scene)), srgb(Theme.flare)))
    }

    @Test func 上端が奥へ倒れると盤の上端は中心へ寄って見える() throws {
        let scene = makeScene(count: 4, rotation: 0)
        scene.tilt(to: WheelTilt(pitch: 25, roll: 0))
        let pixels = try render(scene)
        // 正面ではスライス 0 の外周寄りの位置が、倒すと盤より外になる
        let top = pixels.color(at: location(angle: 10, fraction: 0.95, pixels: pixels))
        #expect(!isClose(top, srgb(Theme.sliceColor(at: 0, count: 4))), "\(top)")
        // 下端は手前に起きるので、同じ位置にまだスライス 1 がある
        let bottom = pixels.color(at: location(angle: 170, fraction: 0.9, pixels: pixels))
        #expect(isClose(bottom, srgb(Theme.sliceColor(at: 1, count: 4))), "\(bottom)")
    }

    // MARK: 針と結果の帯

    @Test func 針は12時に塗りの色のまま出る() throws {
        let pixels = try render(makeScene(count: 4, rotation: 0))
        // 針の先（盤面の枠の上端から 20pt 下）より少し上の中央
        let color = pixels.color(at: location(x: 0, y: Double(size) / 2 - 8, pixels: pixels))
        #expect(isClose(color, srgb(Theme.flare)), "\(color)")
    }

    @Test func 針は盤と一緒に回らない() throws {
        let pixels = try render(makeScene(count: 4, rotation: 123))
        let color = pixels.color(at: location(x: 0, y: Double(size) / 2 - 8, pixels: pixels))
        #expect(isClose(color, srgb(Theme.flare)), "\(color)")
    }

    /// 帯の中央（盤面の中心より下）の位置。場面の y は上向き。
    private var bandCenterY: Double {
        -ResultBand.centerOffset(diameter: Double(size))
    }

    @Test func 結果の帯は盤面の中心より下に出る() throws {
        let scene = makeScene(count: 4, rotation: 0)
        scene.show(result: Wheel3DResult(id: "a1", label: "\u{3000}", accent: Theme.sliceColor(at: 2, count: 4)), reduceMotion: true)
        let pixels = try render(scene)
        let color = pixels.color(at: location(x: 0, y: bandCenterY, pixels: pixels))
        #expect(isClose(color, srgb(Theme.resultBandFill)), "\(color)")
    }

    @Test func 結果の帯は針の下の上半分には出ない() throws {
        let scene = makeScene(count: 4, rotation: 0)
        scene.show(result: Wheel3DResult(id: "a1", label: "\u{3000}", accent: Theme.sliceColor(at: 2, count: 4)), reduceMotion: true)
        let pixels = try render(scene)
        // 針の先のすぐ下（以前の帯の位置）と、中心をはさんで帯と反対側
        for y in [Double(size) / 2 * 0.65, -bandCenterY] {
            let color = pixels.color(at: location(x: 0, y: y, pixels: pixels))
            #expect(!isClose(color, srgb(Theme.resultBandFill)), "\(y): \(color)")
        }
    }

    @Test func 結果が消えると帯も消える() throws {
        let scene = makeScene(count: 4, rotation: 0)
        scene.show(result: Wheel3DResult(id: "a1", label: "\u{3000}", accent: Theme.sliceColor(at: 2, count: 4)), reduceMotion: true)
        scene.show(result: nil, reduceMotion: true)
        let pixels = try render(scene)
        let color = pixels.color(at: location(x: 0, y: bandCenterY, pixels: pixels))
        #expect(!isClose(color, srgb(Theme.resultBandFill)), "\(color)")
    }

    // MARK: 項目の見た目

    private let purple = Theme.sliceColors[SliceColor.purple.paletteIndex]

    /// 添字 1 だけ紫を選んだ 4 件。他は自動。
    private var styledItems: [Item] {
        [Item(label: ""), Item(label: "", appearance: .color(.purple)), Item(label: ""), Item(label: "")]
    }

    @Test func 色の項目は選んだ色で塗り他は今の規則() throws {
        let scene = Wheel3DScene()
        scene.update(items: styledItems, diameter: size)
        let pixels = try render(scene)
        for index in 0..<4 {
            let expected = index == 1 ? purple : Theme.sliceColor(at: index, count: 4)
            let color = pixels.color(at: location(angle: 45 + 90 * Double(index), fraction: 0.6, pixels: pixels))
            #expect(isClose(color, srgb(expected)), "slice \(index): \(color)")
        }
    }

    @Test func 見た目が変わると組み直す() throws {
        let scene = makeScene(count: 4, rotation: 0)
        scene.update(items: styledItems, diameter: size)
        let pixels = try render(scene)
        let color = pixels.color(at: location(angle: 135, fraction: 0.6, pixels: pixels))
        #expect(isClose(color, srgb(purple)), "\(color)")
    }

    @Test func 止まった色の項目は選んだ色のまま前に出る() throws {
        let pixels = try render(makeStoppedScene(index: 1, items: styledItems))
        let stopped = pixels.color(at: location(angle: 135, fraction: 0.6, pixels: pixels))
        #expect(isClose(stopped, srgb(purple)), "\(stopped)")
    }

    @Test func 光彩を止まったスライスの色にすると色の項目は選んだ色で光る() throws {
        // 止まった添字 1（90〜180 度）の境目から隣（添字 0）へ 5pt 入った位置の青みを、自動の色（添字 1）のときと比べる
        let radius = (Double(size) / 2 - 16 * Double(size) / WheelLabel.referenceDiameter) * 0.6
        let angle = 90 - 5 / radius * 180 / .pi
        let styled = try render(makeStoppedScene(index: 1, glowStyle: .slice, items: styledItems))
        let plain = try render(makeStoppedScene(index: 1, glowStyle: .slice))
        let near = styled.color(at: location(angle: angle, fraction: 0.6, pixels: styled))
        let nearPlain = plain.color(at: location(angle: angle, fraction: 0.6, pixels: plain))
        // 紫（#CE8CEE）は自動の添字 1（#FFA366）より青みが強い
        #expect(near.z > nearPlain.z + 0.05, "styled: \(near) plain: \(nearPlain)")
    }

    @Test func 絵文字の項目はラベルの前に絵文字が描かれる() throws {
        // ラベルは空にして、ラベルの位置が青い四角の絵文字だけになるようにする
        let scene = Wheel3DScene()
        scene.update(
            items: [Item(label: ""), Item(label: "", appearance: .emoji("🟦")), Item(label: ""), Item(label: "")],
            diameter: size
        )
        let pixels = try render(scene)
        let label = pixels.color(at: location(angle: 135, fraction: WheelLabel.radiusFraction, pixels: pixels))
        // 絵文字の項目のスライスは自動の色（添字 1 は橙）。そこに青い絵文字が乗る
        #expect(label.z > label.x + 0.2, "\(label)")
    }

    @Test func 結果を出したまま見た目が変わると帯を動かさずに焼き直す() throws {
        // アプリと同じ順（盤の更新 → 強調 → 帯）で、結果を出したあとに止まった項目の見た目を変える
        let scene = makeScene(count: 4, rotation: 0)
        let highlight = Wheel3DHighlight(index: 1, glowStyle: .white)
        scene.highlight(highlight, reduceMotion: false)
        scene.show(result: Wheel3DResult(id: "a1", label: "\u{3000}", accent: Theme.sliceColor(at: 1, count: 4)), reduceMotion: false)
        #expect(scene.bandRevealCount == 1)

        scene.update(items: [Item(label: ""), Item(label: "", appearance: .emoji("🟦")), Item(label: ""), Item(label: "")], diameter: size)
        scene.highlight(highlight, reduceMotion: false)
        scene.show(result: Wheel3DResult(id: "a1", label: "🟦", accent: Theme.sliceColor(at: 1, count: 4)), reduceMotion: false)
        #expect(scene.bandRevealCount == 1)
        let pixels = try render(scene)
        let color = pixels.color(at: location(x: 0, y: bandCenterY, pixels: pixels))
        #expect(color.z > color.x + 0.2, "\(color)")
    }

    @Test func 結果を出したまま他の項目の見た目が変わっても帯の動きは繰り返さない() throws {
        let scene = makeScene(count: 4, rotation: 0)
        let result = Wheel3DResult(id: "a1", label: "\u{3000}", accent: Theme.sliceColor(at: 1, count: 4))
        scene.show(result: result, reduceMotion: false)
        scene.update(items: styledItems, diameter: size)
        scene.show(result: result, reduceMotion: false)
        #expect(scene.bandRevealCount == 1)
        let pixels = try render(scene)
        #expect(isClose(pixels.color(at: location(x: 0, y: bandCenterY, pixels: pixels)), srgb(Theme.resultBandFill)))
    }

    @Test func 新しい結果では帯の登場の動きを流す() {
        let scene = makeScene(count: 4, rotation: 0)
        scene.show(result: Wheel3DResult(id: "a1", label: "\u{3000}", accent: Theme.sliceColor(at: 1, count: 4)), reduceMotion: false)
        scene.show(result: nil, reduceMotion: false)
        scene.show(result: Wheel3DResult(id: "a2", label: "\u{3000}", accent: Theme.sliceColor(at: 1, count: 4)), reduceMotion: false)
        #expect(scene.bandRevealCount == 2)
    }

    // MARK: 電飾

    /// 電球 `index` の中心の画素の位置。電球は縁の上面から浮かせてあるので、カメラに近い分だけ外へ広がって見える。
    private func lightLocation(index: Int, along offset: Double = 0, pixels: Pixels) -> CGPoint {
        let ring = Double(Theme.LightRing.ringRadius(diameter: size))
        let z = Double(Theme.Wheel3D.rimLift) * Double(size) / WheelLabel.referenceDiameter + Double(Theme.Wheel3D.lightLift)
        let distance = WheelGeometry.cameraDistance(diameter: Double(canvas), fieldOfView: Theme.Wheel3D.fieldOfView)
        let projection = distance / (distance - z)
        // `offset` は環に沿って時計回りに進めた距離（pt）
        let angle = WheelLights.angle(index: index) + offset / ring * 180 / .pi
        let point = WheelGeometry.point(angle: angle, radius: ring * projection)
        return location(x: point.x, y: point.y, pixels: pixels)
    }

    /// 2D の電球の色（縁の `wheelRim` に `wheelLight` を明るさの不透明度で重ねた色）。
    private func bulbColor(_ brightness: Double) -> SIMD3<Double> {
        let rim = srgb(Theme.wheelRim), light = srgb(Theme.wheelLight)
        return rim + (light - rim) * brightness
    }

    @Test func 電飾を出さないときは縁のまま() throws {
        let plain = try render(makeScene(count: 4, rotation: 0))
        let scene = makeScene(count: 4, rotation: 0)
        scene.light(.still)
        scene.light(nil)
        let cleared = try render(scene)
        for index in [3, 6, 15] {
            let before = plain.color(at: lightLocation(index: index, pixels: plain))
            let after = cleared.color(at: lightLocation(index: index, pixels: cleared))
            #expect(distance(before, after) < 0.01, "\(index): \(before) \(after)")
            // 縁の色で、電球の色ではない
            #expect(!isClose(before, bulbColor(WheelLights.stillLevel)), "\(index): \(before)")
        }
    }

    @Test func 電球は縁の上に2Dと同じ明るさで点く() throws {
        let cases: [(WheelLights.Scene, Int)] = [
            (.still, 6),
            // 止まっているとき、並び（3 個おき）は 0.6、間は 0.3
            (.running(angle: 0, intensity: 0), 6),
            (.running(angle: 0, intensity: 0), 7),
            // 点滅の終わり（暗いところ）
            (.stopped(elapsed: WheelLights.blinkDuration), 9),
        ]
        for (lights, index) in cases {
            let scene = makeScene(count: 4, rotation: 0)
            scene.light(lights)
            let pixels = try render(scene)
            let expected = bulbColor(WheelLights.bulb(index: index, scene: lights).brightness)
            let color = pixels.color(at: lightLocation(index: index, pixels: pixels))
            #expect(isClose(color, expected), "\(lights) \(index): \(color) expected \(expected)")
        }
    }

    @Test func 電球は盤と一緒に回らない() throws {
        let scene = makeScene(count: 4, rotation: 123)
        scene.light(.still)
        let pixels = try render(scene)
        for index in [3, 6, 18] {
            let color = pixels.color(at: lightLocation(index: index, pixels: pixels))
            #expect(isClose(color, bulbColor(WheelLights.stillLevel)), "\(index): \(color)")
        }
    }

    @Test func 強さに応じて電球のまわりににじむ() throws {
        let weak = makeScene(count: 4, rotation: 0)
        weak.light(.running(angle: 0, intensity: 0))
        let strong = makeScene(count: 4, rotation: 0)
        strong.light(.running(angle: 0, intensity: 1))
        let weakPixels = try render(weak), strongPixels = try render(strong)
        // 電球 6（並びの上）の縁に沿って 4pt 離れた位置（電球の外、にじみの中）
        let near = strongPixels.color(at: lightLocation(index: 6, along: 4, pixels: strongPixels))
        let plain = weakPixels.color(at: lightLocation(index: 6, along: 4, pixels: weakPixels))
        #expect(near.x + near.y + near.z > plain.x + plain.y + plain.z + 0.1, "near: \(near) plain: \(plain)")
        // 強さ 1 では並びの電球は最も明るい
        let bulb = strongPixels.color(at: lightLocation(index: 6, pixels: strongPixels))
        #expect(isClose(bulb, bulbColor(WheelLights.litPeakLevel)), "\(bulb)")
    }

    @Test func 盤を組み直しても電飾を出し直す() throws {
        let scene = makeScene(count: 4, rotation: 0)
        scene.light(.still)
        scene.update(labels: Array(repeating: "", count: 5), diameter: size)
        let pixels = try render(scene)
        let color = pixels.color(at: lightLocation(index: 6, pixels: pixels))
        #expect(isClose(color, bulbColor(WheelLights.stillLevel)), "\(color)")
    }

    @Test func 電球は持ち上げた止まったスライスの光彩に隠れない() throws {
        let scene = makeScene(count: 4, rotation: 0)
        scene.highlight(Wheel3DHighlight(index: 0, glowStyle: .white), reduceMotion: false)
        scene.light(.stopped(elapsed: WheelLights.blinkDuration))
        let pixels = try render(scene)
        // 止まったスライス（0〜90 度）の外周の上の電球
        let color = pixels.color(at: lightLocation(index: 3, pixels: pixels))
        #expect(isClose(color, bulbColor(WheelLights.blinkLowLevel)), "\(color)")

        // 浮かせなければ、前に出した止まったスライス（縁の上面 + 0.5pt）に隠れる（上の確かめが浮かせた高さで決まっていること）
        let flat = makeScene(count: 4, rotation: 0)
        flat.lightLift = 0
        flat.highlight(Wheel3DHighlight(index: 0, glowStyle: .white), reduceMotion: false)
        flat.light(.stopped(elapsed: WheelLights.blinkDuration))
        let hidden = try render(flat)
        let covered = hidden.color(at: lightLocation(index: 3, pixels: hidden))
        #expect(!isClose(covered, bulbColor(WheelLights.blinkLowLevel)), "\(covered)")
        #expect(distance(covered, color) > 0.04, "\(covered) \(color)")
    }

    @Test func 電飾を出さない間は電球を作らない() {
        let scene = makeScene(count: 4, rotation: 0)
        scene.light(nil)
        #expect(scene.bulbCount == 0)
        // 組み直しても作らない
        scene.update(labels: Array(repeating: "", count: 5), diameter: size)
        #expect(scene.bulbCount == 0)
        scene.light(.still)
        #expect(scene.bulbCount == Config.wheelLightCount)
    }

    @Test func 明るさの変わらない電球は塗り直さない() {
        let scene = makeScene(count: 4, rotation: 0)
        scene.light(.still)
        #expect(scene.bulbColorWriteCount == Config.wheelLightCount)
        // 止まっている並び（3 個おき）は `still` と同じ 0.6 なので、間の電球だけ塗り直す
        scene.light(.running(angle: 0, intensity: 0))
        let lit = (0..<Config.wheelLightCount).filter {
            WheelLights.bulb(index: $0, scene: .running(angle: 0, intensity: 0)).brightness == WheelLights.stillLevel
        }.count
        #expect(lit == Config.wheelLightCount / WheelLights.litStride)
        #expect(scene.bulbColorWriteCount == Config.wheelLightCount * 2 - lit)
        // 消して同じ場面に戻しても、明るさが同じなら塗り直さない
        scene.light(nil)
        scene.light(.running(angle: 0, intensity: 0))
        #expect(scene.bulbColorWriteCount == Config.wheelLightCount * 2 - lit)
    }

    @Test func 電球は針の後ろ() throws {
        let scene = makeScene(count: 4, rotation: 0)
        scene.light(.running(angle: 0, intensity: 1))
        let pixels = try render(scene)
        // 12 時の電球（添字 0）は針に隠れる
        let color = pixels.color(at: lightLocation(index: 0, pixels: pixels))
        #expect(isClose(color, srgb(Theme.flare)), "\(color)")
    }

    // MARK: 光の尾・残像

    /// 光の尾の環の上で角度 `angle`（12 時が 0 度、時計回り）の画素の位置。光の尾は `Theme.Wheel3D.trailPieceAngle`（2.5 度）の切れ端を
    /// 並べて描くので、テストは切れ端の境目（2.5 度の倍数）を避けて切れ端の中央（x.25・x.75 度）で読む。光の尾は縁の上面から浮かせてあるので、カメラに近い分だけ外へ広がって見える。
    private func trailLocation(angle: Double, pixels: Pixels) -> CGPoint {
        let ring = Double(Theme.TrailRing.ringRadius(diameter: size))
        let z = Double(Theme.Wheel3D.rimLift) * Double(size) / WheelLabel.referenceDiameter + Double(Theme.Wheel3D.trailLift)
        let distance = WheelGeometry.cameraDistance(diameter: Double(canvas), fieldOfView: Theme.Wheel3D.fieldOfView)
        let point = WheelGeometry.point(angle: angle, radius: ring * distance / (distance - z))
        return location(x: point.x, y: point.y, pixels: pixels)
    }

    private func brightness(_ color: SIMD3<Double>) -> Double {
        color.x + color.y + color.z
    }

    private func trailFrame(
        length: Double = Config.wheelTrailMaxLength, opacity: Double = WheelTrails.trailPeakOpacity,
        direction: SpinDirection = .clockwise, ghosts: [WheelTrails.Ghost] = []
    ) -> WheelTrails.Frame {
        WheelTrails.Frame(ghosts: ghosts, trail: WheelTrails.Trail(length: length, opacity: opacity, direction: direction))
    }

    @Test func 光の尾は縁の上を針の下から回転と逆へ伸びる() throws {
        let plain = try render(makeScene(count: 4, rotation: 0))
        let scene = makeScene(count: 4, rotation: 0)
        scene.trail(trailFrame())
        let pixels = try render(scene)
        // 時計回りなら 12 時から反時計回りの側（負の角度）に伸びる
        for angle in [-11.25, -41.25, -81.25] {
            let color = pixels.color(at: trailLocation(angle: angle, pixels: pixels))
            let before = plain.color(at: trailLocation(angle: angle, pixels: plain))
            #expect(brightness(color) > brightness(before) + 0.2, "\(angle): \(color) \(before)")
            // 冷たい白系（青みが強い）
            #expect(color.z > before.z + 0.1, "\(angle): \(color)")
        }
        // 回転の向きの側と、尾の長さより先は縁のまま
        for angle in [21.25, 61.25, -131.25, -201.25] {
            let color = pixels.color(at: trailLocation(angle: angle, pixels: pixels))
            let before = plain.color(at: trailLocation(angle: angle, pixels: plain))
            #expect(distance(color, before) < 0.01, "\(angle): \(color) \(before)")
        }
    }

    @Test func 反時計回りでは光の尾は逆の側に伸びる() throws {
        let plain = try render(makeScene(count: 4, rotation: 0))
        let scene = makeScene(count: 4, rotation: 0)
        scene.trail(trailFrame(direction: .counterclockwise))
        let pixels = try render(scene)
        let tail = pixels.color(at: trailLocation(angle: 41.25, pixels: pixels))
        #expect(brightness(tail) > brightness(plain.color(at: trailLocation(angle: 41.25, pixels: plain))) + 0.2)
        let ahead = pixels.color(at: trailLocation(angle: -41.25, pixels: pixels))
        #expect(distance(ahead, plain.color(at: trailLocation(angle: -41.25, pixels: plain))) < 0.01)
    }

    @Test func 光の尾は頭ほど濃く短いときは短く描く() throws {
        let scene = makeScene(count: 4, rotation: 0)
        scene.trail(trailFrame())
        let pixels = try render(scene)
        let head = pixels.color(at: trailLocation(angle: -16.25, pixels: pixels))
        let tip = pixels.color(at: trailLocation(angle: -101.25, pixels: pixels))
        #expect(brightness(head) > brightness(tip) + 0.2, "head: \(head) tip: \(tip)")

        // 長さ 40 度なら 61.25 度の位置には無い
        let plain = try render(makeScene(count: 4, rotation: 0))
        scene.trail(trailFrame(length: 40))
        let short = try render(scene)
        #expect(distance(short.color(at: trailLocation(angle: -61.25, pixels: short)),
                         plain.color(at: trailLocation(angle: -61.25, pixels: plain))) < 0.01)
        #expect(brightness(short.color(at: trailLocation(angle: -11.25, pixels: short)))
            > brightness(plain.color(at: trailLocation(angle: -11.25, pixels: plain))) + 0.2)
    }

    @Test func 光の尾は針の下と電球の奥() throws {
        let scene = makeScene(count: 4, rotation: 0)
        scene.light(.still)
        scene.trail(trailFrame())
        let pixels = try render(scene)
        // 針は光の尾に隠れない
        let pointer = pixels.color(at: location(x: 0, y: Double(size) / 2 - 8, pixels: pixels))
        #expect(isClose(pointer, srgb(Theme.flare)), "\(pointer)")
        // 尾の上の電球（添字 23 = 345 度、22 = 330 度）は電球の色のまま
        for index in [22, 23] {
            let color = pixels.color(at: lightLocation(index: index, pixels: pixels))
            #expect(isClose(color, bulbColor(WheelLights.stillLevel)), "\(index): \(color)")
        }
    }

    @Test func 光の尾と残像は盤と一緒に回らない() throws {
        let plain = try render(makeScene(count: 4, rotation: 123))
        let scene = makeScene(count: 4, rotation: 123)
        scene.trail(trailFrame())
        let pixels = try render(scene)
        let tail = pixels.color(at: trailLocation(angle: -21.25, pixels: pixels))
        #expect(brightness(tail) > brightness(plain.color(at: trailLocation(angle: -21.25, pixels: plain))) + 0.2)
        let ahead = pixels.color(at: trailLocation(angle: 21.25, pixels: pixels))
        #expect(distance(ahead, plain.color(at: trailLocation(angle: 21.25, pixels: plain))) < 0.01)
    }

    @Test func 残像は遅れた角度のスライスの塗りを重ねる() throws {
        let plain = try render(makeScene(count: 4, rotation: 0))
        let scene = makeScene(count: 4, rotation: 0)
        // 120 度遅れた角度の残像。80 度の位置は今はスライス 0、残像ではスライス 2（60〜150 度）
        scene.trail(trailFrame(ghosts: [WheelTrails.Ghost(angle: -120, opacity: 0.3)]))
        let pixels = try render(scene)
        let slice2 = srgb(Theme.sliceColor(at: 2, count: 4))
        let shifted = pixels.color(at: location(angle: 80, fraction: 0.6, pixels: pixels))
        let before = plain.color(at: location(angle: 80, fraction: 0.6, pixels: plain))
        #expect(distance(shifted, slice2) < distance(before, slice2) - 0.03, "\(shifted) \(before)")
        // ハブには重ねない
        let hub = pixels.color(at: location(x: 3, y: 3, pixels: pixels))
        #expect(distance(hub, plain.color(at: location(x: 3, y: 3, pixels: plain))) < 0.01, "\(hub)")
    }

    @Test func 残像は盤の回転に足さず描いた角度に置く() throws {
        let scene = makeScene(count: 4, rotation: 90)
        // 盤は 90 度（スライス 0 は 90〜180 度）、残像は −30 度（スライス 2 は 150〜240 度）
        scene.trail(trailFrame(ghosts: [WheelTrails.Ghost(angle: -30, opacity: 0.3)]))
        let pixels = try render(scene)
        let plain = try render(makeScene(count: 4, rotation: 90))
        let slice2 = srgb(Theme.sliceColor(at: 2, count: 4))
        let shifted = pixels.color(at: location(angle: 170, fraction: 0.6, pixels: pixels))
        let before = plain.color(at: location(angle: 170, fraction: 0.6, pixels: plain))
        #expect(distance(shifted, slice2) < distance(before, slice2) - 0.03, "\(shifted) \(before)")
    }

    @Test func 残像は濃いほど遅れた角度の色に寄る() throws {
        let weak = makeScene(count: 4, rotation: 0)
        weak.trail(trailFrame(ghosts: [WheelTrails.Ghost(angle: -120, opacity: 0.1)]))
        let strong = makeScene(count: 4, rotation: 0)
        strong.trail(trailFrame(ghosts: [WheelTrails.Ghost(angle: -120, opacity: 0.3)]))
        let weakPixels = try render(weak), strongPixels = try render(strong)
        let slice2 = srgb(Theme.sliceColor(at: 2, count: 4))
        let w = weakPixels.color(at: location(angle: 80, fraction: 0.6, pixels: weakPixels))
        let s = strongPixels.color(at: location(angle: 80, fraction: 0.6, pixels: strongPixels))
        #expect(distance(s, slice2) < distance(w, slice2), "\(s) \(w)")
    }

    @Test func 光の尾も残像も出さないときはノードを作らず今の盤面のまま() throws {
        let plain = try render(makeScene(count: 4, rotation: 0))
        let scene = makeScene(count: 4, rotation: 0)
        scene.trail(.none)
        #expect(!scene.hasTrailNodes)
        // 閾値未満の速さでは何も描かない
        let slow = TimedSpinMotion(
            motion: SpinMotion(from: 0, to: 2000, duration: 10, easing: CubicBezierCurve(0.33, 0.33, 0.67, 0.67)), start: 0
        )
        let below = WheelTrails.frame(motion: slow, now: 5, sliceCount: 4, lowPower: false, reduceMotion: false)
        #expect(below.isEmpty)
        scene.trail(below)
        #expect(!scene.hasTrailNodes)
        let pixels = try render(scene)
        for angle in [-31.25, -91.25, 31.25] {
            let ring = pixels.color(at: trailLocation(angle: angle, pixels: pixels))
            #expect(distance(ring, plain.color(at: trailLocation(angle: angle, pixels: plain))) < 0.01, "\(angle)")
            let face = pixels.color(at: location(angle: angle + 360, fraction: 0.6, pixels: pixels))
            #expect(distance(face, plain.color(at: location(angle: angle + 360, fraction: 0.6, pixels: plain))) < 0.01, "\(angle)")
        }
    }

    @Test func 描いたあと消すと今の盤面に戻り組み直しても出し直す() throws {
        let plain = try render(makeScene(count: 4, rotation: 0))
        let scene = makeScene(count: 4, rotation: 0)
        let frame = trailFrame(ghosts: [WheelTrails.Ghost(angle: -120, opacity: 0.3)])
        scene.trail(frame)
        scene.trail(.none)
        let cleared = try render(scene)
        for point in [trailLocation(angle: -21.25, pixels: cleared), location(angle: 80, fraction: 0.6, pixels: cleared)] {
            #expect(distance(cleared.color(at: point), plain.color(at: point)) < 0.01)
        }
        // 大きさが変わって組み直しても、出していれば出し直す
        scene.trail(frame)
        scene.update(labels: Array(repeating: "", count: 4), diameter: size + 1)
        scene.update(labels: Array(repeating: "", count: 4), diameter: size)
        let rebuilt = try render(scene)
        let tail = rebuilt.color(at: trailLocation(angle: -21.25, pixels: rebuilt))
        #expect(brightness(tail) > brightness(plain.color(at: trailLocation(angle: -21.25, pixels: plain))) + 0.2)
    }

    @Test func 項目が1件のときは残像を描かない() throws {
        let plain = try render(makeScene(count: 1, rotation: 0))
        let scene = makeScene(count: 1, rotation: 0)
        scene.trail(trailFrame(ghosts: [WheelTrails.Ghost(angle: -30, opacity: 0.3)]))
        let pixels = try render(scene)
        let face = pixels.color(at: location(angle: 80, fraction: 0.6, pixels: pixels))
        #expect(distance(face, plain.color(at: location(angle: 80, fraction: 0.6, pixels: plain))) < 0.01)
    }

    @Test func 結果の帯は残像より手前で帯の余白は残像を隠さない() throws {
        let result = Wheel3DResult(id: "a1", label: "\u{3000}", accent: Theme.sliceColor(at: 2, count: 4))
        // 帯の上の余白（約 158 度）は今はスライス 1、残像ではスライス 3
        let ghost = trailFrame(ghosts: [WheelTrails.Ghost(angle: -135, opacity: 0.3)])
        let banded = makeScene(count: 4, rotation: 0)
        banded.show(result: result, reduceMotion: true)
        let withGhost = makeScene(count: 4, rotation: 0)
        withGhost.show(result: result, reduceMotion: true)
        withGhost.trail(ghost)
        let before = try render(banded), after = try render(withGhost)
        // 帯の中央は帯の地のまま
        let center = after.color(at: location(x: 0, y: bandCenterY, pixels: after))
        #expect(isClose(center, srgb(Theme.resultBandFill)), "\(center)")
        // 帯の上の余白（画像の透明な縁）からは残像が見える
        let margin = location(x: 15, y: bandCenterY + ResultBand.height(diameter: Double(size)) / 2 + 4, pixels: after)
        #expect(distance(after.color(at: margin), before.color(at: margin)) > 0.02, "\(after.color(at: margin)) \(before.color(at: margin))")
    }

    /// 強調の状態。
    enum HighlightPhase: String, CaseIterable {
        /// 強調を出した直後（暗くする層は 0 から濃くなり始めたところ。画面外描画は動きの始まりを描く）。止まったスライスは持ち上げてある。
        case appearing
        /// 強調を出し切った（動きを減らす設定と同じく即座に出すので、暗くする層は最初から濃い）。
        case settled
        /// 強調を消し始めた。
        case clearing
    }

    /// 止まったスライス 1（90〜180 度）を `phase` の状態で強調した盤に、光の尾と残像を重ねる。
    private func highlightedScene(_ phase: HighlightPhase, trails: WheelTrails.Frame) -> Wheel3DScene {
        let scene = makeScene(count: 4, rotation: 0)
        scene.highlight(Wheel3DHighlight(index: 1, glowStyle: .white), reduceMotion: phase == .settled)
        if phase == .clearing { scene.highlight(nil, reduceMotion: false) }
        scene.trail(trails)
        return scene
    }

    @Test(arguments: HighlightPhase.allCases)
    func 強調を出したままでも消している途中でも光の尾と残像は板に隠れない(phase: HighlightPhase) throws {
        // 光の尾（−11.25 度）と残像を見る位置（300 度）は、沈めたスライス 3 の上。残像ではスライス 0 になる
        let frame = trailFrame(ghosts: [WheelTrails.Ghost(angle: -120, opacity: 0.3)])
        let plain = try render(highlightedScene(phase, trails: .none))
        let pixels = try render(highlightedScene(phase, trails: frame))
        let tail = trailLocation(angle: -11.25, pixels: pixels)
        #expect(brightness(pixels.color(at: tail)) > brightness(plain.color(at: tail)) + 0.2, "\(pixels.color(at: tail)) \(plain.color(at: tail))")
        let ghost = location(angle: 300, fraction: 0.6, pixels: pixels)
        #expect(distance(pixels.color(at: ghost), plain.color(at: ghost)) > 0.02, "\(pixels.color(at: ghost)) \(plain.color(at: ghost))")
        switch phase {
        case .clearing:
            // 消している途中は、止まったスライス（90〜180 度、持ち上げた板）の上でも残像（スライス 2）が見える
            let stopped = location(angle: 135, fraction: 0.6, pixels: pixels)
            #expect(distance(pixels.color(at: stopped), plain.color(at: stopped)) > 0.02, "\(pixels.color(at: stopped)) \(plain.color(at: stopped))")
        case .settled:
            // 暗くする層が濃く出ていても、残像はその上に見え（上の確かめ）、沈めたスライスは残像の下で沈んだまま（残像が暗くする層を消さない）。
            // `distance` は成分ごとの差の最大。暗くする層が無い盤に同じ残像を重ねた色は緑で最大（0.7·lin(0.859) + 0.3·lin(0.502) → sRGB 0.773、
            // `onSlice` から 0.706）、暗くした上に重ねた色は赤で最大（0.7·0.187 + 0.3·1 → sRGB 0.688、`onSlice` から約 0.598。
            // 緑は 0.7·0.357 + 0.3·0.216 → sRGB 0.597 で約 0.53）なので、暗くした方が `onSlice` に近い
            let bare = makeScene(count: 4, rotation: 0)
            bare.trail(frame)
            let unlit = try render(bare)
            let ink = srgb(Theme.onSlice)
            #expect(distance(pixels.color(at: ghost), ink) < distance(unlit.color(at: ghost), ink) - 0.03,
                    "\(pixels.color(at: ghost)) \(unlit.color(at: ghost))")
        case .appearing:
            break
        }
    }

    // MARK: 組み直し

    @Test func 項目の色が変わって組み直すと残像の塗りも新しい色にする() throws {
        // 120 度遅れた残像の、80 度の位置（今はスライス 0、残像ではスライス 2）
        let frame = trailFrame(ghosts: [WheelTrails.Ghost(angle: -120, opacity: 0.3)])
        let scene = makeScene(count: 4, rotation: 0)
        scene.trail(frame)
        let before = try render(scene)
        scene.update(items: [Item(label: ""), Item(label: ""), Item(label: "", appearance: .color(.purple)), Item(label: "")], diameter: size)
        let after = try render(scene)
        let point = location(angle: 80, fraction: 0.6, pixels: after)
        // 下のスライス 0 は同じ色のまま、残像のスライス 2 が紫になった分だけ紫に寄る
        #expect(distance(after.color(at: point), srgb(purple)) < distance(before.color(at: point), srgb(purple)) - 0.02,
                "\(after.color(at: point)) \(before.color(at: point))")
    }

    @Test func 組み直すと電球の明るさの覚えを捨てて塗り直す() throws {
        let scene = makeScene(count: 4, rotation: 0)
        let lights = WheelLights.Scene.running(angle: 0, intensity: 0)
        scene.light(lights)
        #expect(scene.bulbColorWriteCount == Config.wheelLightCount)
        // 大きさが変わる・項目の色が変わると電球を作り直すので、明るさが同じでも全部塗り直す
        scene.update(labels: Array(repeating: "", count: 4), diameter: size + 1)
        #expect(scene.bulbColorWriteCount == Config.wheelLightCount * 2)
        scene.update(items: styledItems, diameter: size)
        #expect(scene.bulbColorWriteCount == Config.wheelLightCount * 3)
        let pixels = try render(scene)
        for index in [6, 7] {
            let expected = bulbColor(WheelLights.bulb(index: index, scene: lights).brightness)
            let color = pixels.color(at: lightLocation(index: index, pixels: pixels))
            #expect(isClose(color, expected), "\(index): \(color) expected \(expected)")
        }
    }

    // MARK: 光の尾の書き換え

    @Test func 濃さの変わらない光の尾の切れ端は書き換えない() throws {
        let scene = makeScene(count: 4, rotation: 0)
        let trail = trailFrame()
        scene.trail(trail)
        let written = scene.trailOpacityWriteCount
        #expect(written > 0)
        // 残像だけが変わったフレーム・消して同じ尾を出し直したフレームでは、切れ端を書き換えない
        scene.trail(trailFrame(ghosts: [WheelTrails.Ghost(angle: -30, opacity: 0.2)]))
        scene.trail(.none)
        scene.trail(trail)
        #expect(scene.trailOpacityWriteCount == written)
        // 出し直しても今の濃さのまま描く
        let plain = try render(makeScene(count: 4, rotation: 0))
        let pixels = try render(scene)
        let tail = trailLocation(angle: -11.25, pixels: pixels)
        #expect(brightness(pixels.color(at: tail)) > brightness(plain.color(at: tail)) + 0.2)
        // 尾が短くなれば、濃さの変わった切れ端だけ書き換える
        scene.trail(trailFrame(length: 40))
        let changed = scene.trailOpacityWriteCount - written
        #expect(changed > 0 && changed <= Int((40 / Theme.Wheel3D.trailPieceAngle).rounded(.up)))
    }

    @Test func 光の尾のにじみは外周の縁の外へはみ出さない() throws {
        let bounds = Theme.Wheel3D.trailGlowBounds(diameter: size)
        let scale = Double(size) / WheelLabel.referenceDiameter
        let sliceRadius = WheelGeometry.sliceRadius(diameter: Double(size))
        let ring = Double(Theme.TrailRing.ringRadius(diameter: size))
        #expect(abs(Double(bounds.outer) - (sliceRadius + Double(Theme.Wheel3D.rimWidth) * scale)) < 1e-9)
        #expect(abs(Double(bounds.inner) - (ring - Double(Theme.TrailRing.glowWidth) * scale / 2)) < 1e-9)

        let plain = try render(makeScene(count: 4, rotation: 0))
        let scene = makeScene(count: 4, rotation: 0)
        scene.trail(trailFrame())
        let pixels = try render(scene)
        let distanceToCamera = WheelGeometry.cameraDistance(diameter: Double(canvas), fieldOfView: Theme.Wheel3D.fieldOfView)
        let z = Double(Theme.Wheel3D.rimLift) * scale + Double(Theme.Wheel3D.trailLift)
        for angle in [-11.25, -41.25] {
            // 縁の外（スライスの円の外 13pt。2D のにじみの外側は 14pt まで届く）は地のまま
            let outside = WheelGeometry.point(angle: angle, radius: (sliceRadius + 13 * scale) * distanceToCamera / (distanceToCamera - z))
            let point = location(x: outside.x, y: outside.y, pixels: pixels)
            #expect(distance(pixels.color(at: point), plain.color(at: point)) < 0.01, "\(angle): \(pixels.color(at: point))")
        }
    }

    // MARK: 直径 480

    @Test func 直径480でもスライス_針_電球_光の尾_帯が同じ割り付けで出る() throws {
        var large = self
        large.size = 480
        try large.checkLayout()
    }

    /// 今の直径で、スライスの塗り・針・電球・光の尾・結果の帯が盤面の割り付けどおりの位置に出るか。
    private func checkLayout() throws {
        let plain = try render(makeScene(count: 4, rotation: 0))
        for index in 0..<4 {
            let color = plain.color(at: location(angle: 45 + 90 * Double(index), fraction: 0.6, pixels: plain))
            #expect(isClose(color, srgb(Theme.sliceColor(at: index, count: 4))), "\(size) slice \(index): \(color)")
        }
        let pointer = plain.color(at: location(x: 0, y: Double(size) / 2 - 8, pixels: plain))
        #expect(isClose(pointer, srgb(Theme.flare)), "\(size) pointer: \(pointer)")

        let lit = makeScene(count: 4, rotation: 0)
        lit.light(.still)
        let lights = try render(lit)
        for index in [3, 6, 15] {
            let color = lights.color(at: lightLocation(index: index, pixels: lights))
            #expect(isClose(color, bulbColor(WheelLights.stillLevel)), "\(size) bulb \(index): \(color)")
        }

        let trailed = makeScene(count: 4, rotation: 0)
        trailed.trail(trailFrame())
        let trails = try render(trailed)
        let tail = trailLocation(angle: -41.25, pixels: trails)
        #expect(brightness(trails.color(at: tail)) > brightness(plain.color(at: tail)) + 0.2, "\(size) trail")

        let banded = makeScene(count: 4, rotation: 0)
        banded.show(result: Wheel3DResult(id: "a1", label: "\u{3000}", accent: Theme.sliceColor(at: 2, count: 4)), reduceMotion: true)
        let band = try render(banded)
        let center = band.color(at: location(x: 0, y: bandCenterY, pixels: band))
        #expect(isClose(center, srgb(Theme.resultBandFill)), "\(size) band: \(center)")

        let sparked = makeScene(count: 4, rotation: 0)
        let point = CGPoint(x: size / 2 + 50 * size / 320, y: 70)
        sparked.particles(WheelParticles.Frame(sparks: [WheelParticles.Spark(position: point, tail: .zero, radius: 3, opacity: 1)]))
        let spark = try render(sparked)
        let core = spark.color(at: particleLocation(point, compensated: false, pixels: spark))
        #expect(isClose(core, srgb(Theme.wheelSpark)), "\(size) spark: \(core)")
    }

    // MARK: 火花・紙吹雪

    /// 粒の面（針と同じ奥行き）の、盤面の枠の左上を原点とする位置（pt、y が下向き）の画素の位置。紙吹雪は遠近の広がりを打ち消してあるので
    /// `compensated` で、火花は針と同じく浮かせた分だけ外へ広がって見える。
    private func particleLocation(_ point: CGPoint, compensated: Bool, pixels: Pixels) -> CGPoint {
        let x = Double(point.x) - Double(size) / 2, y = Double(size) / 2 - Double(point.y)
        guard !compensated else { return location(x: x, y: y, pixels: pixels) }
        let z = Double(Wheel3DScene.pointerZ(scale: Double(size) / WheelLabel.referenceDiameter))
        let distance = WheelGeometry.cameraDistance(diameter: Double(canvas), fieldOfView: Theme.Wheel3D.fieldOfView)
        let k = distance / (distance - z)
        return location(x: x * k, y: y * k, pixels: pixels)
    }

    @Test func 火花は2Dと同じ位置に芯の色で出て尾を引く() throws {
        let plain = try render(makeScene(count: 4, rotation: 0))
        let scene = makeScene(count: 4, rotation: 0)
        let point = CGPoint(x: size / 2 + 50, y: 70)
        // 尾は左へ 20pt（にじみの半径 9pt より長い）
        scene.particles(WheelParticles.Frame(sparks: [
            WheelParticles.Spark(position: point, tail: CGVector(dx: -20, dy: 0), radius: 3, opacity: 1),
        ]))
        let pixels = try render(scene)
        let core = pixels.color(at: particleLocation(point, compensated: false, pixels: pixels))
        #expect(isClose(core, srgb(Theme.wheelSpark)), "\(core)")
        // にじみの外の尾は橙に寄る
        let tailPoint = particleLocation(CGPoint(x: point.x - 13, y: point.y), compensated: false, pixels: pixels)
        #expect(distance(pixels.color(at: tailPoint), plain.color(at: tailPoint)) > 0.05, "\(pixels.color(at: tailPoint))")
        // 尾の逆側のにじみの外は盤のまま
        let ahead = particleLocation(CGPoint(x: point.x + 13, y: point.y), compensated: false, pixels: pixels)
        #expect(distance(pixels.color(at: ahead), plain.color(at: ahead)) < 0.01, "\(pixels.color(at: ahead))")
    }

    private func confetto(at point: CGPoint, side: CGFloat = 14, colorIndex: Int = 7) -> WheelParticles.Confetto {
        WheelParticles.Confetto(
            position: point, size: CGSize(width: side, height: side), rotation: 0, flip: 1, colorIndex: colorIndex, opacity: 1
        )
    }

    @Test func 紙吹雪は2Dと同じ位置と色で針より手前_結果の帯より奥に出る() throws {
        let scene = makeScene(count: 4, rotation: 0)
        scene.show(result: Wheel3DResult(id: "a1", label: "\u{3000}", accent: Theme.sliceColor(at: 2, count: 4)), reduceMotion: true)
        let open = CGPoint(x: size / 2 - 60, y: size / 2 + 10)
        let onPointer = CGPoint(x: size / 2, y: 8)
        let onBand = CGPoint(x: size / 2, y: size / 2 - bandCenterY)
        scene.particles(WheelParticles.Frame(confetti: [confetto(at: open), confetto(at: onPointer), confetto(at: onBand)]))
        let pixels = try render(scene)
        let color = srgb(Theme.confettiColors[7])
        let shown = pixels.color(at: particleLocation(open, compensated: true, pixels: pixels))
        #expect(isClose(shown, color), "\(shown)")
        let pointer = pixels.color(at: particleLocation(onPointer, compensated: true, pixels: pixels))
        #expect(isClose(pointer, color), "\(pointer)")
        let band = pixels.color(at: particleLocation(onBand, compensated: true, pixels: pixels))
        #expect(isClose(band, srgb(Theme.resultBandFill)), "\(band)")
    }

    @Test func 火花は2Dと同じく紙吹雪の上に重なる() throws {
        let scene = makeScene(count: 4, rotation: 0)
        // 火花の芯（半径 3pt）を、それより大きい紙片（26pt 角）の真ん中に重ねる。火花は遠近で外へ広がって見えるので、紙片をその位置に置く
        let point = CGPoint(x: size / 2 + 50, y: 70)
        let z = Double(Wheel3DScene.pointerZ(scale: Double(size) / WheelLabel.referenceDiameter))
        let distanceToCamera = WheelGeometry.cameraDistance(diameter: Double(canvas), fieldOfView: Theme.Wheel3D.fieldOfView)
        let spread = distanceToCamera / (distanceToCamera - z)
        let under = CGPoint(x: size / 2 + 50 * spread, y: size / 2 - (size / 2 - 70) * spread)
        scene.particles(WheelParticles.Frame(
            sparks: [WheelParticles.Spark(position: point, tail: .zero, radius: 3, opacity: 1)],
            confetti: [confetto(at: under, side: 26)]
        ))
        let pixels = try render(scene)
        let core = pixels.color(at: particleLocation(point, compensated: false, pixels: pixels))
        #expect(isClose(core, srgb(Theme.wheelSpark)), "\(core)")
        // 火花のにじみ（半径 9pt）の外の紙片の中は、紙吹雪の色のまま
        let beside = pixels.color(at: particleLocation(CGPoint(x: under.x + 11, y: under.y), compensated: true, pixels: pixels))
        #expect(isClose(beside, srgb(Theme.confettiColors[7])), "\(beside)")
    }

    @Test func 紙吹雪は盤面の枠の外へ広げない() throws {
        // 直径 480 で、遠近の広がりを打ち消しているときだけ「外」になる位置を見る
        var large = self
        large.size = 480
        try large.checkConfettiInsideFrame()
    }

    /// 枠の右端に接する紙片（枠の内側 8pt）が、正面から見て枠の右端（盤の中心から半径 = 直径 ÷ 2）で切れて見えるか。
    /// 手計算（直径 480）: 紙吹雪の面の高さ z = 針の奥行き = (6 × 1.5 + 1) + 2 = 12pt、描く範囲 624pt、カメラまでの距離
    /// d = 312 ÷ tan 15° ≈ 1164.4pt で、縮めないと d ÷ (d − z) ≈ 1.0104 倍に広がり、紙片の外端は 240 × 1.0104 ≈ 242.5pt に見える。
    /// 縮めれば外端は 240pt。「外」として見る 241pt は、縮めれば外（1pt）、縮めなければ内（1.5pt）になる。
    private func checkConfettiInsideFrame() throws {
        let plain = try render(makeScene(count: 4, rotation: 0))
        let scene = makeScene(count: 4, rotation: 0)
        scene.particles(WheelParticles.Frame(confetti: [confetto(at: CGPoint(x: size - 4, y: size / 2), side: 8)]))
        let pixels = try render(scene)
        let inside = location(x: Double(size) / 2 - 4, y: 0, pixels: pixels)
        #expect(isClose(pixels.color(at: inside), srgb(Theme.confettiColors[7])), "\(pixels.color(at: inside))")
        let outside = location(x: Double(size) / 2 + 1, y: 0, pixels: pixels)
        #expect(distance(pixels.color(at: outside), plain.color(at: outside)) < 0.01, "\(pixels.color(at: outside))")
    }

    @Test func 火花と紙吹雪は2Dと同じ関数で引いた数だけ出しノードは使い回す() throws {
        let scene = makeScene(count: 4, rotation: 0)
        scene.particles(.none)
        #expect(scene.particleNodeCount == 0)
        let motion = TimedSpinMotion(
            motion: SpinMotion(from: 0, to: 7200, duration: 10, easing: CubicBezierCurve(0.33, 0.33, 0.67, 0.67)), start: 0
        )
        for lowPower in [false, true] {
            for now in [5.0, 5.2, 5.5] {
                let frame = WheelParticles.frame(
                    motion: motion, drag: nil, burst: WheelParticles.Burst(start: 4.9, seed: 3), now: now, spinSeed: 42, dragSeed: 0,
                    side: size, colorCount: Theme.confettiColors.count, lowPower: lowPower, reduceMotion: false
                )
                #expect(!frame.sparks.isEmpty && !frame.confetti.isEmpty)
                scene.particles(frame)
                #expect(scene.visibleSparkCount == frame.sparks.filter { $0.opacity > 0 }.count)
                #expect(scene.visibleConfettiCount == frame.confetti.filter { $0.opacity > 0 }.count)
                #expect(scene.visibleSparkCount <= WheelParticles.sparkCapacity(lowPower: lowPower))
                #expect(scene.visibleConfettiCount <= WheelParticles.confettiCapacity(lowPower: lowPower))
                // 粒のノードは上限の数だけ作って使い回す
                #expect(scene.particleNodeCount == Config.wheelSparkMaxCount + Config.wheelConfettiMaxCount)
            }
        }
        // 組み直しても作り直すだけで、数は変わらない
        scene.update(labels: Array(repeating: "", count: 4), diameter: size + 1)
        #expect(scene.particleNodeCount == Config.wheelSparkMaxCount + Config.wheelConfettiMaxCount)
        scene.update(labels: Array(repeating: "", count: 4), diameter: size)
        scene.particles(.none)
        #expect(scene.visibleSparkCount == 0)
        #expect(scene.visibleConfettiCount == 0)
        let plain = try render(makeScene(count: 4, rotation: 0))
        let pixels = try render(scene)
        for angle in [0.0, 30, 330] {
            let point = location(angle: angle, fraction: 0.8, pixels: pixels)
            #expect(distance(pixels.color(at: point), plain.color(at: point)) < 0.01, "\(angle)")
        }
    }

    // MARK: 停止の瞬間のフラッシュ・余韻

    @Test func フラッシュは盤面の枠の中を中心ほど明るく光らせ針と枠の外は変えない() throws {
        let plain = try render(makeScene(count: 4, rotation: 0))
        let scene = makeScene(count: 4, rotation: 0)
        scene.stopEffects(WheelStopEffects.Frame(flashOpacity: WheelStopEffects.flashPeakOpacity, glowLevel: 1))
        let pixels = try render(scene)
        let gain = { (point: CGPoint) in brightness(pixels.color(at: point)) - brightness(plain.color(at: point)) }
        // 中心寄り（ハブの上も。中心の白い点を避けてハブの暗い地で見る）ほど明るく、縁寄りは弱い
        let hub = location(x: 11 * Double(size) / WheelLabel.referenceDiameter, y: 0, pixels: pixels)
        let inner = location(angle: 45, fraction: 0.2, pixels: pixels)
        let outer = location(angle: 45, fraction: 0.95, pixels: pixels)
        #expect(gain(hub) > 0.05, "\(gain(hub))")
        #expect(gain(inner) > 0.05, "\(gain(inner))")
        #expect(gain(inner) > gain(outer) + 0.03, "\(gain(inner)) \(gain(outer))")
        // 枠の角（円の外）は変えない
        let corner = location(x: Double(size) / 2 - 3, y: -Double(size) / 2 + 3, pixels: pixels)
        #expect(distance(pixels.color(at: corner), plain.color(at: corner)) < 0.01, "\(pixels.color(at: corner))")
        // 正面から見た丸い光の半径は、浮かせた分の遠近の広がりを打ち消して盤面の枠の半径と同じ。光は縁へ向けて 0 まで薄くなるので、
        // 縁の近くの画素では縮めの有無を見分けられない（直径 320 で縮めないと半径 ≈ 161.3pt、縁から 1pt 内の不透明度は 0.25 × 1.4 × 2.3 ÷ 161.3 ≈ 0.005）。
        // 板の置き方から求める（縮めないと 1.0084 倍で、許容を超える）
        let placement = try #require(scene.flashPlacement)
        let distanceToCamera = WheelGeometry.cameraDistance(diameter: Double(canvas), fieldOfView: Theme.Wheel3D.fieldOfView)
        let apparent = placement.side / 2 * placement.scale * distanceToCamera / (distanceToCamera - placement.z)
        #expect(abs(apparent - Double(size) / 2) < 1e-3, "\(apparent)")
        // 消えたら今の盤面のまま
        scene.stopEffects(.none)
        let cleared = try render(scene)
        #expect(distance(cleared.color(at: inner), plain.color(at: inner)) < 0.01)
    }

    @Test func フラッシュは針に隠れる() throws {
        // 針の先の近く（中心から 148pt）でも光がはっきり見えるよう、不透明度 1 で光らせる
        // （0.25 だと針の先のあたりの不透明度は 0.25 × 1.4 × 12 ÷ 160 ≈ 0.03 で、針の色の許容 0.04 に収まってしまう）
        let plain = try render(makeScene(count: 4, rotation: 0))
        let scene = makeScene(count: 4, rotation: 0)
        scene.stopEffects(WheelStopEffects.Frame(flashOpacity: 1, glowLevel: 1))
        let pixels = try render(scene)
        let y = 148 * Double(size) / WheelLabel.referenceDiameter
        // 針のすぐ横（縁の上）は光る（不透明度 ≈ 1.4 × 12 ÷ 160 ≈ 0.1）
        let beside = location(x: 8 * Double(size) / WheelLabel.referenceDiameter, y: y, pixels: pixels)
        #expect(brightness(pixels.color(at: beside)) > brightness(plain.color(at: beside)) + 0.05,
                "\(pixels.color(at: beside)) \(plain.color(at: beside))")
        // 針（先から約 6pt 上で幅 5pt）は光の手前で、針の色のまま（光が上に重なると緑・青が約 0.07 明るくなり許容を超える）
        let pointer = pixels.color(at: location(x: 0, y: y, pixels: pixels))
        #expect(isClose(pointer, srgb(Theme.flare)), "\(pointer)")
        #expect(isClose(plain.color(at: location(x: 0, y: y, pixels: plain)), srgb(Theme.flare)))
    }

    /// 止まったスライス 2 を強調した盤。`afterglow` は停止の演出が ON（余韻を出せる形）か。
    /// 動きを減らす設定では余韻を出さないので、どちらも押し出す側（`reduceMotion: false`）で比べる。
    private func glowingScene(afterglow: Bool, level: Double? = nil) -> Wheel3DScene {
        let scene = makeScene(count: 4, rotation: 0)
        scene.highlight(Wheel3DHighlight(index: 2, glowStyle: .white), reduceMotion: false, afterglow: afterglow)
        if let level { scene.stopEffects(WheelStopEffects.Frame(flashOpacity: 0, glowLevel: level)) }
        return scene
    }

    /// 止まったスライス 2（180〜270 度）の始まりの境目から、隣のスライス 1 へ 5pt 入った位置（光彩の中）。
    private func glowLocation(pixels: Pixels) -> CGPoint {
        let radius = (Double(size) / 2 - 16 * Double(size) / WheelLabel.referenceDiameter) * 0.6
        return location(angle: 180 - 5 / radius * 180 / .pi, fraction: 0.6, pixels: pixels)
    }

    @Test func 余韻の倍率で止まったスライスの光彩だけが薄くなる() throws {
        let fullPixels = try render(glowingScene(afterglow: true, level: 1))
        let lowPixels = try render(glowingScene(afterglow: true, level: WheelStopEffects.afterglowLowLevel))
        let near = glowLocation(pixels: fullPixels)
        let plain = lowPixels.color(at: location(angle: 135, fraction: 0.6, pixels: lowPixels))
        // 光彩は弱くなるが消えない
        #expect(brightness(fullPixels.color(at: near)) > brightness(lowPixels.color(at: near)) + 0.03,
                "\(fullPixels.color(at: near)) \(lowPixels.color(at: near))")
        #expect(brightness(lowPixels.color(at: near)) > brightness(plain) + 0.02, "\(lowPixels.color(at: near)) \(plain)")
        // 止まったスライスの塗りと縁取りは変えない
        for (angle, color) in [(225.0, Theme.sliceColor(at: 2, count: 4)), (180, Theme.stopOutline)] {
            let point = location(angle: angle, fraction: 0.6, pixels: lowPixels)
            #expect(isClose(lowPixels.color(at: point), srgb(color)), "\(angle): \(lowPixels.color(at: point))")
        }
        // 盤を組み直して強調を出し直しても、今の倍率のまま（同じく組み直した倍率 1 の盤より光彩が弱い）
        let rebuild = { (scene: Wheel3DScene) -> Wheel3DScene in
            scene.update(labels: Array(repeating: "", count: 4), diameter: self.size + 1)
            scene.update(labels: Array(repeating: "", count: 4), diameter: self.size)
            scene.highlight(Wheel3DHighlight(index: 2, glowStyle: .white), reduceMotion: false, afterglow: true)
            return scene
        }
        let rebuiltFull = try render(rebuild(glowingScene(afterglow: true, level: 1)))
        let rebuiltLow = try render(rebuild(glowingScene(afterglow: true, level: WheelStopEffects.afterglowLowLevel)))
        #expect(brightness(rebuiltFull.color(at: near)) > brightness(rebuiltLow.color(at: near)) + 0.03,
                "\(rebuiltFull.color(at: near)) \(rebuiltLow.color(at: near))")
    }

    @Test func なしでは止まったスライスを1枚で焼き粒もフラッシュの板も作らない() throws {
        let none = glowingScene(afterglow: false)
        none.stopEffects(.none)
        none.particles(.none)
        #expect(none.stoppedImagePlaneCount == 1)
        #expect(!none.hasFlashNode)
        #expect(none.particleNodeCount == 0)
        // 余韻を出すときは 2 枚。動きを減らす設定では余韻を出さないので 1 枚
        #expect(glowingScene(afterglow: true).stoppedImagePlaneCount == 2)
        let reduced = makeScene(count: 4, rotation: 0)
        reduced.highlight(Wheel3DHighlight(index: 2, glowStyle: .white), reduceMotion: true, afterglow: true)
        #expect(reduced.stoppedImagePlaneCount == 1)
        // 倍率 1 の 2 枚は余韻を出さない 1 枚と同じ見た目
        let single = try render(none)
        let double = try render(glowingScene(afterglow: true, level: 1))
        for point in [glowLocation(pixels: single), location(angle: 225, fraction: 0.6, pixels: single),
                      location(angle: 180, fraction: 0.6, pixels: single)] {
            #expect(distance(single.color(at: point), double.color(at: point)) < 0.02, "\(single.color(at: point)) \(double.color(at: point))")
        }
        // 結果を出したまま演出を切り替えたら、その形で出し直す
        none.highlight(Wheel3DHighlight(index: 2, glowStyle: .white), reduceMotion: false, afterglow: true)
        #expect(none.stoppedImagePlaneCount == 2)
        none.highlight(Wheel3DHighlight(index: 2, glowStyle: .white), reduceMotion: false, afterglow: false)
        #expect(none.stoppedImagePlaneCount == 1)
    }

    /// 止まった瞬間の針の沈みは 2D と同じ量（停止の演出が ON なら 8pt、OFF なら 4pt）。動きを減らす設定では沈めない。
    @Test func 針は停止の演出がONなら2倍沈む() {
        let cases: [(PointerBounce, Double)] = [(.big, 8), (.normal, 4)]
        for (bounce, depth) in cases {
            let scene = makeScene(count: 4, rotation: 0)
            scene.highlight(Wheel3DHighlight(index: 2, glowStyle: .white), reduceMotion: false, pointerBounce: bounce)
            #expect(abs(scene.pointerBounceDepth - depth) < 1e-9, "\(bounce)")
        }
        let still = makeScene(count: 4, rotation: 0)
        still.highlight(Wheel3DHighlight(index: 2, glowStyle: .white), reduceMotion: true, pointerBounce: .big)
        #expect(still.pointerBounceDepth == 0)
    }

    @Test func 結果の帯はなし以外のとき新しい結果でだけ登場演出を重ねる() {
        let scene = makeScene(count: 4, rotation: 0)
        let result = { (id: String) in Wheel3DResult(id: id, label: "\u{3000}", accent: Theme.sliceColor(at: 1, count: 4)) }
        scene.show(result: result("a1"), reduceMotion: false, popIn: true)
        #expect(scene.bandPopCount == 1)
        #expect(scene.bandRevealCount == 1)
        // 停止の演出が OFF・動きを減らす設定では重ねない
        scene.show(result: nil, reduceMotion: false, popIn: true)
        scene.show(result: result("a2"), reduceMotion: false, popIn: false)
        scene.show(result: nil, reduceMotion: false, popIn: true)
        scene.show(result: result("a3"), reduceMotion: true, popIn: true)
        #expect(scene.bandPopCount == 1)
        // 結果を出したまま見た目を変えて焼き直しても繰り返さない
        scene.show(result: nil, reduceMotion: false, popIn: true)
        scene.show(result: result("a4"), reduceMotion: false, popIn: true)
        scene.update(items: styledItems, diameter: size)
        scene.show(result: result("a4"), reduceMotion: false, popIn: true)
        #expect(scene.bandPopCount == 2)
    }
}
