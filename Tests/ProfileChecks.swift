import Foundation

@main
struct ProfileChecks {
    @MainActor static func main() throws {
        let suite = "BatonProfileTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ConductingProfileStore(defaults: defaults)
        precondition(store.profiles.count == 1 && store.selected != nil)
        var profile = ConductingProfile(name: "My small strokes", beatsPerMeasure: 3,
            sensitivity: .gentle, downbeatSound: .wood, otherBeatSound: .bell)
        precondition(store.save(profile))
        var reload = ConductingProfileStore(defaults: defaults)
        precondition(reload.selected == profile)
        profile.name = "Renamed"
        precondition(reload.save(profile) && reload.profiles.count == 2)
        reload = ConductingProfileStore(defaults: defaults)
        precondition(reload.selected?.name == "Renamed")
        var bad = profile; bad.name = "  "
        precondition(!reload.save(bad))
        bad = profile; bad.beatsPerMeasure = 5
        precondition(!reload.save(bad))
        reload.delete(profile.id)
        precondition(reload.profiles.count == 1 && reload.selected?.id != profile.id)
        let retained = reload.selected!.id
        reload.delete(retained)
        precondition(reload.profiles.isEmpty && reload.selected == nil)
        precondition(ConductingProfileStore(defaults: defaults).profiles.isEmpty)
        defaults.set(Data([0xFF]), forKey: "conducting.profiles.v1")
        let corrupted = ConductingProfileStore(defaults: defaults)
        precondition(corrupted.error != nil && corrupted.selected == nil)
        precondition(defaults.data(forKey: "conducting.profiles.v1") == Data([0xFF]))
        precondition(corrupted.save(profile))
        precondition(ConductingProfileStore(defaults: defaults).selected == profile)

        func packet(_ seq: UInt16, _ time: UInt32) throws -> BatonBeatPacket {
            try BatonBeatPacket(data: Data([1, 1, UInt8(truncatingIfNeeded: seq), UInt8(seq >> 8),
                UInt8(truncatingIfNeeded: time), UInt8(truncatingIfNeeded: time >> 8),
                UInt8(truncatingIfNeeded: time >> 16), UInt8(truncatingIfNeeded: time >> 24), 0, 0, 80, 0]))
        }
        for meter in 2...4 {
            var counter = MeasureCounter()
            for i in 0..<12 {
                let p = try packet(UInt16(i), UInt32(i*600))
                precondition(counter.advance(p, beatsPerMeasure: meter) == i%meter+1)
            }
            let missing = try packet(13, 7800)
            precondition(counter.advance(missing, beatsPerMeasure: meter) == nil)
            counter.reset()
            precondition(counter.advance(missing, beatsPerMeasure: meter) == 1)
            let pause = try packet(14, 11000)
            precondition(counter.advance(pause, beatsPerMeasure: meter) == nil)
            counter.reset()
            precondition(counter.advance(pause, beatsPerMeasure: meter) == 1)
        }
        var wrap = MeasureCounter()
        let before = try packet(65535, UInt32.max - 100)
        let after = try packet(0, 499)
        precondition(wrap.advance(before, beatsPerMeasure: 4) == 1)
        precondition(wrap.advance(after, beatsPerMeasure: 4) == 2)
        for sensitivity in DetectionSensitivity.allCases {
            precondition(ConductingSettingsPacket.encode(sensitivity) == Data([1,1,UInt8(sensitivity.rawValue),0]))
        }
        var sounds = Set<Data>()
        for voice in ClickVoice.allCases {
            for accented in [false, true] {
                let wav = BeatSound.wavData(voice: voice, accented: accented)
                precondition(wav.count == 44+2646*2 && wav.suffix(2) == Data([0,0]))
                sounds.insert(wav)
            }
        }
        precondition(sounds.count == 6)
        print("Profile persistence/CRUD, validation, 2/3/4 measure count, gaps, wrap, settings and six sounds passed")
    }
}
