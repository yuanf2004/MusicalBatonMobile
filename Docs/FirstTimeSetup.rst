Musical Baton first time Mac and iPhone setup
=============================================

This guide takes you from a fresh Mac/Xcode setup to running Musical Baton on
an iPhone and connecting a baton. No previous Xcode experience is assumed.
Follow the numbered sections in order. A simulator can show the interface, but
use a real iPhone for Bluetooth, motion and audio testing.

You will finish with the app installed on your phone, a working Bluetooth
connection, and a sound you can test while conducting.

.. contents:: Find a step
   :local:
   :depth: 2

1. Gather what you need
-----------------------

* A Mac that supports the Xcode version you will install.
* The full Xcode application, available from the Mac App Store. Command Line
  Tools alone are not enough to open and run this iOS project.
* An iPhone running iOS 17 or later, with its passcode available.
* A USB cable that transfers data, not just power.
* Your own Apple Account and an internet connection for setup/signing.
* Access to the MusicalBatonMobile repository or a complete project ZIP.
* A powered baton with compatible Musical Baton firmware for the Bluetooth steps.

You can build the iPhone app without installing the Nordic SDK, Python packages,
Node.js, CocoaPods, or third-party Bluetooth libraries. Fonts and the gesture
model are included in the repository. The app and baton firmware are separate
projects; installing the app does not update the baton.

A free Apple Account can use Xcode's **Personal Team** for on-device testing.
Apple currently limits these development provisioning profiles to seven days;
rebuild and reinstall through Xcode when they expire. A paid developer membership
is not required just to try this project's current features on your own phone.
See `Apple's Personal Team explanation <https://developer.apple.com/help/account/basics/about-your-developer-account>`_.

2. Install and open Xcode
-------------------------

1. Install **Xcode** from the Mac App Store and wait for installation to finish.
2. Open Xcode from Applications.
3. Complete its first-launch setup. Review any agreements yourself, and allow
   Xcode to install the components it requests for iOS development.
4. If Xcode offers platform downloads, install the iOS support it needs. An iOS
   simulator runtime is useful for UI previews but does not replace an iPhone
   for testing the baton.

Choose an Xcode release that supports both your Mac's macOS and your phone's iOS.
If Xcode says the phone's software is unsupported, check compatibility before
changing project settings. See `Apple's Xcode compatibility table <https://developer.apple.com/xcode/system-requirements>`_.

**Checkpoint:** Xcode opens normally and is no longer asking to finish installing
its basic development components.

3. Get the complete project
---------------------------

Repository: https://github.com/yuanf2004/MusicalBatonMobile

If the repository is private, first ask the project owner to grant your GitHub
account access. Use your own account.

Option A: Download a ZIP
~~~~~~~~~~~~~~~~~~~~~~~~

1. Open the repository in a browser.
2. Choose **Code → Download ZIP**.
3. Unzip it and keep the entire extracted folder together.
4. Find **MusicalBaton.xcworkspace** inside that folder.

Option B: Clone with Git
~~~~~~~~~~~~~~~~~~~~~~~~

Open Terminal and run these commands, one line at a time::

    mkdir -p ~/Developer
    cd ~/Developer
    git clone https://github.com/yuanf2004/MusicalBatonMobile.git
    cd MusicalBatonMobile

If Git asks for authentication, use your organization's normal GitHub sign-in
method. If you are unfamiliar with Git, the ZIP route is enough for an initial
installation; a GitHub Desktop clone also works.

The top-level folder should include::

    MusicalBaton.xcworkspace
    Apps/
        Baton/           Production app
        BatonDebug/      Developer/debug app
    Shared/
        BatonKit/        Code used by both apps
    Docs/
    Tests/
    Tools/
    README.rst

Do not copy only an app subfolder: both apps depend on Shared/BatonKit.
If these files are missing, obtain the latest monorepo version from the team.

4. Open the workspace and choose an app
---------------------------------------

Double-click **MusicalBaton.xcworkspace**. If Xcode is already open, use
**File → Open** and select that workspace.

Near the Run triangle at the top of Xcode are the scheme selector and the run
destination selector. A scheme tells Xcode which app to build.

.. list-table:: The two apps
   :header-rows: 1
   :widths: 22 38 40

   * - Scheme to run
     - Project and app target used for signing
     - What it does
   * - Musical Baton
     - Project Baton; target Baton
     - Main app with Home, Sound, Settings and Help. Start here.
   * - Baton Debug
     - Project Musical Baton Mobile; target Musical Baton Mobile
     - BLE inspector with services, characteristics, terminals and graphs.

Choose **Musical Baton** for your first run. You can install both apps later;
they have different bundle identifiers and keep their own saved data.

5. Sign in to Xcode and configure signing
-----------------------------------------

Signing lets iOS identify the developer installing the app. A provisioning
profile connects the app, signing team and permitted test device. Xcode can
create these development assets automatically.

1. In Xcode, open **Xcode → Settings → Apple Accounts**. Some releases label
   this pane **Accounts**.
2. Add your Apple Account and complete its normal sign-in steps.
3. In the project navigator on the left, select the blue **Baton** project icon.
4. In the editor, find the **TARGETS** list and select **Baton**. Select the app
   target, rather than the project-level settings or a Swift source file.
5. Open **Signing & Capabilities**.
6. Enable **Automatically manage signing** if it is not already enabled.
7. Under **Team**, choose your own Personal Team, or the shared development team
   you were invited to use. The team committed in the repository belongs to the
   original developer; another person may need to select a different team.

If Xcode says the bundle identifier is unavailable to your team, give your test
build a unique one, such as **com.yourname.musicalbaton**. Replace ``yourname``
with your own identifier. If using the team's signing account, keep the existing
identifier unless the team tells you otherwise. Let Xcode register the test
device if it requests this.

To install Baton Debug, repeat the target-signing steps in the **Musical Baton
Mobile** project and target; use a separate identifier such as
**com.yourname.musicalbaton.debug** if needed. Ask before committing personal
signing changes to the shared repository.

Changing an app's bundle identifier gives it a separate iPhone data container.
It does not change the baton's Bluetooth discovery UUID or device name.
See `Apple's physical-device signing instructions <https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices>`_.

6. Connect the iPhone and trust the Mac
---------------------------------------

1. Connect the iPhone to the Mac using the data cable.
2. Unlock the iPhone and keep it unlocked during initial setup.
3. If the Mac asks whether to allow the accessory to connect, allow the iPhone.
4. If Finder asks to trust the iPhone, select it in Finder's sidebar and follow
   that prompt.
5. On the iPhone, if **Trust This Computer?** appears, tap **Trust** and enter
   the iPhone passcode.

This permission is between the phone and the Mac; it is separate from Developer
Mode and app-developer trust. See `Apple's computer-trust instructions <https://support.apple.com/en-us/109054>`_.

In Xcode, choose your physical iPhone as the run destination. If it is not ready,
open **Device Hub** in newer Xcode versions, or **Window → Devices and
Simulators** in versions that provide that window. Select the phone and follow
its pairing/preparation messages. Device Hub is the newer device-management
interface; see `Apple's Device Hub introduction <https://developer.apple.com/videos/play/wwdc2026/260/>`_.

**Checkpoint:** your actual phone is listed as a run destination. A simulator
with the same iPhone model name is a different destination.

7. Enable Developer Mode on the iPhone
--------------------------------------

1. Begin pairing/preparing the phone in Xcode as described above.
2. On the iPhone, open **Settings → Privacy & Security → Developer Mode**.
3. Turn **Developer Mode** on.
4. Choose **Restart** when prompted.
5. After the phone restarts, unlock it and confirm **Enable** or **Turn On**
   when the confirmation appears. Enter your iPhone passcode as requested.
6. Return to Xcode with the phone connected and unlocked.

If Developer Mode is missing, initiate pairing with Xcode first; Apple only
shows the setting after pairing is initiated or the phone was previously paired.
Reopen Settings after doing so. On a managed phone, contact the administrator if
policy prevents development use.

Developer Mode permits development-signed apps to run; it does not by itself
install this project. See `Apple's Developer Mode guide <https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device>`_.

8. Build and install the app
----------------------------

1. In Xcode's top toolbar, select **Musical Baton** as the scheme.
2. Select your connected physical iPhone as the destination.
3. Click **Run**, the triangle button, or press **Command-R**.
4. Wait while Xcode builds, signs, installs and launches the app. The first run
   can also prepare the device or download support components.
5. If macOS asks to unlock the login keychain so code signing can use your
   development key, follow that prompt using your Mac login password.

The phone should open Musical Baton. If Xcode installs the icon but reports that
the developer is not trusted, continue with the next section and then run again.
To read a failed build, open Xcode's Issue navigator with **Command-5** and start
with the first red error. See `Apple's device run instructions <https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html>`_.

9. Trust the app developer only if iOS requests it
--------------------------------------------------

Some development installations require a separate certificate-trust step. Skip
this section if the app already opens.

If the phone or Xcode reports **Untrusted Developer** or asks you to trust the
Developer App certificate:

1. On the iPhone, open **Settings → General → VPN & Device Management**.
2. Under **Developer App**, select the entry matching the Apple Account/team
   used to sign this installation. Wording can vary by iOS and signing method.
3. Choose **Trust** or the verification option shown for that developer and
   confirm the request. Keep the phone online for any certificate verification.
4. Return to Xcode and press **Command-R**, or reopen the installed app.

If there is no matching entry, first check that Xcode actually installed the app
and that you are looking at the same team used in Signing & Capabilities. An
unsuccessful build does not create a developer entry to trust.

Enterprise-signed distributions can show **Allow & Restart** instead of Trust;
that is a different distribution flow and is not a required extra step for every
Xcode installation. Follow the prompt for your actual installation. See
`Apple's certificate-trust instructions <https://support.apple.com/en-ie/118254>`_.

This project does not require downloading a separate configuration profile or
installing a root certificate. The iPhone's **Certificate Trust Settings** page
under About is not the developer-app trust page.

10. Allow Bluetooth and connect a baton
---------------------------------------

1. On the iPhone, turn Bluetooth on in **Settings → Bluetooth**.
2. Open Musical Baton and allow its Bluetooth access prompt.
3. If you previously denied access, open **Settings → Privacy & Security →
   Bluetooth** and enable access for Musical Baton. Repeat separately for Baton
   Debug if you install it. See `Apple's Bluetooth permission guide <https://support.apple.com/en-us/102267>`_.
4. Power on the baton. Bluetooth starts inactive after a baton reboot.
5. Quickly press the baton button **three times**. The Bluetooth light should
   breathe while it advertises.
6. In Musical Baton, tap **Find my baton** and select the baton in the list.
7. Wait for connection and service setup. Home should show the connected baton
   and a health card; receiving motion means recent valid motion data is arriving.

Connect through the app's Find my baton screen. You do not need to pair this
baton through the iPhone's normal Bluetooth accessories list first.

The baton advertises for up to **60 seconds** without a live connection. The
phone's search defaults to **30 seconds** and can be changed in the app's
Settings. If either window ends, triple-press again and start another search.

A freshly configured baton is normally named **Smart Baton**. A previously
renamed one can have a different name. The production app finds the shared baton
service UUID, not a specific name. Keep the baton disconnected from other phones
and from Baton Debug when connecting in the main app; one connection is supported.

11. Test sound and start practice
---------------------------------

1. Open **Your sound** using the music-note icon at the top of Home.
2. Choose a sound and tap **Test sound**. This preview works without a baton.
3. Choose the movement sensitivity, then tap **Save**.
4. Connect the baton if it is not connected already.
5. Tap **Start practice**. Wait for setup, hold the baton still briefly, then
   conduct. Accepted strokes play the selected sound and increase the beat count.

For an initial audio test, use the phone speaker and raise the media volume.
Practice uses the current audio route, including connected headphones. Starting
practice pauses other media. Weak or idle movements can be filtered out.

Keep the app open while practicing. Backgrounding, disconnection, an audio
interruption or a headphone-route change can stop practice. Return and start it
again when ready. Stop practice before changing sound/sensitivity or renaming.
The Help button at the top of Home has setup and troubleshooting Q&A.

Optional: Rename the baton itself
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

With name-enabled firmware, open **Settings → Connected batons** and tap the
connected baton's name. On **Your baton**, edit **Baton Bluetooth name**, then
tap **Save on baton** and wait for confirmation.
The 20-byte UTF-8 limit means emoji/accented letters can use multiple bytes.
The name is saved on the baton and survives normal reboot; other phones see it
when advertising resumes. Reconnect/reboot to check it. Some scanners may cache
an older name briefly. If the page asks for updated firmware, the iOS app alone
cannot enable device-side renaming.

12. Use the installed app on later days
---------------------------------------

Once installed and trusted, you can open the app from the phone's Home Screen
without leaving it tethered to Xcode. The development signing must remain valid;
a free Personal Team installation needs periodic rebuilding after its seven-day
profile expires, as described in section 1.

Reopen the same workspace and keep the same team and bundle identifier when
updating your test installation. Switching to a new identifier creates a separate
app/data container. Deleting an app removes its local saved data, so do not use
uninstall/reinstall as the first troubleshooting step.

For the other app, select **Baton Debug** in the scheme menu, configure its own
target signing, choose the phone and press **Command-R**. Disconnect the main
app before connecting the debug app to the same baton.

If you cloned with Git and have no local changes to preserve, you can obtain
published updates from the repository root with::

    git pull --ff-only

If Git reports local changes or diverging history, stop and ask the team how to
reconcile them before discarding anything. If you downloaded a ZIP, obtain the
updated full project rather than replacing individual shared source folders.

Troubleshooting by symptom
--------------------------

The phone is not in Xcode's destination menu
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Unlock it, reconnect the data cable, check Finder and the trust prompt, and read
the phone's preparation status in Device Hub/Devices and Simulators. Try another
data cable or USB port if Finder cannot see the phone. A charging indicator
alone does not prove the cable carries data.

Xcode says Developer Mode is disabled
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Complete section 7, including the confirmation after restart. Merely turning on
the switch before the restart does not complete the process.

Signing requires a development team or no profiles were found
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Return to the correct app **target**, choose your team, enable automatic signing,
and select the physical phone. Check the account's sign-in and any registration
prompt. If the identifier belongs to another team, follow section 5's unique-ID
instructions. Do not look for a missing provisioning profile inside this repo;
Xcode normally creates it for your team and phone.

Xcode reports unsupported iOS or cannot prepare the device
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Read the exact device status and check the Xcode compatibility link in section 2.
Complete requested support downloads or update Xcode/macOS as appropriate. Do
not lower the project's iOS 17 minimum to bypass a tool/device mismatch.

The icon installed but the app will not open
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Read the phone's message: an untrusted developer needs section 9; Developer Mode
needs section 7; an expired signing profile needs another Xcode build/install.
If verification fails, check internet access and the signing team's status.
School/work-managed phones can have policies that require administrator help.

The app worked last week and suddenly stopped launching
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

For a free Personal Team, reconnect and run it through Xcode with the same team
and identifier to renew the development installation. See the seven-day limit
in section 1. Do not assume this is a Bluetooth or baton firmware fault.

Find my baton shows no devices
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Check app Bluetooth permission, triple-press the powered baton, and search again
before its 60-second advertising window ends. Disconnect other phones/apps.
A renamed baton should still appear. If the device was flashed with unrelated
firmware, it may not advertise the service this app searches for.

The app connects but Start practice stays unavailable
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Wait for service setup and make sure a sound profile is saved. If the app asks
for updated firmware, ask the hardware team to verify the baton has the current
motion, beat and settings service. This is separate from installing the phone
app. A successful UI preview does not establish firmware compatibility.

Connected appears but there is no motion or sound
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Use Test sound first. If that is silent, check volume and audio output. If sound
preview works but Home never reports Receiving motion, ask the hardware team to
check IMU wiring, startup messages and the flashed firmware/overlay. Do not
interpret missing motion as a measured low battery; battery reporting is not
implemented in the current firmware.

The connection ends after a predictable amount of time
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Check the app's Settings → Bluetooth → Connection time limit. Choose No limit
if you do not want the phone to end a session after a set duration. An expired
limit can be enforced when the app resumes after iOS suspension.

I only want to look at the UI without an iPhone
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Choose a simulated iPhone as the destination and Run. Download its runtime if
Xcode requests one. Bluetooth hardware, actual baton data and real phone audio
latency still need a physical iPhone and baton.

For teammates who also maintain firmware
----------------------------------------

The mobile repository builds the iPhone apps. The separate firmware application
is the **MusicalBaton** folder inside **SmartBatonZach**. For a first iPhone setup,
ask for a preflashed baton; an iOS installation does not require learning the
Nordic toolchain first.

If you are responsible for firmware, use the firmware repository's README and an
**NCS v3.4.0-configured terminal**. From its MusicalBaton folder, the DK commands
are::

    west build --no-sysbuild -p always -d build-lsm6dsox-dk -b nrf52840dk/nrf52840 -- -DDTC_OVERLAY_FILE=nrf52840dk_nrf52840.overlay
    west flash -d build-lsm6dsox-dk

These are **development-kit** commands. The custom PCB uses its own overlay and
build directory; consult the firmware README before flashing that hardware.
The DK startup button message should report pin 11; pin 19 means PCB wiring.
The PCB USB-C connector supplies power/charging, not a phone-style USB data link.
Xcode cannot flash the nRF52840. Do not change iOS Bluetooth UUIDs to work around
an incompatible firmware image.

First run completion checklist
------------------------------

* The complete monorepo is present and MusicalBaton.xcworkspace is open.
* Musical Baton is the selected scheme; the destination is the physical iPhone.
* The Baton target has a valid signing team and identifier for that team.
* The phone trusts the Mac, Developer Mode is confirmed after restart, and any
  developer-certificate trust request is resolved.
* Command-R installs and launches the app.
* Bluetooth permission is allowed for the installed app.
* Test sound plays, Find my baton connects, and Home receives motion.
* Start practice plays cues from accepted baton strokes.

When asking the team for help, share the first red Xcode error or exact iPhone
message, the selected scheme, Xcode version, iPhone/iOS version, and whether the
baton was advertising. Those details usually identify which setup stage failed.
