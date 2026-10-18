import Foundation

/// 3D の盤面の形の計算。3D 空間は手前から見て x が右・y が上・z が手前で、盤は xy 平面に置いて手前（+z）へ向ける。
/// 角度は 2D と同じく 12 時を 0 度として、手前から見て時計回りに数える。
enum WheelGeometry {
    /// 盤面の枠からスライスの円までの距離（基準直径 `WheelLabel.referenceDiameter` での pt）。外周の縁（スライスの円の外 5〜11pt）と
    /// 枠までの余白はこの中に収まる。2D の `WheelFaceView`・3D の盤・電飾の環・光の尾・結果の帯（`ResultBand`）で同じ値を使う。
    static let sliceInset: Double = 16

    /// 直径 `diameter`（pt）の盤面のスライスの円の半径（pt）。
    static func sliceRadius(diameter: Double) -> Double {
        let diameter = max(diameter, 0)
        return diameter / 2 - sliceInset * diameter / WheelLabel.referenceDiameter
    }

    /// 盤面の角度 `angle`（度）・中心からの距離 `radius` の点を、盤の平面（xy）上の座標に写す。
    static func point(angle: Double, radius: Double) -> SIMD2<Double> {
        let rad = angle * .pi / 180
        return SIMD2(radius * sin(rad), radius * cos(rad))
    }

    /// `start` 度から `end` 度までの外周を等分した点（両端を含む）。1 周を `segmentsPerTurn` 等分する細かさで、
    /// 細いスライスでも最低 1 区間（2 点）にする。
    static func arc(start: Double, end: Double, radius: Double, segmentsPerTurn: Int = 96) -> [SIMD2<Double>] {
        let span = end - start
        let segments = max(1, Int((abs(span) / 360 * Double(segmentsPerTurn)).rounded(.up)))
        return (0...segments).map { step in
            point(angle: start + span * Double(step) / Double(segments), radius: radius)
        }
    }

    /// 1 枚のスライスの面。表面（z = 0、手前向き）は中心と外周の扇、側面は外周から奥（z = -thickness）への帯。
    /// どちらの三角形も、表から見て反時計回りに頂点を並べる（SceneKit の片面描画で表が描かれる向き）。
    struct SliceMesh: Equatable, Sendable {
        var vertices: [SIMD3<Double>]
        /// 頂点ごとの法線（表面は手前、側面は外向き）。
        var normals: [SIMD3<Double>]
        /// 表面の三角形（頂点の添字を 3 つずつ）。
        var top: [Int32]
        /// 側面の三角形。
        var side: [Int32]
    }

    /// `start` 度から `end` 度までのスライスの面。
    static func sliceMesh(start: Double, end: Double, radius: Double, thickness: Double) -> SliceMesh {
        let rim = arc(start: start, end: end, radius: radius)
        var mesh = SliceMesh(vertices: [SIMD3(0, 0, 0)], normals: [SIMD3(0, 0, 1)], top: [], side: [])
        for (offset, point) in rim.enumerated() {
            mesh.vertices.append(SIMD3(point.x, point.y, 0))
            mesh.normals.append(SIMD3(0, 0, 1))
            // 外周の点は手前から見て時計回りに進むので、中心・今の点・前の点の順で反時計回りになる
            if offset > 0 { mesh.top += [0, Int32(offset + 1), Int32(offset)] }
        }
        let sideStart = Int32(mesh.vertices.count)
        for (offset, point) in rim.enumerated() {
            let normal = SIMD3(point.x / radius, point.y / radius, 0)
            mesh.vertices += [SIMD3(point.x, point.y, 0), SIMD3(point.x, point.y, -thickness)]
            mesh.normals += [normal, normal]
            if offset > 0 {
                let top = sideStart + Int32(offset * 2), bottom = top + 1
                let previousTop = top - 2, previousBottom = top - 1
                // 外から見て反時計回り（前の上・今の上・前の下、今の上・今の下・前の下）
                mesh.side += [previousTop, top, previousBottom, top, bottom, previousBottom]
            }
        }
        return mesh
    }

    /// 盤の累積の回転角（度、時計回りが正。`RouletteModel.rotation`）を、z 軸まわりの回転（ラジアン）に写す。
    /// z 軸まわりは手前から見て反時計回りが正なので、符号を返す。
    static func spinAngle(rotation: Double) -> Double {
        -rotation * .pi / 180
    }

    /// 縦の画角 `fieldOfView`（度）の透視カメラで、盤の平面に置いた直径 `diameter` の円が縦にちょうど収まる距離。
    static func cameraDistance(diameter: Double, fieldOfView: Double) -> Double {
        let half = max(fieldOfView, 1) / 2 * .pi / 180
        return diameter / 2 / tan(half)
    }
}
