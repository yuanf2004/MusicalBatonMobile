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
* Visible Bluetooth state and error messages. BLE delegate updates run on the
  main queue. Bluetooth permission text is generated into Info.plist.

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
8. Tap Disconnect (or return to Devices), scan again, and reconnect.

Current firmware reference UUIDs are
``12345678-1234-5678-1234-56789abcdef0`` (service) and
``12345678-1234-5678-1234-56789abcdef1`` (motion characteristic). These are
used only to identify the optional motion decoder and label those UUIDs.
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
      'Musical Baton Mobile/Models/MotionHistory.swift' \
      'Musical Baton Mobile/Models/MotionGraphSnapshot.swift' Tests/main.swift \
      -o /tmp/musical-baton-format-checks
    /tmp/musical-baton-format-checks

The development agent's restricted environment required a command-line-only
``OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox'`` override for Swift macro
subprocesses. This is not saved in the project settings. Simulator services
were unavailable in that environment. After adding the app icon, the full build
was blocked by asset-catalog compilation requiring simulator runtimes; all Swift
sources passed direct type checking against the iOS device SDK for the terminal
expansion and live graphs changes, including graph rendering optimizations.
Decoder, history, and display-reduction checks also passed. Runtime performance
has not been measured on an iPhone by the agent. Physical-device BLE verification remains necessary; no hardware
run was performed by the agent.
