import Engine
import Presentation
import Testing

@Suite("DurationClamping")
struct DurationClampingTests {
    @Test("All preset values are recognized")
    func presetsRecognized() {
        for preset in DurationClamping.presets {
            #expect(DurationClamping.isPreset(preset))
        }
    }

    @Test("Non-preset values are not recognized")
    func nonPresetsNotRecognized() {
        #expect(!DurationClamping.isPreset(0))
        #expect(!DurationClamping.isPreset(-1))
        #expect(!DurationClamping.isPreset(999))
        #expect(!DurationClamping.isPreset(5000))
    }

    @Test("Clamp keeps in-range values unchanged")
    func clampInRange() {
        #expect(DurationClamping.clamp(300) == 300)
        #expect(DurationClamping.clamp(3600) == 3600)
        #expect(DurationClamping.clamp(21600) == 21600)
        #expect(DurationClamping.clamp(30 * 86400) == 30 * 86400)
    }

    @Test("Clamp raises below-minimum to minimum (300 seconds)")
    func clampBelowMinimum() {
        #expect(DurationClamping.clamp(0) == 300)
        #expect(DurationClamping.clamp(-1) == 300)
        #expect(DurationClamping.clamp(299) == 300)
    }

    @Test("Clamp lowers above-maximum to maximum (30 days)")
    func clampAboveMaximum() {
        let max = 30 * 86400
        #expect(DurationClamping.clamp(max + 1) == max)
        #expect(DurationClamping.clamp(Int.max) == max)
    }

    @Test("Preset list has the expected count and order")
    func presetListStructure() {
        #expect(DurationClamping.presets.count == 9)
        // Sorted ascending
        for idx in 1 ..< DurationClamping.presets.count {
            #expect(DurationClamping.presets[idx] > DurationClamping.presets[idx - 1])
        }
    }
}
