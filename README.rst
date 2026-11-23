Musical Baton iOS
================

Two native SwiftUI / CoreBluetooth apps for iOS 17+, in one repository.

New to Mac/iPhone development? Follow the
`first-time Xcode and iPhone setup guide <Docs/FirstTimeSetup.rst>`_ for signing,
Developer Mode, trust prompts, installation, Bluetooth and troubleshooting.

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

Custom product-app card and icon buttons, including recording controls and
rhythm pads, darken slightly while held and restore their appearance on release. Standard iOS buttons retain their native
press feedback. Disabled cards do not show pressed feedback.
The touchpad's New Measure Beat and New Beat buttons use a darker blue background
while pressed and for 150 ms after release so quick rhythm taps remain visible,
keeping their white labels bright. Beats still trigger immediately on touch-down,
once per press; the visual reset never delays audio.

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

The Touchpad Recording page uses title capitalization. Saved recordings in the
editor support audible Play/Pause and Restart using the selected sound and beat
accents. Playback stops when editing, leaving the editor, or backgrounding the app.

The recording editor shows a red playback cursor using the audio playback clock.
Hold a beat to drag it vertically, or select it and set its exact time in seconds
(0–86400). Moving a beat is undoable; dragging pauses playback.

The playback cursor refreshes at the display-driven animation cadence. Beat
dragging uses a fixed timeline coordinate space to avoid movement feedback and
follows the finger directly; the moving dot turns red with no selection ring.

Product option labels use Title Case, including sound choices and recording
controls. The Set Time field displays beat times rounded to three decimal places.

Selected beats appear red without a highlight ring. Tap empty timeline space or
Done Editing to deselect; tap another dot to switch selection. Beat controls keep
the selection active. Timeline hit targets stay fixed regardless of duration.

Beat gestures distinguish a quick tap (select and show editing controls) from a
long press followed by dragging (move). The full dot target responds to taps,
and VoiceOver activation opens the beat editor.

Quick beat taps are recognized independently of the hold-and-drag gesture, so
selection does not depend on the long-press recognizer failing first.

Measure-start dots are blue with a small white center dot for the first beat
of the measure;
selected or dragged dots remain red. Selected beat details show the stored
measure number, or Not Numbered when none was recorded.

Drag the red playback line to the right of the dots to seek. Its black time label
shows three decimals above the right end. Seeking pauses audio during the drag
and resumes on release if it was playing; edits preserve the playback position.

A pencil beside the recording name opens inline renaming, with an accessible
Rename Recording label and a full-size touch target.

Choosing a sound in Touchpad Recording, Edit Recording, or Your Sound plays a
short preview. Editor playback pauses for sound changes; previews stop before
recording playback and when leaving the screen or backgrounding the app.

The playback cursor is drawn as one continuous full-width line across the time
axis and dots, with its drag target kept on the right.

Recording saves commit atomically before updating the library or clearing recovery
data; failures remain visible and can be retried. WAV files stream in 4096-frame
chunks with RIFF size validation instead of allocating the full audio in memory.
Touchpad beat buttons preview the chosen sound, accented for new measures.

Touchpad audio is prepared on entry and sound changes, reusing normal/accented
buffers per tap with a short preferred audio buffer. It stops on exit/background
and recovers after interruptions or output changes. Stop Without Saving offers
a confirmed discard. Actual latency depends on the iPhone and output route.

Touchpad rhythm pads fire once on touch-down, including normal accessibility
activation. Recording playback only releases audio sessions it owns, preventing
list dismissal from disabling touchpad audio on entry. A stopped touchpad engine
automatically re-prepares the selected sound on the next tap.

Touchpad sound selection locks after the first beat starts the recording, keeping
its audio and saved sound consistent. Choose and preview sounds before starting.

Touchpad live counters
----------------------

The touchpad displays the current measure and beat, plus total recorded beats.
Counter numbers use the primary text color: black in light mode and white in
dark mode.
New Measure Beat starts measure 1 (or the optional starting measure) at beat 1.
New Beat advances the beat within that measure; the next New Measure Beat
advances the measure and resets its beat to 1. Counters show dashes before the
first beat and only advance when a beat is successfully played and recorded.
New touchpad recordings default to numbered measures starting at 1.

Synchronized practice power control
-----------------------------------
Practice supports legacy firmware without def5 using the original notification
and sensitivity handshake; low-power switching and button control require def5. The app confirms the
baton's actual active sensor state before marking practice ready or capturing
beats, polls once per second, and renews an active lease. Stop, backgrounding,
control errors and disconnect stop local practice; firmware independently idles
after five seconds without renewal. Reconnect never resumes practice.
A half-second (500 ms) baton hold toggles practice in the foreground and respects Record
this session. Starts are blocked while the recording-save sheet is open.
Firmware uses 12.5 Hz IMU idle ODR and the existing 416 Hz practice ODR; idle
sends no motion telemetry; the product health card displays Low-power idle.
Hold requests received after a stale connection are discarded to prevent replay
when returning from suspension.
Both apps retain legacy practice support. Raw debug BLE tools
remain available. Hardware testing must verify power draw, sensor settling,
hold timing, acknowledgment races and disconnect/background behavior.

Power-status version 2 adds an explicit calibrating state. The app displays
Hold still to calibrate and waits for confirmed calibration before counting or
playing beats. Moving during calibration no longer triggers the ten-second
setup timeout; connection timeout and the firmware lease remain active.
Version 1 power-status firmware is still accepted with its original behavior.

Help now includes a Calibration & Practice section covering the one-second
stillness check, calibration status, recovery when calibration does not finish,
button-hold start/stop, recording preferences and automatic low-power idle.
Setup, sound troubleshooting and firmware guidance distinguish legacy support
from the features that need updated firmware.

The Home practice card shows a pause icon while asking the user to hold still
for calibration, then a waveform when ready to conduct.

New baton and touchpad recording save screens begin with an empty, focused name
field and the native gray Name Your Recording placeholder. Save stays disabled
until a nonblank name of at most 80 characters is entered. Existing saved
recording names remain unchanged.

Editor measure and beat positions
--------------------------------
Selected dots show their measure and beat within that measure. Positions are
recalculated after moves (on drag release), insertions, deletions and measure
marker changes. The first beat begins the starting measure, defaulting to 1;
each later New Measure marker increments the measure and resets the beat to 1.
Custom starting measures are preserved. Legacy files are numbered on load;
original beats remain untouched for Revert. Undo/redo retain numbered snapshots.
Ordinary edits maintain sorted order by linear insertion and recalculate in
O(N). Loading or reverting an unsorted legacy timeline may require O(N log N)
sorting first. Equal-time beats retain their order; moved/inserted beats go
after existing beats at that time. Optional metadata preserves old-file decoding.

The recording editor stacks Accent and New Measure in separate rows, each
with its own help button.

Saved-recording row action icons use the primary text color, including the
play-from-measure menu: black in light mode and white in dark mode.

The measure-playback menu explicitly overrides the blue app tint with the
primary text color, and row icons use Color.primary rather than an inherited
hierarchical foreground style.

Beat detection report
---------------------

Edit Recording has an Export Report action (chart icon, top left). It is only
enabled once the beats differ from what was captured. The report treats the
edited beats as correct and compares them with the original detected beats.
All times are relative to the start of the recording.

Matching uses ``BeatDetectionReport.matchWindowMicroseconds`` (125 ms: half the
250 ms debounce, and under half a beat at 184 bpm). Pairs are taken closest
first, so each detected and edited beat is used at most once. Every beat then gets
one label. A matched beat has a partner. A missed beat is an edited beat with no
detected partner. A duplicate is an unpaired detected beat that lands near an edited
beat that already has a partner. A false trigger is a detected beat with no
edited beat nearby.

The report shows beat accuracy (matched ÷ all labels), missed, duplicate and
false-trigger rates, and net count difference. It also shows the average timing
offset (detected minus edited, so a positive value means late), timing
consistency (standard deviation), and the share of beats within 50 ms. Tempo and
steadiness are given for both versions, and accuracy per measure appears when
measures are labeled. The edit summary lists beats added and deleted (from beat
IDs), undos, and the edit rate.

Recordings now store an optional ``sensitivity`` and ``editLog`` (undo count).
Both are optional, so earlier saved files still decode. Baton sessions record the
active sensitivity; touchpad recordings show "None (touchpad)".

Export opens the share sheet for Files, Messages, Google Drive and other
targets. It offers a single-page PDF made with ``ImageRenderer``, or a CSV with
one row per beat: ``time_s,source,label,offset_ms,measure``. Host checks are in
``Tests/BeatDetectionReportChecks.swift``.

Bluetooth link evaluation
-------------------------
The evaluation now records beat notifications only: received beat count,
sequence gaps estimating missing/lost beats, and phone arrival spacing. Motion
samples and practice-control read round trips are excluded. The CSV preserves
PCB uptime and phone monotonic timestamps; a true one-way PCB-to-phone latency
requires synchronized clocks and is not inferred from an unsynchronized clock
difference.

Open Settings → Evaluation → Bluetooth Evaluation. Connect a baton, start a
live evaluation, then practice with the configuration under test. Finish the
evaluation to inspect the results and share its CSV. The latest run stays in
memory until replaced or the app exits. Load simulated run exercises the same
analysis with synthetic packets and controlled gaps without hardware.

Beat and motion counters are tracked independently with 16-bit wrap handling.
Forward gaps estimate missing notifications between observed packets. Duplicates
and backward arrivals are labeled in the CSV. Loss outside the observed range
and radio retransmissions cannot be inferred. Arrival spacing includes the
baton's event cadence. Read round trips use the iPhone monotonic clock around
existing practice-control reads, including app scheduling and peripheral work.
The chart groups successful round trips in 5 ms bins. These times cannot directly
verify a 15 ms one-way beat latency budget. Export before starting another run.
