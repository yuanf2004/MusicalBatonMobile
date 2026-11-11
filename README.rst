Musical Baton iOS
================

Two native SwiftUI / CoreBluetooth apps for iOS 17+, in one repository.
Open ``MusicalBaton.xcworkspace`` in Xcode and choose a shared scheme:

* **Baton Debug**: the existing BLE inspector with terminals, GATT tools,
  motion graphs, CSV recording, profiles and conducting diagnostics.
* **Musical Baton**: the new user-facing app. Find your baton, choose a sound
  and movement sensitivity, then start/stop practice with a live beat count.

Layout
------

::

    Apps/BatonDebug/          Existing debug app and Xcode project
    Apps/Baton/               User-facing app and Xcode project
    Shared/BatonKit/          Shared Bluetooth, models, audio and conducting code
    Tests/                    Existing Swift host checks and ML parity fixtures
    Tools/                    Regression runner and gesture model exporter
    Docs/DebugApp.rst         Detailed debug features, protocol and hardware checks
    MusicalBaton.xcworkspace  Opens both app projects

Both projects compile the same ``Shared/BatonKit`` source/resource folder using
Xcode synchronized groups. There is one implementation of BLE/protocol/audio;
this is source sharing, not a separately versioned Swift package. Both targets
retain the same Swift language / main-actor settings. UI lives in each app.
No third-party dependencies, package manager or project generator is required.
Firmware remains in its existing repository.

Run on iPhone
-------------

Select the desired scheme, set your signing team if needed, choose your iPhone,
and Run. The debug app keeps ``yuan.Musical-Baton-Mobile`` and its existing data.
The product app uses ``yuan.Musical-Baton``, so both install side by side.
Each has its own sandbox, saved profiles and recordings; data is not migrated
or automatically shared between apps.

In Musical Baton, triple-press the physical button to advertise, tap **Find my
baton**, then choose the baton. Search is filtered by the advertised baton service
UUID, not a device name. A new triple-press reopens the firmware's 60-second
advertising window. Bluetooth permission/status and connection errors are shown.
Practice waits for beat/settings discovery. Start writes and verifies sensitivity,
subscribes to beats/motion and uses the existing ML + strength filtering/audio
pipeline. Sound preferences save locally and are locked during practice; Bluetooth
limits remain adjustable.
Stopping, disconnecting, backgrounding, audio interruption or output changes stop
playback; returning never silently resumes it. Keep the app open to practice.

The product UI is an initial foundation. It currently uses the existing default
experimental ML filter and strength threshold (50); advanced filter controls,
GATT inspection, recording and audio diagnostics remain in Baton Debug. It has
no metered/downbeat counter or background playback. ML accuracy and end-to-end
latency require hardware validation. Existing model/filter/protocol behavior is
unchanged. See ``Docs/DebugApp.rst`` for full technical behavior and limitations.

Build and check
---------------

From the repository root, with Xcode selected::

    xcodebuild -workspace MusicalBaton.xcworkspace -scheme 'Baton Debug' \
      -configuration Debug -destination 'generic/platform=iOS' \
      -derivedDataPath /tmp/baton-debug-build CODE_SIGNING_ALLOWED=NO build
    xcodebuild -workspace MusicalBaton.xcworkspace -scheme 'Musical Baton' \
      -configuration Debug -destination 'generic/platform=iOS' \
      -derivedDataPath /tmp/baton-product-build CODE_SIGNING_ALLOWED=NO build
    bash Tools/check.sh

The checks cover packet/formatting/history/CSV, recorder lifecycle, conducting,
profile persistence, 1,080 ML parity fixtures, six audio voices, product timer
boundaries, Bluetooth preference persistence and per-device nicknames.
Unsigned builds do not install either app. Verify actual scanning, reconnects,
profile handshake, sound, permission denial, interruptions and background/return
on an iPhone with a baton. No firmware flash is needed for this repository move;
conducting still requires the existing profile-enabled firmware.

Migration
---------

The original ``Musical Baton Mobile`` directory was reorganized under
``Apps/BatonDebug``; its non-UI code moved to ``Shared/BatonKit``. Tests and tools
moved to the root and their model paths were updated. The original debug app
instructions and detailed README are retained. Open the root workspace instead
of the old project path. Local Xcode user settings are ignored by Git.

Migration validation (2026-11-09): both shared schemes passed unsigned iOS device
builds, all six host regression suites passed, and both app bundles included the
shared gesture model. Original debug UI/assets and unchanged core sources were
compared byte-for-byte. No app was installed on an iPhone and live BLE/audio/UI
behavior has not yet been validated on hardware.


Product visual theme
--------------------

Musical Baton uses the requested blue accent (sRGB #0437F2) in both light and
dark mode, with warm ivory backgrounds and soft card surfaces in light mode
and deep blue surfaces in dark mode. Instrument Serif Regular is bundled
for the main headline, card headings and navigation titles, with Dynamic Type
scaling. Body copy, buttons and live beat counts retain native system fonts for
readability. The connection and sound sheets use the same accent and canvas.

The font is bundled locally, with no runtime download or dependency. Source:
https://github.com/google/fonts/tree/main/ofl/instrumentserif
Its SIL Open Font License is retained at
``Apps/Baton/Baton/Fonts/OFL.txt``. Registration lives in
``Apps/Baton/Config/Info.plist``; palette and typography live in
``Apps/Baton/Baton/BatonTheme.swift`` and the product asset catalog.

The debug app and shared BLE/audio logic are unaffected by this visual change.


Opening screen
--------------

Musical Baton launches on a full-screen #0437F2 background with a centered white
single eighth-note symbol. The static iOS launch storyboard matches the animated
SwiftUI opening cover. The cover spins the note once per second for a short
1.4-second presentation interval, then fades into the practice screen over 0.3
seconds. App initialization runs underneath; this branding animation does not
wait for Bluetooth availability, permission, a connection or network access.
It appears once when a new app window is created, not every foreground return.
If interrupted during opening, the short interval restarts on becoming active.
Reduce Motion keeps the note still and removes the fade. The opening cover hides
underlying controls from touch and VoiceOver until the main screen appears.
Instrument Serif and the existing practice, BLE and audio behavior are unchanged.

Opening-screen validation: unsigned iOS device and iPhone simulator builds passed.
Captured startup frames on the iPhone 17 simulator confirmed the full-screen blue,
white note at changing rotation angles and automatic transition into practice.
Actual iPhone startup and the system Reduce Motion setting still need device QA.


Production Home, Settings and Help
---------------------------------

Home has top icon buttons for Sound, Settings and Help. The existing connection
card stays on Home; while connected, a health card directly below it reports the
actual connection and whether a valid six-axis motion packet arrived in the past
three seconds. It also links to device details and shows remaining connection
time when a limit is selected. Motion notifications start after discovery for
health reporting, independently of starting practice. No battery percentage or
sampling-rate estimate is inferred from motion or signal strength.

Settings is a scrollable native form with practice preferences, the connected
baton list and Bluetooth settings at the bottom. Search duration is 10, 30, 60 or
120 seconds (default 30). Connection TTL is no limit (default), 5, 15, 30 or 60
minutes, measured from successful connection. Values persist between launches.
The one-second foreground timer stops scanning or disconnects/stops practice on
expiry; changing a limit applies it to the current elapsed time. Elapsed time is
monotonic. iOS suspension can delay enforcement in the background; the limit is
checked again when returning, before starting practice. This is a phone-side
policy and does not change the firmware's 60-second advertising window.

One baton is supported at a time. With the name-enabled firmware, Settings →
Connected batons → Your baton can change the device's actual Bluetooth name.
Names have a 20-byte UTF-8 limit, persist on the baton, and appear to other phones
on the next advertising session. Save is disabled during practice. The app writes
the new name, then checks status/readback until the firmware confirms persistence;
a write ACK alone is never shown as success. Old firmware shows an upgrade hint.
Legacy local nicknames remain stored for compatibility but no longer override the
real name in production discovery or connected views.

Details distinguish the iOS Bluetooth identifier from a hardware serial number
and MAC address. Standard Device Information fields appear only when actually
exposed by firmware. The current firmware has no such fields; values are never
invented, and discovery can finish while the details screen is open.

Sound preferences offer Click, Wood tap, Bell, Low pitch, High pitch and Accented
click, with a Test sound button usable without a baton. Home can also preview
the selected saved voice. Previews finish automatically, stop on leaving their
page/backgrounding and cannot run during practice. Existing profile JSON and the
three original voices remain compatible. All six voices use the same existing
60 ms envelope; this does not implement first-beat accents or subdivisions.
The additional shared voices also appear in the debug app's profile picker.

Help is a scrollable Q&A with an expandable first-use guide and troubleshooting
for discovery, permissions, silent strokes, audio routes, disconnects, health
indicators and local names. The #0437F2 theme, Instrument Serif headings and
opening animation are retained. See ``Docs/ProductTickets.rst`` for ticket scope.

Per the requested app-only scope, adaptive sensor sampling, battery telemetry,
wireless firmware updates, beat subdivisions and automatic
measure accenting are omitted. They require firmware support or further product
work; there are no switches that claim to enable them.

App-only ticket validation (2026-11-09): both shared schemes passed unsigned iOS
device builds; all seven host suites passed, including the new product preference
suite. Temporary simulator preview entry points rendered Home, Settings, Help and
Sound for layout review and were removed from source afterward. Simulator layouts
retain the requested blue/serif styling. Physical connection/timeout enforcement,
per-device naming and preview/practice audio still require on-device validation.


Device-side naming protocol
---------------------------

The production app already used the shared service UUID, not a Smart Baton name
filter. It now centralizes that identity in ``BatonIdentity``. All batons advertise
``12345678-1234-5678-1234-56789abcdef0``; the firmware places it in the primary
advertisement and its current full name in the scan response. Each CoreBluetooth
peripheral UUID identifies an individual baton. These are discovery identifiers,
not authentication. Duplicate names remain discoverable as separate peripherals.

New Read/Write-with-response characteristic:
``12345678-1234-5678-1234-56789abcdef4``. Write raw UTF-8 (1–20 bytes, no NUL or
control characters). Read version 1, then status 0=saved / 1=saving / 2=failed,
then the committed name. The app polls every 200 ms after the write ACK, for up
to about eight seconds; an absent ACK times out after ten seconds. A saved status
with an exact name match confirms success. Rejection, save failure, disconnection,
GATT service changes and invalid responses never report success. On connection,
the app reads this characteristic to avoid depending on an iOS cached name.

Firmware source/build lives at the supplied ``SmartBatonZach/MusicalBaton``
repository. Flash its name-enabled DK build, install this iOS build, connect,
rename, wait for confirmation, then reconnect/reboot and scan from another phone.
Default advertising name is still Smart Baton until changed. Names survive normal
reboot but an erase/recover clears saved settings. Other phones may cache names
briefly. Existing motion/beat/settings packets and generic debug scanning remain
compatible; the debug inspector can read the new raw status/name characteristic.

Validation: both iOS schemes build unsigned and existing regressions pass. New
identity checks cover UTF-8 byte limits, malformed replies, UUID matching and
saved/saving/failed confirmation rules. Firmware host checks cover deferred save,
restore and failure behavior; the DK builds successfully. No app installation,
flash or physical BLE rename/reboot/two-phone validation was performed.


Conducting recordings
---------------------

The Musical Baton product app can optionally record a practice session without
recording microphone audio or changing the live BLE, gesture-filtering or sound
path. Home keeps one **Start practice** action and adds a **Record this session**
toggle; its default is off and can be changed in Settings. Capture begins only
after practice is ready and observes only beats whose sound was successfully
triggered. Each beat stores elapsed time from session start plus original,
modified, measure-start, accent and optional measure-number metadata.

Active recording drafts are atomically persisted under Application Support after
each accepted beat. A stop, disconnect, interruption or background transition
offers the same name/save or confirmed-discard flow, and a draft left by process
termination is offered again on launch. Saved recordings keep an immutable
original beat/sound copy alongside the editable copy.

The new Recordings page searches by name, plays generated beat audio, selects and
confirms deletion of multiple rows, opens the editor and exports the edited
sequence as a generated mono 44.1 kHz WAV through the iOS share sheet (including
Save to Files). Playback generates a 30 percent higher-pitched form of the chosen
voice for accented and new-measure beats. It never runs through the live baton
capture path.

The touchpad recorder starts with its first new-measure beat and provides regular
and measure-beat controls, stop/save naming and confirmed escape. The editor has
explicit and double-tap rename, sound selection, a vertical time list, beat
selection/deletion, accent and measure-start flags, 10 ms earlier/later shifts,
time-positioned beat insertion, visit-scoped undo/redo and revert of beats and
sound without reverting the recording name.

Recording rows expose both direct confirmed deletion and multi-select confirmed
deletion. In the editor, the header and selected-beat controls remain visible
while the time axis scrolls independently. Accent and new-measure switches show
the selected beat's current state; regular, accented and new-measure beats use
distinct timeline colors. Deleting an individual beat also requires confirmation
and remains undoable before saving. A Recording Guide is available from both the
recordings list and editor and explains capture, playback, export, touchpad,
timeline symbols, editing, undo and revert behavior.

Multi-selection uses square checkboxes. Touchpad recordings accept an optional
positive starting measure number; the first measure beat receives that number,
regular beats inherit the current measure and each later measure beat increments
it. Recordings containing numbered beats expose playback-from-measure choices.
The editor time axis reserves scrollable space after the last beat for later
insertions. Contextual question-mark controls explain recording, sound, movement,
starting measures, accents, new measures, add mode and undo/redo without requiring
users to leave their current workflow.

Recording host checks cover elapsed capture, default flags, immutable originals,
edited persistence, recoverable drafts and WAV structure. Audio timing, pause and
resume behavior, share-sheet destinations, lifecycle interruption handling and
the timeline's iPhone ergonomics still require physical-device validation. No
firmware, UUID, packet or sensitivity behavior is changed.

A standalone interactive Windows-friendly UI prototype is available at
``Mockups/recordings/index.html``. It uses only local HTML, CSS and JavaScript;
double-click the file to review the proposed Home, recordings list, touchpad,
save and timeline-editing flows without Xcode, SwiftUI or an iOS simulator. The
prototype also demonstrates connection and naming, sound/movement preferences,
Settings, Help, the Recording Guide, confirmation dialogs and stateful editing
controls so browser review covers the product app's user-facing workflows.
