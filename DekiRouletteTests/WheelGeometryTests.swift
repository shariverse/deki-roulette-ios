import Foundation
import Testing
@testable import DekiRoulette

struct WheelGeometryTests {
    private func isClose(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Bool {
        abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9
    }

    @Test func スライスの円は盤面の枠から基準直径で16pt内側で直径に比例する() {
        #expect(abs(WheelGeometry.sliceRadius(diameter: 320) - 144) < 1e-9)
        #expect(abs(WheelGeometry.sliceRadius(diameter: 480) - 216) < 1e-9)
        #expect(WheelGeometry.sliceRadius(diameter: -10) == 0)
        // 結果の帯の寸法と同じ値
        #expect(WheelGeometry.sliceInset == ResultBand.baseSliceInset)
    }

    @Test func 零度は12時() {
        #expect(isClose(WheelGeometry.point(angle: 0, radius: 10), SIMD2(0, 10)))
    }

    /// 2D と同じく、手前から見て時計回りに進む（90 度で 3 時、180 度で 6 時）。
    @Test func 角度は手前から見て時計回り() {
        #expect(isClose(WheelGeometry.point(angle: 90, radius: 10), SIMD2(10, 0)))
        #expect(isClose(WheelGeometry.point(angle: 180, radius: 10), SIMD2(0, -10)))
        #expect(isClose(WheelGeometry.point(angle: 270, radius: 10), SIMD2(-10, 0)))
    }

    @Test func 外周は両端を含めて等分する() {
        let points = WheelGeometry.arc(start: 0, end: 90, radius: 10, segmentsPerTurn: 8)
        #expect(points.count == 3)
        #expect(isClose(points[0], SIMD2(0, 10)))
        #expect(isClose(points[1], WheelGeometry.point(angle: 45, radius: 10)))
        #expect(isClose(points[2], SIMD2(10, 0)))
    }

    @Test func 細いスライスでも最低1区間() {
        let points = WheelGeometry.arc(start: 10, end: 11, radius: 10, segmentsPerTurn: 8)
        #expect(points.count == 2)
    }

    @Test func 外周の点は半径の上にある() {
        for point in WheelGeometry.arc(start: 30, end: 200, radius: 7) {
            #expect(abs((point.x * point.x + point.y * point.y).squareRoot() - 7) < 1e-9)
        }
    }

    /// 三角形の頂点の並び（表から見て反時計回り）から求めた向きが、頂点の法線と同じ側を向く。
    /// 逆だと SceneKit の片面描画で表が描かれない。
    private func expectFacesMatchNormals(_ indices: [Int32], in mesh: WheelGeometry.SliceMesh) {
        #expect(!indices.isEmpty && indices.count % 3 == 0)
        for triangle in stride(from: 0, to: indices.count, by: 3) {
            let a = mesh.vertices[Int(indices[triangle])]
            let b = mesh.vertices[Int(indices[triangle + 1])]
            let c = mesh.vertices[Int(indices[triangle + 2])]
            let u = b - a, v = c - a
            let face = SIMD3(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
            let normal = mesh.normals[Int(indices[triangle])] + mesh.normals[Int(indices[triangle + 1])]
                + mesh.normals[Int(indices[triangle + 2])]
            let agreement = face.x * normal.x + face.y * normal.y + face.z * normal.z
            #expect(agreement > 0, "triangle \(triangle / 3)")
        }
    }

    @Test(arguments: [(0.0, 90.0), (45.0, 50.0), (0.0, 360.0), (200.0, 320.0)])
    func スライスの面は法線の側を表に向ける(start: Double, end: Double) {
        let mesh = WheelGeometry.sliceMesh(start: start, end: end, radius: 100, thickness: 14)
        #expect(mesh.vertices.count == mesh.normals.count)
        expectFacesMatchNormals(mesh.top, in: mesh)
        expectFacesMatchNormals(mesh.side, in: mesh)
    }

    @Test(arguments: [(0.0, 90.0), (-2.5, 0.0), (0.0, 360.0), (200.0, 320.0)])
    func 扇形の帯は法線の側を表に向け内径と外径の間に収まる(start: Double, end: Double) {
        let mesh = WheelGeometry.annulusMesh(start: start, end: end, inner: 20, outer: 100)
        #expect(mesh.vertices.count == mesh.normals.count)
        #expect(mesh.side.isEmpty)
        expectFacesMatchNormals(mesh.top, in: mesh)
        for vertex in mesh.vertices {
            let radius = (vertex.x * vertex.x + vertex.y * vertex.y).squareRoot()
            #expect(radius > 20 - 1e-9 && radius < 100 + 1e-9)
            #expect(vertex.z == 0)
        }
    }

    @Test func 扇形の帯の面積は内径と外径の差の扇() {
        let mesh = WheelGeometry.annulusMesh(start: 0, end: 90, inner: 20, outer: 100, segmentsPerTurn: 720)
        var area = 0.0
        for triangle in stride(from: 0, to: mesh.top.count, by: 3) {
            let a = mesh.vertices[Int(mesh.top[triangle])]
            let b = mesh.vertices[Int(mesh.top[triangle + 1])]
            let c = mesh.vertices[Int(mesh.top[triangle + 2])]
            area += ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)) / 2
        }
        let expected = Double.pi * (100 * 100 - 20 * 20) / 4
        #expect(abs(area - expected) / expected < 1e-3)
    }

    @Test func スライスの表面は手前で側面は奥へ伸びる() {
        let mesh = WheelGeometry.sliceMesh(start: 0, end: 90, radius: 100, thickness: 14)
        let topZ = Set(mesh.top.map { mesh.vertices[Int($0)].z })
        let sideZ = Set(mesh.side.map { mesh.vertices[Int($0)].z })
        #expect(topZ == [0])
        #expect(sideZ == [0, -14])
    }

    /// 2D の `rotationEffect`（時計回りが正）と同じ向きに回るよう、z 軸まわり（反時計回りが正）では符号を返す。
    @Test func 回転角はz軸まわりでは符号を返す() {
        #expect(abs(WheelGeometry.spinAngle(rotation: 90) + .pi / 2) < 1e-12)
        #expect(abs(WheelGeometry.spinAngle(rotation: -180) - .pi) < 1e-12)
        #expect(WheelGeometry.spinAngle(rotation: 0) == 0)
    }

    /// 回した盤の 12 時にあった点は、回転角だけ時計回りに進んだところへ動く。
    @Test func 回した盤の点は時計回りに進む() {
        let angle = WheelGeometry.spinAngle(rotation: 90)
        let top = WheelGeometry.point(angle: 0, radius: 10)
        let rotated = SIMD2(top.x * cos(angle) - top.y * sin(angle), top.x * sin(angle) + top.y * cos(angle))
        #expect(isClose(rotated, WheelGeometry.point(angle: 90, radius: 10)))
    }

    @Test func カメラの距離は画角に収まる長さ() {
        let distance = WheelGeometry.cameraDistance(diameter: 200, fieldOfView: 90)
        #expect(abs(distance - 100) < 1e-9)
        #expect(WheelGeometry.cameraDistance(diameter: 200, fieldOfView: 30) > distance)
    }
}
