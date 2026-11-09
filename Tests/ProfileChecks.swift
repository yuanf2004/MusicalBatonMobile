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
        // Gaps and pauses remain playable; only stale/duplicate events are rejected.
        func tryAccept(_ gate: inout BeatEventGate, _ seq: UInt16, _ time: UInt32) -> Bool {
            gate.accept(try! packet(seq, time))
        }
        var gate = BeatEventGate()
        precondition(tryAccept(&gate, 1, 100))
        precondition(tryAccept(&gate, 3, 700))
        precondition(tryAccept(&gate, 4, 5000))
        precondition(!tryAccept(&gate, 4, 5000))
        gate = BeatEventGate()
        precondition(tryAccept(&gate, 65535, UInt32.max - 100))
        precondition(tryAccept(&gate, 0, 499))
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
        precondition(sounds.count == 10) // Five pitches/timbres, each plain or accented; accented voice aliases accented click.
        print("Profile persistence/CRUD, validation, continuous playback gaps, wrap, settings and ten sound variants passed")
    }
}
