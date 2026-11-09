#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d /tmp/baton-checks.XXXXXX)
trap 'rm -rf "$out"' EXIT
core=Shared/BatonKit
compile() { xcrun swiftc -module-cache-path "$out/cache" "$@"; }
compile "$core/Utilities/DataFormatting.swift" "$core/Models/BatonMotionPacket.swift" "$core/Models/BatonBeatPacket.swift" "$core/Models/ConductingProfile.swift" "$core/Models/MotionHistory.swift" "$core/Models/MotionGraphSnapshot.swift" "$core/Recording/IMUCSV.swift" Tests/main.swift -o "$out/core"
"$out/core"
compile "$core/Models/BatonMotionPacket.swift" "$core/Recording/IMUCSV.swift" "$core/Recording/IMURecorder.swift" Tests/IMURecorderChecks.swift -o "$out/recorder"
"$out/recorder"
compile "$core/Models/BatonBeatPacket.swift" "$core/Models/ConductingProfile.swift" "$core/Conducting/BeatSound.swift" Tests/ConductingChecks.swift -o "$out/conducting"
"$out/conducting"
compile "$core/Models/BatonBeatPacket.swift" "$core/Models/ConductingProfile.swift" "$core/Conducting/ConductingProfileStore.swift" "$core/Conducting/BeatSound.swift" Tests/ProfileChecks.swift -o "$out/profiles"
"$out/profiles"
compile "$core/Models/BatonMotionPacket.swift" "$core/Conducting/GestureFilter.swift" Tests/GestureChecks.swift -o "$out/gesture"
"$out/gesture" "$PWD"
compile "$core/Models/ConductingProfile.swift" "$core/Conducting/BeatSound.swift" "$core/Conducting/BeatAudioEngine.swift" Tests/AudioBufferChecks.swift -o "$out/audio"
"$out/audio"
