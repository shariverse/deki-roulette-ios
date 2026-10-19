import AVFAudio
import Foundation
import Testing
@testable import DekiRoulette

@MainActor
struct StopChimeTests {
    @Test func なしでは鳴らさない() {
        #expect(!StopChime.plays(style: .none, soundEnabled: true, stop: .spin))
        #expect(!StopChime.plays(style: .none, soundEnabled: false, stop: .spin))
    }

    @Test func 演出があって効果音がONならスピンの停止で鳴らす() {
        for style in SpinEffectStyle.allCases where style != .none {
            #expect(StopChime.plays(style: style, soundEnabled: true, stop: .spin))
        }
    }

    @Test func 効果音がOFFなら鳴らさない() {
        for style in SpinEffectStyle.allCases {
            #expect(!StopChime.plays(style: style, soundEnabled: false, stop: .spin))
        }
    }

    @Test func 惰性では鳴らさない() {
        for style in SpinEffectStyle.allCases {
            #expect(!StopChime.plays(style: style, soundEnabled: true, stop: .coast))
        }
    }

    /// 鳴らすきっかけ（結果が出たこと）も判定も、指定の有無で変わらない。
    @Test func 指定があってもなくても同じように鳴らす() {
        let free = RouletteModel(items: ItemLabel.makeItems(["A", "B", "C", "D"]))
        let aimed = RouletteModel(items: ItemLabel.makeItems(["A", "B", "C", "D"]))
        aimed.toggleTarget(id: aimed.items[2].id)

        for model in [free, aimed] {
            #expect(model.beginSpin(reducedMotion: true) != nil)
            model.finishSpin()
            #expect(model.outcome != nil)
        }
        for style in SpinEffectStyle.allCases {
            for soundEnabled in [true, false] {
                let plays = StopChime.plays(style: style, soundEnabled: soundEnabled, stop: .spin)
                #expect(plays == (style.showsCommonEffects && soundEnabled))
            }
        }
    }

    /// 惰性は抽選しないので結果が出ず、決まり音のきっかけにならない。
    @Test func 惰性では結果が出ない() {
        let model = RouletteModel(items: ItemLabel.makeItems(["A", "B", "C", "D"]))
        #expect(model.beginCoast(angularVelocity: 120, reducedMotion: false) != nil)
        #expect(model.outcome == nil)
        model.stopCoast()
        #expect(model.outcome == nil)
    }

    /// 音源は click.wav と同じ形式で、1 秒未満・クリップしない（`scripts/make-chime-sound.swift` の出力）。
    @Test func 音源は短くクリップしない() throws {
        let chimeURL = try #require(Bundle.main.url(forResource: "chime", withExtension: "wav"))
        let clickURL = try #require(Bundle.main.url(forResource: "click", withExtension: "wav"))
        let chime = try AVAudioFile(forReading: chimeURL)
        let click = try AVAudioFile(forReading: clickURL)

        #expect(chime.fileFormat.sampleRate == click.fileFormat.sampleRate)
        #expect(chime.fileFormat.channelCount == 1)
        #expect(chime.fileFormat.commonFormat == click.fileFormat.commonFormat)
        #expect(Double(chime.length) / chime.fileFormat.sampleRate < 1)

        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: chime.processingFormat, frameCapacity: AVAudioFrameCount(chime.length)
        ))
        try chime.read(into: buffer)
        let channel = try #require(buffer.floatChannelData?.pointee)
        let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        let peak = samples.map(abs).max() ?? 0
        #expect(peak > 0.1)
        #expect(peak < 1)
        // 頭と尻は 0 付近から始まり 0 付近で終わる（プチッというノイズを出さない）
        #expect(abs(samples.first ?? 1) < 0.01)
        #expect(abs(samples.last ?? 1) < 0.01)
    }
}
