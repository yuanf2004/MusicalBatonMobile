# Musical Baton iOS monorepo

This repository contains two iOS 17+ SwiftUI apps. Firmware lives separately.

- Apps/BatonDebug preserves the developer BLE inspector, terminals, graphs and recordings.
- Apps/Baton is the user-facing Musical Baton app. Keep its normal flow focused on connecting, choosing a sound/sensitivity and conducting; keep GATT and terminal tools in BatonDebug.
- Shared/BatonKit owns CoreBluetooth, packets, motion processing, conducting, profiles, audio and recording. Both Xcode projects compile this same folder via synchronized source groups. It is not a separate Swift package/module yet.
- Open MusicalBaton.xcworkspace. Shared schemes: Musical Baton and Baton Debug.
- Preserve the debug app bundle identifier and existing saved-data compatibility. The product app uses a separate bundle identifier and sandbox.
- Keep Bluetooth work in BLEManager and main-actor/UI updates on the main actor. Use native CoreBluetooth with no third-party BLE dependency.
- Preserve protocol versions/UUIDs and raw-byte handling. Do not change firmware here.
- Build both schemes after shared changes. Run Tools/check.sh for existing host regressions. Update README.rst with every project change.
- Device scanning, live BLE, sound latency and lifecycle behavior require an actual iPhone/baton; unsigned builds and host checks do not validate hardware.

The original debug-specific instructions remain in Apps/BatonDebug/Musical Baton Mobile/AGENTS.md. Their original first-milestone restrictions describe the debug app, not the product app or the existing conducting features.
