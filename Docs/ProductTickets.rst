Production app ticket audit
===========================

Based on the ticket descriptions supplied in chat (KAN-19, KAN-37 and KAN-39).
This is a local acceptance audit, not a Jira status update. No Jira connection or
remote ticket changes were made. Scope was narrowed by the user to features
available without firmware changes.

Home (KAN-37 / KAN-19)
----------------------

* Top Sound, Settings and Help icon navigation: implemented.
* Bluetooth connection dialog on Home: retained; discovery uses the common service UUID regardless of name.
* Health immediately below connection: implemented using connection and fresh
  valid motion data. Battery telemetry is excluded because firmware lacks it.
* Sound configuration/preview: six voices, including low/high and a single
  accented click. Test works without a baton. No subdivisions or measure accents.

Settings (KAN-39 / KAN-19)
--------------------------

* Scrollable Settings page and Home button: implemented.
* Bluetooth options at bottom: persistent scan duration and connection TTL.
* Connected-device list and identity: implemented for one connection. Real
  Bluetooth device-name editing now uses the companion name-enabled firmware,
  with persisted-status confirmation. This supersedes the original local-only
  nicknames. The iOS identifier is labelled accurately; standard device-reported
  IDs are shown only if exposed by firmware.
* Adaptive 1000-to-500 Hz sampling and firmware updates: excluded by app-only
  scope; no command/telemetry/DFU protocol exists for these in current firmware.
* Strict TTL during iOS suspension and simultaneous multi-baton operation are
  not implemented; the app explains the foreground/resume enforcement policy
  and its single-device connection limit.

Help
----

* Expandable Q&A, step-by-step setup and troubleshooting: implemented.

Validation
----------

Both shared iOS device schemes build unsigned. The existing Swift regressions
plus new product preference/timing/nickname checks pass; six voices are checked
against PCM buffers and the new pitched/accented waveforms are checked separately.
Hardware BLE setup, actual scan/TTL disconnect timing, reconnect/nickname use,
audio routes/interruptions and real device health still require an iPhone and
baton. The original app-only pass did not edit firmware. Subsequent device-name firmware
changes are described below; no device has been flashed.


Subsequent naming scope
-----------------------

The user separately authorized firmware work for actual device naming. The app
now uses the appended def4 name characteristic and the firmware persists names.
Adaptive sampling, battery telemetry and firmware updates remain excluded.
See README.rst in both repositories for the protocol and required hardware QA.
