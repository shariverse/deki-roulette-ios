import Metal
import SceneKit
import SwiftUI
import Testing
@testable import DekiRoulette

/// 3D の盤面を画面外で描き、スライスの並び・回る向き・塗りの色を画素で確かめる。
@MainActor
struct Wheel3DSceneTests {
    private let size: CGFloat = 320
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

    private func render(_ scene: Wheel3DScene) throws -> Pixels {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene.scene
        renderer.pointOfView = scene.cameraNode
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: canvas, height: canvas), antialiasingMode: .none)
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
    }

    @Test func 電球は針の後ろ() throws {
        let scene = makeScene(count: 4, rotation: 0)
        scene.light(.running(angle: 0, intensity: 1))
        let pixels = try render(scene)
        // 12 時の電球（添字 0）は針に隠れる
        let color = pixels.color(at: lightLocation(index: 0, pixels: pixels))
        #expect(isClose(color, srgb(Theme.flare)), "\(color)")
    }
}
