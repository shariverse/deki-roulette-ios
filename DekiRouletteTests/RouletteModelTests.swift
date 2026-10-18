import Testing
@testable import DekiRoulette

@MainActor
struct RouletteModelTests {
    private func makeModel(_ labels: [String] = ["A", "B", "C", "D"]) -> RouletteModel {
        RouletteModel(items: ItemLabel.makeItems(labels))
    }

    @Test func 項目は上限まで追加できる() {
        let model = makeModel([])
        for i in 0..<30 { model.addItem("項目\(i)") }
        #expect(model.items.count == Config.maxItems)
        #expect(model.atCapacity)
    }

    @Test func 空のラベルは追加されない() {
        let model = makeModel([])
        model.addItem("   ")
        #expect(model.items.isEmpty)
    }

    @Test func 複数のラベルをまとめて追加できる() {
        let model = makeModel([])
        let added = model.addItems(["A", "  B  C ", "   ", "D"])
        #expect(added == 3)
        #expect(model.items.map(\.label) == ["A", "B C", "D"])
    }

    @Test func まとめて追加しても上限を超えた分は切り捨てる() {
        let model = makeModel(["A", "B"])
        let added = model.addItems((0..<30).map { "項目\($0)" })
        #expect(added == Config.maxItems - 2)
        #expect(model.items.count == Config.maxItems)
        #expect(model.items.last?.label == "項目\(Config.maxItems - 3)")
        #expect(model.addItems(["E"]) == 0)
    }

    @Test func まとめて追加すると結果が消える() {
        let model = makeModel()
        model.rotation = model.beginSpin(reducedMotion: false)!
        model.finishSpin()
        #expect(model.result != nil)
        model.addItems(["E", "F"])
        #expect(model.result == nil)
    }

    @Test func 項目が2つ未満なら回せない() {
        let model = makeModel(["A"])
        #expect(!model.canSpin)
        #expect(model.beginSpin(reducedMotion: false) == nil)
    }

    @Test func 当たり指定はトグルする() {
        let model = makeModel()
        let id = model.items[1].id
        model.toggleTarget(id: id)
        #expect(model.targetId == id)
        #expect(model.marks == [id: .target])
        model.toggleTarget(id: id)
        #expect(model.targetId == nil)
    }

    @Test func 指定した項目を削除すると指定も外れる() {
        let model = makeModel()
        let id = model.items[2].id
        model.toggleTarget(id: id)
        model.removeItem(id: id)
        #expect(model.targetId == nil)
        #expect(model.items.count == 3)
    }

    @Test func 削除すると削除した項目と元の位置が返る() {
        let model = makeModel()
        let item = model.items[1]
        let removed = model.removeItem(id: item.id)
        #expect(removed == RemovedItem(item: item, index: 1))
        #expect(model.items.map(\.label) == ["A", "C", "D"])
        #expect(model.removeItem(id: item.id) == nil)
    }

    @Test func 元に戻すと同じIDで元の位置に入る() {
        let model = makeModel()
        let removed = model.removeItem(id: model.items[1].id)!
        model.restore(removed.item, at: removed.index)
        #expect(model.items.map(\.label) == ["A", "B", "C", "D"])
        #expect(model.items[1].id == removed.item.id)
    }

    @Test func 元に戻しても指定は復元しない() {
        let model = makeModel()
        let id = model.items[2].id
        model.toggleTarget(id: id)
        let removed = model.removeItem(id: id)!
        model.restore(removed.item, at: removed.index)
        #expect(model.targetId == nil)
        #expect(model.marks.isEmpty)
    }

    @Test func 元の位置が範囲外なら末尾に戻す() {
        let model = makeModel()
        let removed = model.removeItem(id: model.items[3].id)!
        model.removeItem(id: model.items[2].id)
        model.restore(removed.item, at: removed.index)
        #expect(model.items.map(\.label) == ["A", "B", "D"])
    }

    @Test func 同じ項目が残っているか上限に達していれば戻さない() {
        let model = makeModel()
        model.restore(model.items[0], at: 0)
        #expect(model.items.count == 4)

        let full = makeModel([])
        for i in 0..<Config.maxItems { full.addItem("項目\(i)") }
        full.restore(Item(label: "E"), at: 0)
        #expect(full.items.count == Config.maxItems)
    }

    @Test func 元に戻すと結果が消える() {
        let model = makeModel()
        let removed = model.removeItem(id: model.items[0].id)!
        model.rotation = model.beginSpin(reducedMotion: false)!
        model.finishSpin()
        #expect(model.result != nil)
        model.restore(removed.item, at: removed.index)
        #expect(model.result == nil)
    }

    @Test func すべて削除すると項目も指定も結果も消える() {
        let model = makeModel()
        model.toggleTarget(id: model.items[1].id)
        model.rotation = model.beginSpin(reducedMotion: false)!
        model.finishSpin()
        model.removeAll()
        #expect(model.items.isEmpty)
        #expect(model.targetId == nil)
        #expect(model.result == nil)
        #expect(!model.canSpin)
    }

    @Test func 指定があれば結果はその項目になる() {
        for _ in 0..<50 {
            let model = makeModel()
            model.toggleTarget(id: model.items[3].id)
            let next = model.beginSpin(reducedMotion: false)
            #expect(next != nil)
            #expect(model.spinning)
            #expect(model.result == nil)
            model.rotation = next!
            model.finishSpin()
            #expect(!model.spinning)
            #expect(model.result == "D")
            #expect(RouletteMath.indexUnderPointer(rotation: model.rotation, count: 4) == 3)
        }
    }

    @Test func 指定がなければ結果は針の下の項目と一致する() {
        for _ in 0..<50 {
            let model = makeModel()
            let next = model.beginSpin(reducedMotion: false)!
            model.rotation = next
            model.finishSpin()
            let index = RouletteMath.indexUnderPointer(rotation: next, count: 4)
            #expect(model.result == model.items[index].label)
        }
    }

    @Test func スピン中は二重に始められない() {
        let model = makeModel()
        #expect(model.beginSpin(reducedMotion: false) != nil)
        #expect(model.beginSpin(reducedMotion: false) == nil)
    }

    @Test func 結果の添字は針の下のスライスと一致する() throws {
        for _ in 0..<50 {
            let model = makeModel()
            let next = model.beginSpin(reducedMotion: false)!
            model.rotation = next
            model.finishSpin()
            let outcome = try #require(model.outcome)
            #expect(outcome.index == RouletteMath.indexUnderPointer(rotation: next, count: 4))
            #expect(outcome.label == model.items[outcome.index].label)
        }
    }

    @Test func 同じラベルが並んでいても結果の添字は指定した項目を指す() {
        let model = makeModel(["A", "A", "A", "A"])
        model.toggleTarget(id: model.items[2].id)
        model.rotation = model.beginSpin(reducedMotion: false)!
        model.finishSpin()
        #expect(model.outcome == SpinOutcome(index: 2, label: "A"))
    }

    @Test func フリックの周回数を渡しても結果は針の下の項目と一致する() throws {
        for spins in Config.fullSpinRange {
            let model = makeModel()
            model.toggleTarget(id: model.items[1].id)
            let before = model.rotation
            let next = try #require(model.beginSpin(reducedMotion: false, fullSpins: spins))
            #expect(next - before >= Double(spins) * 360 + 10)
            #expect(next - before < Double(spins) * 360 + 370)
            model.rotation = next
            model.finishSpin()
            #expect(model.outcome == SpinOutcome(index: 1, label: "B"))
        }
    }

    @Test func 反時計回りのフリックでは累積角が減り結果は変わらない() throws {
        for spins in Config.fullSpinRange {
            let model = makeModel()
            model.toggleTarget(id: model.items[1].id)
            let before = model.rotation
            let next = try #require(model.beginSpin(reducedMotion: false, fullSpins: spins, direction: .counterclockwise))
            #expect(before - next >= Double(spins) * 360 + 10)
            #expect(before - next < Double(spins) * 360 + 370)
            model.rotation = next
            model.finishSpin()
            #expect(model.outcome == SpinOutcome(index: 1, label: "B"))
            #expect(RouletteMath.indexUnderPointer(rotation: model.rotation, count: 4) == 1)
        }
    }

    @Test func 向きを変えても指定がなければ結果は針の下の項目と一致する() throws {
        let model = makeModel()
        for round in 0..<50 {
            let direction: SpinDirection = round.isMultiple(of: 2) ? .counterclockwise : .clockwise
            let next = try #require(model.beginSpin(reducedMotion: false, fullSpins: 4, direction: direction))
            model.rotation = next
            model.finishSpin()
            let outcome = try #require(model.outcome)
            #expect(outcome.index == RouletteMath.indexUnderPointer(rotation: next, count: 4))
        }
    }

    @Test func ボタンは初めは時計回りに回す() throws {
        let model = makeModel()
        #expect(model.lastDirection == .clockwise)
        let next = try #require(model.beginSpin(reducedMotion: false))
        #expect(next > 0)
    }

    @Test func ボタンは直前のフリックの向きを引き継ぐ() throws {
        let model = makeModel()
        model.rotation = try #require(model.beginSpin(reducedMotion: false, fullSpins: 4, direction: .counterclockwise))
        model.finishSpin()
        #expect(model.lastDirection == .counterclockwise)

        var before = model.rotation
        model.rotation = try #require(model.beginSpin(reducedMotion: false))
        #expect(model.rotation < before)
        model.finishSpin()

        model.rotation = try #require(model.beginSpin(reducedMotion: false, fullSpins: 4, direction: .clockwise))
        model.finishSpin()
        before = model.rotation
        model.rotation = try #require(model.beginSpin(reducedMotion: false))
        #expect(model.rotation > before)
    }

    @Test func 始められなかったフリックの向きは引き継がない() {
        let model = makeModel()
        #expect(model.beginSpin(reducedMotion: false) != nil)
        // スピン中のフリックでは始まらないので、向きも覚えない
        #expect(model.beginSpin(reducedMotion: false, fullSpins: 4, direction: .counterclockwise) == nil)
        #expect(model.lastDirection == .clockwise)
    }

    @Test func 勢いの無いまま離しても向きと結果は変わらない() throws {
        // 閾値未満で離したときは、追従した角度を取り込むだけでスピンを始めない（`RouletteScreen.flick`）
        let model = makeModel()
        model.rotation = try #require(model.beginSpin(reducedMotion: false, fullSpins: 4, direction: .counterclockwise))
        model.finishSpin()
        let outcome = model.outcome
        let count = model.spinCount
        let before = model.rotation
        #expect(FlickSpin.spin(angularVelocity: Config.flickMinAngularVelocity - 1) == nil)
        model.rotate(by: 30)
        #expect(model.rotation == before + 30)
        #expect(model.lastDirection == .counterclockwise)
        #expect(model.outcome == outcome)
        #expect(model.spinCount == count)
        #expect(!model.spinning)
    }

    // MARK: 惰性

    @Test func 惰性は抽選せず結果と向きを残す() throws {
        let model = makeModel()
        model.rotation = try #require(model.beginSpin(reducedMotion: false, fullSpins: 4, direction: .counterclockwise))
        model.finishSpin()
        let outcome = model.outcome
        let count = model.spinCount
        let before = model.rotation
        let next = try #require(model.beginCoast(angularVelocity: 120, reducedMotion: false))
        let coast = try #require(FlickCoast.coast(angularVelocity: 120))
        #expect(abs(next - (before + coast.distance)) < 1e-9)
        #expect(model.rotationPath == SpinPath(coast.motion(from: before)))
        #expect(model.rotationPath.segments.first?.easing == FlickCoast.easing)
        #expect(abs(model.rotationPath.duration - coast.duration) < 1e-9)
        #expect(model.outcome == outcome)
        #expect(model.spinCount == count)
        #expect(model.lastDirection == .counterclockwise)
        #expect(!model.spinning)
        #expect(model.rotation == before)
    }

    @Test func 動きを減らす設定と止めてから離したときは惰性を付けない() {
        let model = makeModel()
        #expect(model.beginCoast(angularVelocity: 120, reducedMotion: true) == nil)
        #expect(model.beginCoast(angularVelocity: 0, reducedMotion: false) == nil)
        #expect(model.rotationPath == SpinPath.idle)
    }

    @Test func 演出中は惰性を付けない() {
        let model = makeModel()
        _ = model.beginSpin(reducedMotion: false)
        #expect(model.beginCoast(angularVelocity: 120, reducedMotion: false) == nil)
        #expect(model.rotationPath.duration == Config.spinDuration)
    }

    @Test func 惰性の途中で触れたら今の角度で止める() throws {
        let model = makeModel()
        var clock = 100.0
        model.now = { clock }
        model.rotation = 30
        let next = try #require(model.beginCoast(angularVelocity: -200, reducedMotion: false))
        let coast = try #require(FlickCoast.coast(angularVelocity: -200))
        model.rotation = next
        clock += coast.duration / 2
        let angle = try #require(model.stopCoast())
        #expect(abs(angle - (30 + coast.angle(after: coast.duration / 2))) < 1e-9)
        #expect(angle < 30)
        #expect(angle > next)
        // 一度止めたら、もう止めるものは無い
        #expect(model.stopCoast() == nil)
    }

    @Test func 惰性が止まったあとに触れても角度は変えない() throws {
        let model = makeModel()
        var clock = 0.0
        model.now = { clock }
        let next = try #require(model.beginCoast(angularVelocity: 100, reducedMotion: false))
        model.rotation = next
        clock += try #require(FlickCoast.coast(angularVelocity: 100)).duration
        #expect(model.stopCoast() == nil)
        #expect(model.rotation == next)
    }

    @Test func 惰性の途中でスピンを始めたら惰性を打ち切りスピンの曲線に戻す() throws {
        let model = makeModel()
        var clock = 0.0
        model.now = { clock }
        let next = try #require(model.beginCoast(angularVelocity: 100, reducedMotion: false))
        model.rotation = next
        clock += 0.01
        let target = try #require(model.beginSpin(reducedMotion: false))
        #expect(target > next)
        #expect(model.rotationPath == SpinPath(SpinMotion(
            from: next, to: target, duration: Config.spinDuration, easing: Config.spinEasing
        )))
        #expect(model.stopCoast() == nil)
    }

    @Test func 惰性で回る間も境目で回転音と触覚を鳴らす() async throws {
        let model = makeModel()
        model.rotation = 80
        let coast = try #require(FlickCoast.coast(angularVelocity: 120))
        let next = try #require(model.beginCoast(angularVelocity: 120, reducedMotion: false))
        let clicks = SpinTicks.boundaryCrossings(
            from: 80, to: next, count: 4, duration: coast.duration,
            easing: coast.easing, minInterval: Config.clickMinInterval
        )
        let haptics = HapticSchedule.boundaryCrossings(
            from: 80, to: next, count: 4, duration: coast.duration,
            easing: coast.easing, minInterval: Config.hapticMinInterval
        )
        #expect(!clicks.isEmpty)
        #expect(!haptics.isEmpty)
        #expect(model.clickTimes == clicks)
        #expect(model.clickTimes.last! <= coast.duration)
        try await Task.sleep(for: .seconds(coast.duration + 0.3))
        #expect(model.boundaryTick == haptics.count)
        #expect(model.dragBoundaryTick == 0)
    }

    @Test func 反時計回りの惰性でも境目で鳴らす() throws {
        let model = makeModel()
        model.rotation = 100
        let coast = try #require(FlickCoast.coast(angularVelocity: -120))
        let next = try #require(model.beginCoast(angularVelocity: -120, reducedMotion: false))
        #expect(next < 100)
        let clicks = SpinTicks.boundaryCrossings(
            from: 100, to: next, count: 4, duration: coast.duration,
            easing: coast.easing, minInterval: Config.clickMinInterval
        )
        #expect(!clicks.isEmpty)
        #expect(model.clickTimes == clicks)
    }

    @Test func 惰性の途中で触れたら残りの触覚を刻まない() async throws {
        let model = makeModel()
        model.rotation = 80
        let coast = try #require(FlickCoast.coast(angularVelocity: 200))
        let next = try #require(model.beginCoast(angularVelocity: 200, reducedMotion: false))
        model.rotation = next
        let haptics = HapticSchedule.boundaryCrossings(
            from: 80, to: next, count: 4, duration: coast.duration,
            easing: coast.easing, minInterval: Config.hapticMinInterval
        )
        let first = try #require(haptics.first)
        // 最初の境目より前に止める
        #expect(model.stopCoast() != nil)
        #expect(first > 0)
        try await Task.sleep(for: .seconds(coast.duration + 0.3))
        #expect(model.boundaryTick == 0)
    }

    @Test func 惰性の途中でスピンを始めたら刻みをスピンのものに差し替える() async throws {
        let model = makeModel()
        model.rotation = 80
        let next = try #require(model.beginCoast(angularVelocity: 200, reducedMotion: false))
        model.rotation = next
        let target = try #require(model.beginSpin(reducedMotion: false))
        let expected = HapticSchedule.boundaryCrossings(
            from: next, to: target, count: 4, duration: Config.spinDuration,
            easing: Config.spinEasing, minInterval: Config.hapticMinInterval
        )
        #expect(model.clickTimes == SpinTicks.boundaryCrossings(
            from: next, to: target, count: 4, duration: Config.spinDuration,
            easing: Config.spinEasing, minInterval: Config.clickMinInterval
        ))
        try await Task.sleep(for: .seconds(Config.spinDuration + 0.3))
        #expect(model.boundaryTick == expected.count)
    }

    @Test func 動きを減らす設定では惰性の音と触覚を用意しない() async throws {
        let model = makeModel()
        model.rotation = 80
        #expect(model.beginCoast(angularVelocity: 200, reducedMotion: true) == nil)
        #expect(model.clickTimes.isEmpty)
        try await Task.sleep(for: .seconds(0.8))
        #expect(model.boundaryTick == 0)
    }

    @Test func 反時計回りでもクリック音と触覚の時刻が出る() async throws {
        let model = makeModel()
        let from = model.rotation
        let next = try #require(model.beginSpin(reducedMotion: false, fullSpins: 4, direction: .counterclockwise))
        #expect(!model.clickTimes.isEmpty)
        #expect(model.clickTimes == model.clickTimes.sorted())
        #expect(model.clickTimes.last! <= Config.spinDuration)
        let expected = HapticSchedule.boundaryCrossings(
            from: from, to: next, count: 4, duration: Config.spinDuration,
            easing: Config.spinEasing, minInterval: Config.hapticMinInterval
        )
        #expect(!expected.isEmpty)
        try await Task.sleep(for: .seconds(Config.spinDuration + 0.3))
        #expect(model.boundaryTick == expected.count)
    }

    @Test func 指で回した角度からスピンを始めても結果は変わらない() throws {
        var rng = SeededGenerator(seed: 3)
        let model = makeModel()
        model.toggleTarget(id: model.items[2].id)
        for _ in 0..<100 {
            // 時計回り・反時計回りに大きく回したあとでも、止まる位置は指定したスライス
            let dragged = Double.random(in: -5000...5000, using: &rng)
            let before = model.rotation
            model.rotate(by: dragged)
            #expect(model.rotation == before + dragged)
            let direction: SpinDirection = dragged < 0 ? .counterclockwise : .clockwise
            let from = model.rotation
            let next = try #require(model.beginSpin(reducedMotion: false, fullSpins: 4, direction: direction))
            #expect(abs(next - from) >= 4 * 360 + 10)
            #expect(model.clickTimes == SpinTicks.boundaryCrossings(
                from: from, to: next, count: 4, duration: Config.spinDuration,
                easing: Config.spinEasing, minInterval: Config.clickMinInterval
            ))
            model.rotation = next
            model.finishSpin()
            #expect(model.outcome == SpinOutcome(index: 2, label: "C"))
            #expect(RouletteMath.indexUnderPointer(rotation: model.rotation, count: 4) == 2)
        }
    }

    @Test func フリックの初速は曲線にだけ効き結果は変わらない() throws {
        var rng = SeededGenerator(seed: 5)
        let model = makeModel()
        model.toggleTarget(id: model.items[1].id)
        for _ in 0..<50 {
            let velocity = Double.random(in: -4000...4000, using: &rng)
            let direction: SpinDirection = velocity < 0 ? .counterclockwise : .clockwise
            let from = model.rotation
            let next = try #require(model.beginSpin(
                reducedMotion: false, fullSpins: 5, direction: direction, releaseVelocity: velocity
            ))
            let easing = FlickSpin.easing(angularVelocity: velocity, distance: abs(next - from), duration: Config.spinDuration)
            #expect(model.rotationPath == SpinPath(SpinMotion(
                from: from, to: next, duration: Config.spinDuration, easing: easing
            )))
            // 回転音の時刻も同じ曲線から逆算する（見た目とずれない）
            #expect(model.clickTimes == SpinTicks.boundaryCrossings(
                from: from, to: next, count: 4, duration: Config.spinDuration,
                easing: easing, minInterval: Config.clickMinInterval
            ))
            model.rotation = next
            model.finishSpin()
            #expect(model.outcome == SpinOutcome(index: 1, label: "B"))
            #expect(RouletteMath.indexUnderPointer(rotation: model.rotation, count: 4) == 1)
        }
    }

    @Test func ボタンのスピンは基準の曲線で回す() throws {
        let model = makeModel()
        model.rotation = try #require(model.beginSpin(reducedMotion: false, fullSpins: 4, releaseVelocity: 1500))
        model.finishSpin()
        #expect(model.rotationPath.segments.first?.easing != Config.spinEasing)
        _ = try #require(model.beginSpin(reducedMotion: false))
        #expect(model.rotationPath.segments.first?.easing == Config.spinEasing)
    }

    // MARK: 今の動き（演出が時刻から角度・角速度を引く）

    @Test func スピンを始めると今の動きと開始時刻を持ち終わると捨てる() throws {
        let model = makeModel()
        model.now = { 50 }
        model.rotation = 20
        #expect(model.currentMotion == nil)
        let next = try #require(model.beginSpin(reducedMotion: false, fullSpins: 5, direction: .counterclockwise, releaseVelocity: -1500))
        let current = try #require(model.currentMotion)
        #expect(current.start == 50)
        #expect(current.path == model.rotationPath)
        #expect(current.path.segments.count == 1)
        #expect(current.path.from == 20)
        #expect(current.path.to == next)
        // 初速は離した角速度につながる
        #expect(abs(current.angularVelocity(now: 50) + 1500) < 1e-6)
        model.rotation = next
        model.finishSpin()
        #expect(model.currentMotion == nil)
    }

    @Test func 動きを減らす設定のスピンは今の動きを持たない() throws {
        let model = makeModel()
        _ = try #require(model.beginSpin(reducedMotion: true))
        #expect(model.currentMotion == nil)
    }

    @Test func 惰性の動きを持ち触れたら捨てる() throws {
        let model = makeModel()
        var clock = 10.0
        model.now = { clock }
        model.rotation = 30
        let next = try #require(model.beginCoast(angularVelocity: -200, reducedMotion: false))
        let coast = try #require(FlickCoast.coast(angularVelocity: -200))
        let current = try #require(model.currentMotion)
        #expect(current.start == 10)
        #expect(current.path == SpinPath(coast.motion(from: 30)))
        #expect(abs(current.path.to - next) < 1e-9)
        #expect(abs(current.angularVelocity(now: 10) + 200) < 1e-6)
        model.rotation = next
        clock += coast.duration / 2
        _ = try #require(model.stopCoast())
        #expect(model.currentMotion == nil)
    }

    @Test func 惰性の途中でスピンを始めたら今の動きをスピンのものにする() throws {
        let model = makeModel()
        model.now = { 0 }
        let coastTo = try #require(model.beginCoast(angularVelocity: 100, reducedMotion: false))
        model.rotation = coastTo
        let next = try #require(model.beginSpin(reducedMotion: false))
        let current = try #require(model.currentMotion)
        #expect(current.path == SpinPath(SpinMotion(from: coastTo, to: next, duration: Config.spinDuration, easing: Config.spinEasing)))
    }

    @Test func 指で回したら今の動きを捨てる() throws {
        let model = makeModel()
        let next = try #require(model.beginCoast(angularVelocity: 100, reducedMotion: false))
        model.rotation = next
        #expect(model.currentMotion != nil)
        model.rotate(by: 15)
        #expect(model.currentMotion == nil)
    }

    @Test func 指で動かして境目を越えると強い触覚の刻みが進む() {
        let model = makeModel()
        #expect(model.crossDragBoundary(at: 1))
        #expect(model.dragBoundaryTick == 1)
        // 詰まった境目は間引く
        #expect(!model.crossDragBoundary(at: 1.01))
        #expect(model.dragBoundaryTick == 1)
        #expect(model.crossDragBoundary(at: 1 + Config.hapticMinInterval))
        #expect(model.dragBoundaryTick == 2)
        // スピン中の刻みとは別に数える
        #expect(model.boundaryTick == 0)
    }

    @Test func 演出中は境目の音と触覚を鳴らさない() {
        let model = makeModel()
        _ = model.beginSpin(reducedMotion: false)
        #expect(!model.crossDragBoundary(at: 1))
        #expect(model.dragBoundaryTick == 0)
    }

    @Test func 演出中は指で回せない() {
        let model = makeModel()
        let next = model.beginSpin(reducedMotion: false)!
        model.rotate(by: 45)
        #expect(model.rotation == 0)
        model.rotation = next
        model.finishSpin()
        model.rotate(by: 45)
        #expect(model.rotation == next + 45)
    }

    @Test func 指で回しても結果は消えない() {
        let model = makeModel()
        model.rotation = model.beginSpin(reducedMotion: false)!
        model.finishSpin()
        let outcome = model.outcome
        let count = model.spinCount
        model.rotate(by: -30)
        #expect(model.outcome == outcome)
        #expect(model.spinCount == count)
    }

    @Test func スピンを始めるたびに回数が増える() {
        let model = makeModel()
        #expect(model.spinCount == 0)
        model.rotation = model.beginSpin(reducedMotion: false)!
        model.finishSpin()
        #expect(model.spinCount == 1)
        _ = model.beginSpin(reducedMotion: false)
        // スピン中は始められないので増えない
        _ = model.beginSpin(reducedMotion: false)
        #expect(model.spinCount == 2)
    }

    @Test func 境目を越えるたびに刻まれる() async throws {
        let model = makeModel()
        let from = model.rotation
        let next = try #require(model.beginSpin(reducedMotion: false))
        let expected = HapticSchedule.boundaryCrossings(
            from: from, to: next, count: 4, duration: Config.spinDuration,
            easing: Config.spinEasing, minInterval: Config.hapticMinInterval
        )
        #expect(!expected.isEmpty)
        #expect(model.boundaryTick == 0)
        try await Task.sleep(for: .seconds(Config.spinDuration + 0.3))
        #expect(model.boundaryTick == expected.count)
    }

    @Test func 動きを減らす設定では境目を刻まない() async throws {
        let model = makeModel()
        #expect(model.beginSpin(reducedMotion: true) != nil)
        try await Task.sleep(for: .seconds(Config.reducedMotionSpinDuration + 0.3))
        #expect(model.boundaryTick == 0)
        #expect(model.result != nil)
    }

    @Test func スピンが終わると刻みも止まる() async throws {
        let model = makeModel()
        model.rotation = model.beginSpin(reducedMotion: false)!
        model.finishSpin()
        try await Task.sleep(for: .seconds(0.5))
        #expect(model.boundaryTick == 0)
    }

    @Test func クリック音の時刻はスピンの間に収まる() {
        let model = makeModel()
        let next = model.beginSpin(reducedMotion: false)!
        #expect(!model.clickTimes.isEmpty)
        #expect(model.clickTimes == model.clickTimes.sorted())
        #expect(model.clickTimes.first! > 0)
        #expect(model.clickTimes.last! <= Config.spinDuration)
        // 4 項目なので境目は 90 度ごと。間引きがある分だけ必ず少なくなる
        #expect(model.clickTimes.count <= Int(next / 90))
    }

    @Test func 動きを減らす設定では鳴らさない() {
        let model = makeModel()
        model.rotation = model.beginSpin(reducedMotion: true)!
        #expect(model.clickTimes.isEmpty)
    }

    @Test func 項目を触ると結果が消える() {
        let model = makeModel()
        model.rotation = model.beginSpin(reducedMotion: false)!
        model.finishSpin()
        #expect(model.result != nil)
        model.addItem("E")
        #expect(model.result == nil)
    }


    // MARK: 永続化

    private func makeStore(_ storage: InMemoryStorage) -> ItemStore {
        ItemStore(key: .roulette, storage: storage, defaultLabels: { ["A", "B", "C", "D"] })
    }

    @Test func まとめて追加したときも保存する() {
        let storage = InMemoryStorage()
        let store = makeStore(storage)
        let model = RouletteModel(store: store)
        model.addItems(["E", "F"])
        #expect(store.loadSaved()?.map(\.label) == ["A", "B", "C", "D", "E", "F"])
    }

    @Test func 追加と削除のたびに保存する() {
        let storage = InMemoryStorage()
        let store = makeStore(storage)
        let model = RouletteModel(store: store)
        #expect(store.loadSaved() == nil)
        model.addItem("E")
        #expect(store.loadSaved()?.map(\.label) == ["A", "B", "C", "D", "E"])
        model.removeItem(id: model.items[0].id)
        #expect(store.loadSaved()?.map(\.label) == ["B", "C", "D", "E"])
    }

    @Test func 保存した項目から始まるが指定は残らない() {
        let storage = InMemoryStorage()
        let first = RouletteModel(store: makeStore(storage))
        first.addItem("E")
        first.toggleTarget(id: first.items[4].id)

        let second = RouletteModel(store: makeStore(storage))
        #expect(second.items == first.items)
        #expect(second.targetId == nil)
    }

    @Test func 初期状態に戻すと指定と結果も消え保存データも消える() {
        let storage = InMemoryStorage()
        let store = makeStore(storage)
        let model = RouletteModel(store: store)
        model.addItem("E")
        model.toggleTarget(id: model.items[0].id)
        model.rotation = model.beginSpin(reducedMotion: false)!
        model.finishSpin()

        model.resetItems()
        #expect(model.items.map(\.label) == ["A", "B", "C", "D"])
        #expect(model.targetId == nil)
        #expect(model.result == nil)
        #expect(store.loadSaved() == nil)
    }

    @Test func 保存先が無いときは初期状態に戻しても何もしない() {
        let model = makeModel(["A", "B"])
        model.resetItems()
        #expect(model.items.map(\.label) == ["A", "B"])
    }

    // MARK: 止まり際の焦らし

    @Test func 演出なしのスピンは今の曲線と長さと音と触覚の時刻のまま() throws {
        for (seed, release) in [(UInt64(1), nil), (2, 1500), (3, -900)] as [(UInt64, Double?)] {
            // 「なし」を渡したときと、省いたとき（既定）
            for passesStyle in [true, false] {
                let model = makeModel()
                model.randomSource = AnyRandomNumberGenerator(SeededGenerator(seed: seed))
                model.rotation = 40
                let direction: SpinDirection? = release.map { $0 < 0 ? .counterclockwise : .clockwise }
                let started = if passesStyle {
                    model.beginSpin(
                        reducedMotion: false, style: SpinEffectStyle.none, fullSpins: 5, direction: direction, releaseVelocity: release
                    )
                } else {
                    model.beginSpin(reducedMotion: false, fullSpins: 5, direction: direction, releaseVelocity: release)
                }
                let next = try #require(started)
                let easing = if let release {
                    FlickSpin.easing(angularVelocity: release, distance: abs(next - 40), duration: Config.spinDuration)
                } else {
                    Config.spinEasing
                }
                #expect(model.rotationPath == SpinPath(SpinMotion(from: 40, to: next, duration: Config.spinDuration, easing: easing)))
                #expect(model.rotationPath.tease == nil)
                #expect(model.rotationPath.duration == Config.spinDuration)
                #expect(abs(model.rotationPath.fallback - Config.spinFallback) < 1e-9)
                #expect(model.clickTimes == SpinTicks.boundaryCrossings(
                    from: 40, to: next, count: 4, duration: Config.spinDuration,
                    easing: easing, minInterval: Config.clickMinInterval
                ))
                #expect(HapticSchedule.boundaryCrossings(along: model.rotationPath, count: 4, minInterval: Config.hapticMinInterval)
                    == HapticSchedule.boundaryCrossings(
                        from: 40, to: next, count: 4, duration: Config.spinDuration,
                        easing: easing, minInterval: Config.hapticMinInterval
                    ))
                #expect(model.currentMotion?.path == model.rotationPath)
                // 盤面の補間も今の `timingCurve` のまま
                #expect(Theme.spinAnimation(path: model.rotationPath) == Theme.spinAnimation(easing: easing))
            }
        }
    }

    @Test(arguments: [SpinEffectStyle.lights, .trails, .confetti, .all])
    func 演出ありのスピンは焦らしを入れても止まる位置と結果は変わらない(style: SpinEffectStyle) throws {
        let model = makeModel()
        model.randomSource = AnyRandomNumberGenerator(SeededGenerator(seed: 11))
        model.toggleTarget(id: model.items[2].id)
        for round in 0..<30 {
            let from = model.rotation
            let direction: SpinDirection = round.isMultiple(of: 2) ? .clockwise : .counterclockwise
            let next = try #require(model.beginSpin(reducedMotion: false, style: style, direction: direction))
            let path = model.rotationPath
            #expect(path.tease != nil)
            #expect(path.from == from)
            #expect(path.to == next)
            #expect(abs(path.duration - (Config.spinDuration + Config.spinTeaseDuration)) < 1e-9)
            #expect(abs(path.fallback - Config.spinTeaseFallback) < 1e-9)
            #expect(abs(next - from) >= Double(Config.fullSpinRange.lowerBound) * 360 + 10)
            // 回転音と触覚の時刻は往復とも数えた境目から
            #expect(model.clickTimes == path.boundaryCrossings(count: 4, minInterval: Config.clickMinInterval))
            #expect(model.clickTimes.last! <= path.duration)
            #expect(model.currentMotion?.path == path)
            #expect(Theme.spinAnimation(path: path) != Theme.spinAnimation(easing: Config.spinEasing))
            model.rotation = next
            model.finishSpin()
            #expect(model.outcome == SpinOutcome(index: 2, label: "C"))
            #expect(RouletteMath.indexUnderPointer(rotation: model.rotation, count: 4) == 2)
        }
    }

    @Test(arguments: [SpinEffectStyle.lights, .trails, .confetti, .all])
    func 焦らしの動きは指定の有無で変わらない(style: SpinEffectStyle) throws {
        for seed in UInt64(1)...20 {
            for release: Double? in [nil, 1800, -2400] {
                let direction: SpinDirection? = release.map { $0 < 0 ? .counterclockwise : .clockwise }
                let fullSpins = release.map { _ in 6 }
                // 指定なし: 乱数で止まる項目が決まる
                let free = makeModel(["A", "B", "C", "D", "E"])
                free.randomSource = AnyRandomNumberGenerator(SeededGenerator(seed: seed))
                free.rotation = 25
                let freeNext = try #require(free.beginSpin(
                    reducedMotion: false, style: style, fullSpins: fullSpins, direction: direction, releaseVelocity: release
                ))
                free.rotation = freeNext
                free.finishSpin()
                let index = try #require(free.outcome?.index)

                // 指定あり: 同じ項目を指定し、同じ乱数の列で回す
                let aimed = makeModel(["A", "B", "C", "D", "E"])
                aimed.randomSource = AnyRandomNumberGenerator(SeededGenerator(seed: seed))
                aimed.rotation = 25
                aimed.toggleTarget(id: aimed.items[index].id)
                let aimedNext = try #require(aimed.beginSpin(
                    reducedMotion: false, style: style, fullSpins: fullSpins, direction: direction, releaseVelocity: release
                ))
                #expect(aimedNext == freeNext)
                #expect(aimed.rotationPath == free.rotationPath)
                #expect(aimed.rotationPath.tease == free.rotationPath.tease)
                #expect(aimed.clickTimes == free.clickTimes)
                #expect(HapticSchedule.boundaryCrossings(along: aimed.rotationPath, count: 5, minInterval: Config.hapticMinInterval)
                    == HapticSchedule.boundaryCrossings(along: free.rotationPath, count: 5, minInterval: Config.hapticMinInterval))
            }
        }
    }

    @Test func フリックの焦らしは主の区間の初速を離した角速度に合わせる() throws {
        for release in [1500.0, -1500] {
            let model = makeModel()
            model.randomSource = AnyRandomNumberGenerator(SeededGenerator(seed: 4))
            model.now = { 30 }
            let direction: SpinDirection = release < 0 ? .counterclockwise : .clockwise
            let next = try #require(model.beginSpin(
                reducedMotion: false, style: .all, fullSpins: 5, direction: direction, releaseVelocity: release
            ))
            let path = model.rotationPath
            let tease = try #require(path.tease)
            #expect(path == SpinPath.teased(tease, from: 0, to: next, count: 4, releaseVelocity: release))
            let current = try #require(model.currentMotion)
            #expect(abs(current.angularVelocity(now: 30) - release) < 1e-6)
        }
    }

    @Test func 動きを減らす設定では焦らしを入れない() throws {
        let model = makeModel()
        let next = try #require(model.beginSpin(reducedMotion: true, style: .all))
        #expect(model.rotationPath.tease == nil)
        #expect(model.rotationPath.segments.count == 1)
        #expect(model.rotationPath.to == next)
        #expect(model.currentMotion == nil)
        #expect(model.clickTimes.isEmpty)
    }

    @Test func 演出なしの保険は今の長さで止める() async throws {
        let model = makeModel()
        _ = try #require(model.beginSpin(reducedMotion: false, style: .none))
        try await Task.sleep(for: .seconds(Config.spinFallback + 0.4))
        #expect(!model.spinning)
        #expect(model.result != nil)
    }

    @Test func 焦らしのスピンは焦らしを含めた長さまで止めず境目ごとに刻む() async throws {
        let model = makeModel()
        model.randomSource = AnyRandomNumberGenerator(SeededGenerator(seed: 9))
        _ = try #require(model.beginSpin(reducedMotion: false, style: .lights))
        let expected = HapticSchedule.boundaryCrossings(along: model.rotationPath, count: 4, minInterval: Config.hapticMinInterval)
        #expect(!expected.isEmpty)
        // 焦らし無しの保険の時刻を過ぎてもまだ止めない
        try await Task.sleep(for: .seconds(Config.spinFallback + 0.2))
        #expect(model.spinning)
        #expect(model.result == nil)
        try await Task.sleep(for: .seconds(Config.spinTeaseFallback - Config.spinFallback + 0.4))
        #expect(!model.spinning)
        #expect(model.result != nil)
        #expect(model.boundaryTick == expected.count)
    }
}
