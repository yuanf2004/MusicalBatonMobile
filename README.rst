Smart Baton BLE Debug App
========================

Native SwiftUI + CoreBluetooth inspector for iOS 17 or later. No external
Bluetooth dependencies. The app discovers arbitrary BLE peripherals and GATT
UUIDs; no baton name, service, or characteristic is required to connect.

Features
--------

* Start/stop scanning, advertised names, RSSI, and UUID-based duplicate filtering.
* Case-insensitive search by name, device ID, or advertised service UUID. Unnamed
  devices are hidden and only connectable devices shown by default; both filters
  can be changed and persist across launches. Show All Devices clears filters.
  Names and advertised service UUIDs are retained across advertising packets
  which omit these fields. An unnamed device can still be inspected by enabling
  Include unnamed devices; the phone cannot infer an unadvertised device name.
* Connect, cancel pending connections, a 15-second connection timeout,
  disconnect, and reconnect. Going back to Devices disconnects the peripheral.
* All discovered services and characteristics, expandable service sections,
  property labels, supported Read and notification/indication controls.
* Raw HEX and valid UTF-8 values. Notifications are enabled manually per
  characteristic. Raw bytes remain visible with motion parsing on or off.
* Optional Live motion parsing toggle (off initially for each connection) on the
  baton motion characteristic. Enable it to decode the latest value and future
  notifications or reads on the phone. Disabling clears decoded state and stops
  decoded terminal entries. It does not change the notification subscription.
  Decoding is scoped to both the baton service and characteristic UUIDs; other
  devices remain generic GATT inspectors. No gesture recognition is performed.
* HEX or UTF-8 writes with response or without response when supported.
  Oversize writes are rejected; unacknowledged writes are labelled in the log.
* Timestamped terminal for discovery, connection, read, write, notification,
  received bytes, and errors. Clear and Follow controls; the newest 1,000 entries
  are retained. The scanner also provides access to the event log.
* Expand/collapse button in the connected-device terminal header. Expanded mode
  fills the screen and keeps the same BLE connection, notifications, parser, and
  live log. Collapse returns to services without disconnecting. Follow and Clear
  remain available in both sizes.
* Live Graphs button when the baton motion characteristic is discovered. A
  fullscreen native SwiftUI Canvas view shows acceleration XYZ (mg) and gyroscope XYZ
  (degrees/s) as six separate scrolling time-series charts. Notifications and
  parsing can be enabled in that view. Done returns to services while connected.
  Packet sequence, device uptime, received-value count, interval, flags, and
  synchronization status remain visible below the graphs.
* Record IMU button on the connected page: configurable 1–600 second recordings,
  manual stop, a live countdown/row count, persistent CSV files, and Export CSV
  through the iPhone share sheet. IMU Recordings on the scanner exposes saved
  files after disconnection and relaunch. Recording does not require live motion
  parsing and is independent of graph history and display reduction.
* Visible Bluetooth state and error messages. BLE delegate updates run on the
  main queue. Bluetooth permission text is generated into Info.plist.

Conducting profiles and sound
-----------------------------

Tap **Saved Profiles** on the scanner to create, name, edit, select, or delete a
profile before connecting. Profiles persist locally across app relaunches. Each
stores 2, 3, or 4 beats per measure, a detection sensitivity, a beat-1 sound, and
an other-beats sound. Voices are Click, Wood Tap, and Bell; beat 1 has a higher,
stronger accent. A Four-beat practice profile is created on first use. These are
manual settings profiles; no gesture recording/training or automatic meter or
downbeat recognition is implemented. Sensor stillness calibration still happens
in the MCU after boot or a sampling gap.

After connecting, open **Conducting Mode**, use **Choose or Edit Profiles** if
needed, and enable the toggle. Editing/selecting profiles stops an active mode.
The app snapshots the chosen settings for the session, prepares both sounds,
writes sensitivity to the baton, waits for acknowledgement, reads the setting
back, and waits for beat subscription confirmation. Sound events remain disabled
until setup succeeds. Older firmware without settings support shows an update
message; write/read/subscription failures or a ten-second timeout stop setup.
The first new detected beat after Ready is counted as beat 1. **Test Beat 1 Sound**
and **Test Other Beat Sound** preview the voices without advancing the count.
Use **Next beat is 1** to align the next gesture with your downbeat.

Each received MCU beat advances the selected 2/3/4-beat cycle. BPM may be zero;
there is no fixed-tempo metronome or invented missing click. After a gap in beat
sequence numbers or more than two seconds between events, sounds pause and the
screen asks for **Next beat is 1**. This avoids continuing an uncertain accent
pattern. An MCU missed/extra detection can still shift the count without a BLE
sequence gap; use the reset button to realign. The app counts events and cannot
infer actual beat number from motion direction.

Detection remains in the MCU. Flash ``west flash -d build-lsm6dsox-dk`` from the
adjacent MusicalBaton repository, then triple-click to advertise and reconnect.
Raw motion notifications/parsing are independent of Conducting Mode. Profiles
are stored on the phone. Only the selected sensitivity is sent to the MCU; it is
volatile across a firmware reboot and is reapplied on each mode activation.

The sensitivity presets are:

* Balanced (0): arm at 30 deg/s, require 80 mg, trigger below 55% of stroke peak.
* Deliberate (1): arm at 40 deg/s, require 120 mg, trigger below 45% of peak.
* Gentle (2): arm at 22 deg/s, require 55 mg, trigger below 60% of peak.

All retain the stop-speed ceiling, minimum stroke duration, beat separation,
and fresh-motion rearm checks. Gentle can increase false detections; these presets
need hardware validation. A preset change clears stroke/tempo tracking but keeps
sensor calibration. Calibration and filtering are not saved in a profile.

Bluetooth protocol
~~~~~~~~~~~~~~~~~~

The existing service ends in ``...def0``. Raw motion stays on ``...def1`` with its
unchanged 20-byte packet. Notify-only beat characteristic
``12345678-1234-5678-1234-56789abcdef2`` sends exactly 12 bytes, little-endian:

* Byte 0: version 1; byte 1: event type 1 (detected beat).
* Bytes 2-3: unsigned event sequence, wrapping at 65536.
* Bytes 4-7: MCU event uptime in ms, wrapping at 32 bits.
* Bytes 8-9: BPM times 10; zero means an unstable/unavailable estimate.
* Byte 10: motion strength 0-100; byte 11: reserved zero.

The event sequence identifies transport events, not a beat number within a bar.
The app chooses sounds using the selected profile and its local measure counter.
No audio asset ID or audio data needs to travel from the baton.

New read/write characteristic ``12345678-1234-5678-1234-56789abcdef3`` accepts
exactly four bytes: ``[1, 1, sensitivityID, 0]`` (version, set-sensitivity command,
preset ID, reserved). Write with response; read returns the requested setting in
the same format. Invalid version/command/preset/reserved values, wrong length,
nonzero offsets, and prepared writes are rejected. The firmware atomically records
the request and applies it on the sampling thread before detection; the readback
confirms the accepted setting rather than a particular sample's application time.
Writing settings manually in the inspector stops Conducting Mode so the selected
profile can be reapplied explicitly.

Malformed beat data is rejected and logged. Duplicate/backward events are ignored;
sequence and timestamp rollover are supported. Event tracking resets on reconnect
or service rediscovery. No queued sounds are replayed on resume. Without clock
synchronization the app cannot establish an arriving packet's absolute age.

Audio and lifecycle
~~~~~~~~~~~~~~~~~~~

Sound uses the phone's media volume and current route. Use the phone speaker for
initial timing checks. The playback category allows sound in silent mode and mixes
with other audio; no microphone permission is requested. Sounds are generated in
memory and prepared before receiving beats. Leaving Conducting Mode, disconnecting,
app inactivity, service changes, notification failure/loss, audio interruption, or
output-route changes stop playback and require explicit reactivation. A beat
subscription may remain enabled while sound is off, so terminal RX can continue.

Hardware acceptance checks
~~~~~~~~~~~~~~~~~~~~~~~~~~

1. Create a named three-beat profile, select different beat-1/other voices, close
   and relaunch the app, and verify the saved selection. Edit and delete a profile.
2. Install updated firmware/app, connect, and enable Conducting Mode. Confirm
   Ready appears only after settings readback and subscription succeed.
3. Test both sounds. Conduct on the downbeat: hear accent, normal, normal, repeat.
   Try 2 and 4 beats per measure. Test Sound must not advance the measure.
4. Stop for over two seconds, then gesture: mode requests a count reset and plays
   no uncertain accent. Tap Next beat is 1 and resume. Compare gentle/deliberate
   profiles against UART beats and ordinary-motion false triggers.
5. Disconnect, background/lock, or interrupt audio: no automatic sound resume.
   Test old firmware's unavailable state and generic settings writes stopping mode.
6. Verify existing motion graphs, CSV recording, and BLE inspection still work.

Run on an iPhone
----------------

1. Open ``Musical Baton Mobile.xcodeproj`` in Xcode.
2. Select the Musical Baton Mobile target and configure your signing Team under
   Signing & Capabilities. Select a connected iPhone running iOS 17 or later.
3. Build and run, then allow Bluetooth access when prompted.
4. Boot the baton and triple-click its button to start advertising. Firmware
   starts with Bluetooth inactive; advertising expires after 60 seconds without
   a live connection. Triple-click again to open a new window if needed.
5. Tap Scan for Devices, search for the baton name or advertised service UUID,
   and tap Connect. If it has no advertised name, enable Include unnamed devices.
   Search only sees advertised UUIDs before connecting, not all GATT services.
6. Expand its discovered service and enable Notifications on the motion
   characteristic. Expect repeated raw 20-byte values in HEX and the terminal.
   Turn on Live motion parsing to see decoded sensor values and motion log entries.
7. Tap Live Graphs to view six sensor plots; enable Notifications and Live motion
   parsing there if needed. Choose a 10-, 30-, or 60-second window. Done returns
   to the connected device without stopping the stream.
8. Tap Record IMU, enable Motion Notifications and wait for confirmation, choose
   a duration, and tap Start Recording. Stop early or wait for the timer. Once
   saving finishes, tap Export CSV and choose Files, AirDrop, or another app.
   Done leaves recording running so you can use Live Graphs while capturing.
9. Tap Disconnect (or return to Devices), scan again, and reconnect. Previously
   saved CSV files remain available under IMU Recordings on the scanner.

Current firmware reference UUIDs are
``12345678-1234-5678-1234-56789abcdef0`` (service) and
``12345678-1234-5678-1234-56789abcdef1`` (motion characteristic). These are
used to identify optional baton features and label those UUIDs.
The app still discovers services dynamically and can connect to other devices.

Motion packet decoding
----------------------

The decoder matches the encoding in the adjacent firmware project's
``src/bluetooth.c`` and ``src/bluetooth.h``:

* Exactly 20 bytes, version 1 at byte 0. Other lengths or versions show a decode
  message and are logged while parsing is enabled; raw bytes are preserved.
* Flags at byte 1: bit 0 acceleration valid, bit 1 gyroscope valid, bit 2 time
  synchronized. Unknown flag bits are shown. Invalid sensor groups are labelled
  invalid rather than presented as valid measurements.
* Little-endian unsigned sequence (bytes 2-3) and uptime in ms (bytes 4-7).
  Uptime is device time, not the iPhone's clock or a wall-clock timestamp.
* Signed little-endian 16-bit acceleration X/Y/Z (bytes 8-13), shown in mg.
* Signed little-endian 16-bit gyroscope X/Y/Z (bytes 14-19), divided by 10
  and shown in degrees per second with one decimal place.

On hardware, compare the decoded axes to the firmware's serial output, exercise
positive/negative readings, and toggle parsing off/on while notifications remain
on to verify that raw reception continues and decoded values resume immediately.

Live graph timing
-----------------

The X axis uses elapsed device uptime in seconds relative to the newest packet
(0); Y axes use mg or degrees/s. Display refresh is limited to 10 times per second,
independent of the incoming sample rate. Each axis is drawn as lightweight Canvas
paths with at most 256 display points: first/minimum/maximum/last values from 64
time buckets preserve peaks. This display reduction does not discard samples
from the recorded history. No per-sample SwiftUI chart marks or animations are
created. Graphs and packet status use the same throttled snapshot, and unchanged
recordings do not trigger new drawings.

Straight lines connect selected points within the same continuous valid segment;
missing sequences, long gaps, and invalid sensor groups break the trace. All three
axes of each sensor share an automatically sized symmetric Y range. Isolated
selected points are shown as dots. Finer detail than the display resolution remains
available in history within its retention bounds.

Controls observe notification/parsing state separately from high-frequency packet
values. Refresh tasks stop when the graph screen closes or the app is inactive.
The terminal redraws at most five times per second and its drawing pauses behind
the fullscreen graphs, while BLE logging continues. Closing the graphs refreshes
the terminal with retained entries.

History retains at most 60 seconds and 1,000 samples per motion characteristic.
Duplicate reads of the same sequence/uptime count as received values but do not
add duplicate plot points. Clear Graphs resets graph history and its counters;
Clear in the terminal affects only logs. Turning parsing off clears graph
history; notification reception and raw logs can continue independently.

32-bit uptime and 16-bit sequence rollover are handled using wrapping differences.
A backwards device-time jump larger than half the 32-bit range starts a fresh
chart timeline and increments Clock resets. This detects typical reboots or
out-of-order timestamps; the packet has no boot ID to distinguish all possible
clock changes. Reconnection or service rediscovery creates a fresh history.
Malformed packets do not enter history; their decode error appears in the graph
view, and any earlier valid packet is labelled as the last decoded value.

IMU CSV recording
-----------------

Recording captures every successful motion-characteristic value callback received
within the selected duration, including readable values and repeated samples.
It captures the incoming BLE rate, with no graph decimation or 1,000-row limit.
The recording still depends on packets actually delivered by BLE; it cannot
recover missing notifications or samples never sent by firmware. Notifications
must be enabled and confirmed before starting a session.

Rows are queued in callback order to a private FIFO file-writing queue. Packet
decoding, CSV formatting, and incremental file writes happen there instead of
on the UI actor. The recording screen polls its counters at five updates/second.
The timer and Stop prevent new rows, then flush and close all queued writes before
making the file available for sharing. Each session has its own unique filename
under the app's Documents/IMURecordings directory. Saved files persist across
normal app launches; there is no automatic upload or external account dependency.

Recording automatically stops and saves its partial file when the duration ends,
the device disconnects, notifications stop, GATT services change, or the app enters
the background. Keep the app in the foreground for continuous capture. Closing
the recording screen itself does not stop recording. Storage errors are visible;
affected files may be incomplete. An interrupted app process can leave a partial
CSV, so inspect its rows before using it as a complete calibration trial.

CSV uses UTF-8, comma-separated fields, CRLF row endings, escaped quotes, and
locale-independent decimal points. Columns include:

* received_at_utc: phone callback receipt time as ISO 8601 UTC with milliseconds.
* phone_elapsed_ms: monotonic phone time since recording started, in milliseconds.
* device_id/device_name/service_uuid/characteristic_uuid: source metadata.
* packet_length_bytes, packet_version, flags, sequence, and device_uptime_ms.
* acceleration_valid, gyroscope_valid, time_synchronized: 1/0 status fields.
* accel_x_mg/accel_y_mg/accel_z_mg and gyro_x_deg_per_s/gyro_y_deg_per_s/gyro_z_deg_per_s.
* raw_hex and decode_error: original bytes and any packet-format error.

Invalid sensor groups have blank numerical fields while retaining their flags and
raw bytes. Unsupported versions or malformed lengths also remain as rows, with a
decode error and blank unavailable decoded fields. Gyroscope values are converted
from tenths of a degree/second with one decimal place. Device uptime is the raw
32-bit value and can wrap; it is not synchronized to phone UTC. Phone receipt time
includes BLE delivery/OS scheduling delay and is not the sensor acquisition time.

Hardware acceptance checks
--------------------------

Verify scanning, connecting, reading, enabling/disabling notifications, and
live bytes on an actual iPhone and BLE peripheral. Also verify reconnecting,
turning the baton off while connected, Bluetooth permission denial, and turning
phone Bluetooth off/on. Use another peripheral with writable characteristics to
verify writes, both supported response modes, and error presentation.
While connected and receiving notifications, expand the terminal, confirm live
raw/decoded entries continue, then collapse and verify the notification/parsing
switches remain enabled. Open Live Graphs, move each axis, change the window,
verify sequence/uptime/interval updates, and use Done to return while connected.
At the faster firmware rate, fill the 60-second window, scroll through all axes,
and confirm responsive controls and that received counts continue to advance.
Profile on the iPhone with Instruments if responsiveness remains poor; local
source checks cannot establish device frame rate.
Verify invalid readings leave gaps and parsing off clears graphs while raw RX
continues. Unexpected disconnection should still return to Devices.
Record a short timed session and a manually stopped session; export each to Files
or AirDrop and check its CSV rows against received sequences/raw bytes. Record
while parsing is off and while the graphs are open. Disconnect or background the
app during recording and verify the partial file is saved and exportable from
the scanner. Reopen the app and verify earlier files remain listed.
A successful build does not verify radio communication or sensor accuracy.

Local validation
----------------

Unsigned iOS device build, from this directory::

    xcodebuild -project 'Musical Baton Mobile.xcodeproj' \
      -scheme 'Musical Baton Mobile' -destination 'generic/platform=iOS' \
      -derivedDataPath /tmp/musical-baton-build CODE_SIGNING_ALLOWED=NO build

Standalone formatting/input checks::

    xcrun swiftc -module-cache-path /tmp/musical-baton-swift-cache \
      'Musical Baton Mobile/Utilities/DataFormatting.swift' \
      'Musical Baton Mobile/Models/BatonMotionPacket.swift' \
      'Musical Baton Mobile/Models/BatonBeatPacket.swift' \
      'Musical Baton Mobile/Models/ConductingProfile.swift' \
      'Musical Baton Mobile/Models/MotionHistory.swift' \
      'Musical Baton Mobile/Models/MotionGraphSnapshot.swift' \
      'Musical Baton Mobile/Recording/IMUCSV.swift' Tests/main.swift \
      -o /tmp/musical-baton-format-checks
    /tmp/musical-baton-format-checks

Standalone recorder lifecycle checks::

    xcrun swiftc -disable-sandbox -module-cache-path /tmp/musical-baton-swift-cache \
      'Musical Baton Mobile/Models/BatonMotionPacket.swift' \
      'Musical Baton Mobile/Recording/IMUCSV.swift' \
      'Musical Baton Mobile/Recording/IMURecorder.swift' Tests/IMURecorderChecks.swift \
      -o /tmp/musical-baton-recorder-checks
    /tmp/musical-baton-recorder-checks

The development agent's restricted environment required a command-line-only
``OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox'`` override for Swift macro
subprocesses. This is not saved in the project settings. Simulator services
were unavailable in that environment. After adding the app icon, the full build
was blocked by asset-catalog compilation requiring simulator runtimes; all Swift
sources passed direct type checking against the iOS device SDK for the terminal
expansion, graph optimizations, and CSV recording changes. Decoder, history,
display reduction, CSV encoding/writer, and recorder lifecycle checks passed.
A separate CSV reader verified row ordering, multiline metadata escaping, units,
invalid/malformed rows, and complete export of 1,504 callbacks. Runtime performance
and the iPhone share sheet have not been measured/tested on device by the agent.
Physical-device BLE verification remains necessary; no hardware run was performed
by the agent.

Conducting packet and sound checks::

    xcrun swiftc -module-cache-path /tmp/musical-baton-swift-cache \
      'Musical Baton Mobile/Models/BatonBeatPacket.swift' \
      'Musical Baton Mobile/Models/ConductingProfile.swift' \
      'Musical Baton Mobile/Conducting/BeatSound.swift' Tests/ConductingChecks.swift \
      -o /tmp/musical-baton-conducting-checks
    /tmp/musical-baton-conducting-checks

The tests cover packet layout, sliced Data, malformed input, UUID matching,
duplicate/backward events, sequence/time wrap, zero-BPM acceptance, and generated
WAV structure. They do not verify live radio/audio timing or phone lifecycle events.
Audio uses a preprepared AVAudioPlayer; see Apple's prepareToPlay documentation:
https://developer.apple.com/documentation/avfaudio/avaudioplayer/preparetoplay()

Conducting Mode validation (2026-10-26): unsigned iOS device build passed with
Xcode 26.2 after granting access to local build services; all Swift sources also
passed iOS SDK type checking. New conducting packet/sound checks and existing
formatting, motion/history, graph, CSV, and recorder lifecycle checks passed.
The adjacent DK firmware build and detector host tests passed. No iPhone install,
DK flash, or physical BLE/audio latency/lifecycle test was performed by the agent.

Profile regression checks::

    xcrun swiftc -disable-sandbox -module-cache-path /tmp/musical-baton-swift-cache \
      'Musical Baton Mobile/Models/BatonBeatPacket.swift' \
      'Musical Baton Mobile/Models/ConductingProfile.swift' \
      'Musical Baton Mobile/Conducting/ConductingProfileStore.swift' \
      'Musical Baton Mobile/Conducting/BeatSound.swift' Tests/ProfileChecks.swift \
      -o /tmp/musical-baton-profile-checks
    /tmp/musical-baton-profile-checks

Profile implementation validation: unsigned iOS device build and iOS SDK type
checking passed. Profile persistence/CRUD, corrupt-save recovery, validation,
2/3/4 measure count, pauses/gaps/wrap, config encoding, and six generated sound
variants passed host checks. DK build and detector sensitivity/gap checks passed.
Live phone audio, BLE settings handshake, and hardware sensitivity accuracy still
require the manual checks above; the agent did not install or flash either device.
