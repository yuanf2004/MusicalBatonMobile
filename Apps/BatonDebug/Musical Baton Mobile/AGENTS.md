# Smart Baton iOS BLE Debug App

## Goal

Build a simple iOS application in **Swift + SwiftUI** that acts as a lightweight BLE debugging interface for our Smart Baton.

The app should behave similarly to the basic BLE functionality of **Nordic nRF Connect**:

1. Scan for nearby Bluetooth Low Energy devices.
2. Display discovered devices in a list.
3. Allow the user to connect to and disconnect from a device.
4. Once connected, navigate to a device detail screen.
5. Discover and display all GATT services and characteristics.
6. Display values received from readable/notifiable characteristics.
7. Include a terminal/log window at the bottom of the connected-device screen showing BLE events and received data.

This is currently a **development/debugging app**, not the final Smart Baton UI.

---

# Technology

Use:

- Xcode
- Swift
- SwiftUI
- CoreBluetooth
- iOS

Do not introduce third-party Bluetooth libraries unless absolutely necessary.

Use Apple's native `CoreBluetooth` framework.

---

# Project Architecture

Keep the architecture simple.

Suggested structure:

```text
SmartBaton/
│
├── SmartBatonApp.swift
│
├── Models/
│   ├── BLEDevice.swift
│   ├── BLEService.swift
│   └── BLECharacteristic.swift
│
├── Bluetooth/
│   └── BLEManager.swift
│
├── Views/
│   ├── DeviceScannerView.swift
│   ├── DeviceDetailView.swift
│   ├── ServiceView.swift
│   ├── CharacteristicView.swift
│   └── TerminalView.swift
│
└── Utilities/
    └── DataFormatting.swift
```

The exact file structure can differ slightly if needed, but Bluetooth logic should be separated from UI code.

---

# BLE Manager

Create a central Bluetooth manager responsible for all CoreBluetooth communication.

The manager should conform to:

```swift
CBCentralManagerDelegate
CBPeripheralDelegate
```

The manager should handle:

- Bluetooth state
- Scanning
- Discovered peripherals
- Connecting
- Disconnecting
- Service discovery
- Characteristic discovery
- Reading characteristics
- Subscribing to notifications
- Receiving updated characteristic values
- Logging BLE events

The manager should be observable by SwiftUI.

Prefer:

```swift
@Observable
```

if supported by the deployment target.

Otherwise use:

```swift
ObservableObject
@Published
```

---

# Screen 1 — BLE Device Scanner

The initial screen should display nearby BLE devices.

Example:

```text
Smart Baton BLE

[ Scan ]

--------------------------------

Smart Baton
RSSI: -48 dBm
[ Connect ]

nRF52840
RSSI: -62 dBm
[ Connect ]

Unknown Device
RSSI: -75 dBm
[ Connect ]
```

## Requirements

The screen should:

- Show whether Bluetooth is enabled.
- Have a button to start/stop scanning.
- Automatically update as devices are discovered.
- Avoid showing duplicate devices.
- Show the advertised device name when available.
- Show `"Unknown Device"` if no name is available.
- Show RSSI.
- Allow tapping a device or pressing a Connect button.

For each device store at minimum:

```swift
UUID
name
RSSI
CBPeripheral
```

Devices should be identified internally using:

```swift
peripheral.identifier
```

Do not identify devices only by advertised name.

---

# Connecting

When the user selects Connect:

1. Stop scanning.
2. Connect using `CBCentralManager`.
3. Set the peripheral delegate.
4. Once connected, discover services.
5. Navigate to the connected device screen.

Log events such as:

```text
Scanning started
Found Smart Baton RSSI -48
Connecting to Smart Baton...
Connected to Smart Baton
Discovering services...
```

If connection fails, display the error and allow retrying.

---

# Screen 2 — Connected Device

The connected-device screen should contain three major sections.

```text
< Devices

Smart Baton
Connected

[ Disconnect ]

----------------------

Services

> Service 180F
    Battery Service

> Service XXXXXXXX
    Smart Baton Service

----------------------

Terminal

14:32:01 Connected
14:32:01 Discovering services
14:32:02 Found service XXXXXXXX
14:32:02 Found characteristic YYYY
14:32:03 Notification enabled
14:32:03 RX: 01 04 A2 19
```

---

# Service Display

Display every GATT service discovered on the peripheral.

For each service show:

- UUID
- Known human-readable name if easy to determine
- Characteristics underneath it

Services may use an expandable/collapsible UI.

Example:

```text
▼ Smart Baton Service
  UUID: ABCD

    Acceleration
    UUID: ABC1

    Gyroscope
    UUID: ABC2

    Battery
    UUID: ABC3
```

Unknown UUIDs should still be displayed.

Do NOT hardcode the UI only for our custom Smart Baton UUIDs.

The app should be able to inspect arbitrary BLE peripherals like nRF Connect.

---

# Characteristic Display

For each characteristic display:

- UUID
- Supported properties
- Current value
- Raw hexadecimal value
- UTF-8 interpretation when valid

Example:

```text
Characteristic ABC1

Properties:
READ
NOTIFY

HEX:
41 42 43 44

UTF-8:
ABCD
```

Possible properties may include:

```text
Read
Write
Write Without Response
Notify
Indicate
Broadcast
Authenticated Signed Writes
```

Only show actions supported by the characteristic.

---

# Reading Characteristics

If a characteristic supports `.read`, provide a:

```text
Read
```

button.

Call:

```swift
peripheral.readValue(for: characteristic)
```

Update the displayed value when:

```swift
peripheral(
    _ peripheral: CBPeripheral,
    didUpdateValueFor characteristic: CBCharacteristic,
    error: Error?
)
```

is triggered.

---

# Notifications

If a characteristic supports:

```swift
.notify
```

or

```swift
.indicate
```

allow the user to enable/disable notifications.

Example:

```text
Notifications: ON
```

Use:

```swift
peripheral.setNotifyValue(true, for: characteristic)
```

When notified data arrives:

1. Update the characteristic's displayed value.
2. Add the value to the terminal log.

Example terminal message:

```text
14:32:05 RX [ABC1]: 04 FF A2 03 18 00
```

Do not assume that incoming data is text.

Always preserve/display the raw bytes.

---

# Optional Write Support

If a characteristic supports writing, it is useful to provide a basic write field.

This is optional for the first version but preferred if straightforward.

Allow:

```text
HEX
UTF-8
```

input modes.

Example:

```text
Write Value

[ 01 FF 03 ]

Format: HEX

[ Write ]
```

Use the appropriate CoreBluetooth write type:

```swift
.withResponse
```

or:

```swift
.withoutResponse
```

depending on supported characteristic properties.

---

# Terminal

The bottom portion of the connected-device screen should contain a terminal-style event log.

Example:

```text
Terminal

[14:32:01] Connected to Smart Baton
[14:32:01] Discovering services
[14:32:02] Service discovered: ABCD
[14:32:02] Characteristic discovered: ABC1
[14:32:02] Notifications enabled: ABC1
[14:32:03] RX ABC1: 1A 02 FF 30
```

The terminal should record:

- Scan started
- Scan stopped
- Device discovered
- Connection attempt
- Connection success
- Connection failure
- Disconnect
- Service discovery
- Characteristic discovery
- Read operations
- Write operations
- Notification enable/disable
- Received characteristic data
- BLE errors

Terminal entries should include timestamps.

The terminal should automatically scroll to the newest message.

Include a:

```text
Clear
```

button.

---

# Layout

The device detail screen should use roughly:

```text
--------------------------------
Device information
--------------------------------

Services + Characteristics
(scrollable)

--------------------------------
Terminal
--------------------------------
```

The service area should take most of the screen.

The terminal can occupy approximately the bottom 25–35% of the screen.

A draggable divider is not necessary.

---

# Disconnect Behavior

A Disconnect button should call:

```swift
centralManager.cancelPeripheralConnection(peripheral)
```

After disconnecting:

- Update the UI.
- Log the disconnection.
- Return to the scanner screen.
- Allow scanning again.

Also correctly handle unexpected disconnects.

---

# Data Formatting

Create helper functions for converting Data.

## Hex

Example:

```swift
func hexString(from data: Data) -> String {
    data.map { String(format: "%02X", $0) }
        .joined(separator: " ")
}
```

Example output:

```text
01 FF A4 22
```

## UTF-8

Attempt:

```swift
String(data: data, encoding: .utf8)
```

If conversion fails, display:

```text
Not valid UTF-8
```

Never discard the hex representation.

---

# Bluetooth Permissions

Ensure the application contains the appropriate Bluetooth usage description in its app configuration / Info.plist.

Use a description such as:

```text
Smart Baton uses Bluetooth to connect to and communicate with the baton.
```

Handle Bluetooth states including:

```text
poweredOn
poweredOff
unauthorized
unsupported
resetting
unknown
```

Show the user an appropriate status message instead of silently failing.

---

# Threading / UI Safety

CoreBluetooth events should correctly update SwiftUI state on the appropriate thread / actor.

Prefer modern Swift concurrency where appropriate, but do not unnecessarily redesign CoreBluetooth around async/await.

Keep CoreBluetooth delegate behavior straightforward.

---

# First Development Milestone

Before implementing every feature, get this basic flow working:

```text
Launch app
   ↓
Scan
   ↓
See Smart Baton
   ↓
Connect
   ↓
Discover services
   ↓
Discover characteristics
   ↓
Subscribe to notification characteristic
   ↓
Display received bytes
   ↓
Show bytes in terminal
```

This milestone is more important than visual polish.

---

# Smart Baton Context

Our physical device uses an:

```text
nRF52840
```

running:

```text
Zephyr RTOS
```

and communicates with the iPhone using BLE GATT.

The baton contains an:

```text
LSM6DSOX IMU
```

which will eventually stream motion data over BLE.

The Swift app should NOT perform gesture recognition yet.

For now the goal is simply to verify and inspect communication between:

```text
LSM6DSOX
    ↓
nRF52840 / Zephyr
    ↓
BLE GATT
    ↓
iPhone / CoreBluetooth
    ↓
SwiftUI App
```

nRF Connect already serves as our reference implementation for BLE testing.

The Swift app should initially provide comparable visibility into services, characteristics, and received data.

---

# UI Style

Keep the UI simple and clean.

Use native SwiftUI components.

A basic NavigationStack is sufficient.

Recommended views:

```text
NavigationStack
    DeviceScannerView
        ↓
    DeviceDetailView
```

Use:

```swift
List
Section
DisclosureGroup
ScrollView
Button
Text
```

where appropriate.

Avoid unnecessary animations or elaborate styling.

Dark mode support should work naturally using native system colors.

---

# Important Implementation Rules

1. Do not hardcode one device name as the only connectable device.
2. Do not assume service or characteristic UUIDs before discovery.
3. Do not assume incoming BLE values are strings.
4. Always preserve raw bytes.
5. Prevent duplicate scanned devices.
6. Use the peripheral UUID as its identity.
7. Do not mix all CoreBluetooth logic directly into SwiftUI views.
8. Keep `BLEManager` responsible for BLE state and operations.
9. Handle errors visibly.
10. Keep the first version focused on BLE debugging rather than the final Smart Baton product UI.

---

# Definition of Done

The initial version is complete when I can:

1. Open the app on an actual iPhone.
2. Scan for nearby BLE devices.
3. See the Smart Baton.
4. Connect to it.
5. Disconnect from it.
6. See its GATT services.
7. Expand a service and see its characteristics.
8. See each characteristic's UUID and properties.
9. Read readable characteristics.
10. Enable notifications on notifiable characteristics.
11. See notification data update live.
12. See raw received bytes in the terminal.
13. See BLE events/errors in the terminal.
14. Return to the scanner and reconnect.

Prioritize these behaviors over visual polish


## README FOR THE FIRMWARE SIDE (MORE CONTEXT)

# Musical Baton firmware context

## Project purpose

This repository contains Zephyr/nRF Connect SDK firmware for a battery-powered
musical baton based on the nRF52840. The firmware reads motion data and exposes
it over Bluetooth Low Energy. Development currently uses an nRF52840 DK and an
LSM6DSOX breakout; the finished PCB also uses an LSM6DSOX IMU.

Treat the KiCad schematic as the source of truth for PCB wiring. The schematic
used to verify the pin map is currently located at:

`/Users/yuan/Documents/Smart Baton/L Smart Baton/L Smart Baton.kicad_sch`

Do not hard-code board-specific GPIO numbers in C modules. Application code
uses devicetree aliases, while overlays map those aliases to development or PCB
pins.

## Hardware configurations

### nRF52840 DK development setup

The normal DK build automatically loads `nrf52840dk_nrf52840.overlay`.

| Function | Development connection | Notes |
|---|---|---|
| User button | DK Button 1, P0.11 | Active-low; the button connects the pin to GND |
| Bluetooth LED | Arduino A0 / P0.03 | PWM output; LED anode goes through a 330 ohm to 1 kohm resistor to P0.03, cathode to GND |
| LSM6DSOX SDA | P0.27 | Matches PCB wiring |
| LSM6DSOX SCL | P0.26 | Matches PCB wiring |
| LSM6DSOX address | 0x6A | SA0 low; I2C fast mode |

P0.19 and P0.21 are connected to the DK's external QSPI flash by default and
are not routed for normal GPIO use at connector P24. Using P0.19 requires
cutting SB11 and shorting SB21. Using P0.21 requires cutting SB14 and shorting
SB24. The current development overlay avoids these changes.

The development setup has no RGB battery LED mapping. The RGB functions compile
as no-ops on the DK, while the Bluetooth LED remains fully functional.

### Custom Musical Baton PCB

Use `boards/musical_baton.overlay` for the custom PCB.

| Function | nRF52840 pin | Electrical behavior |
|---|---:|---|
| User button | P0.19 | Active-low to GND with internal pull-up |
| Charger status | P0.20 | Active-low open-collector signal with pull-up |
| Bluetooth LED | P0.21 | Active-high PWM output; LED cathode is grounded |
| RGB red | P0.22 | Active-low, common-anode RGB LED |
| RGB green | P0.23 | Active-low, common-anode RGB LED |
| RGB blue | P0.24 | Active-low, common-anode RGB LED |
| Battery sense | P0.02 / AIN0 | 1 Mohm / 1 Mohm divider with 100 nF capacitor |
| IMU INT1 | P0.13 | Active-high |
| IMU INT2 | P0.14 | Active-high |
| LSM6DSOX SCL | P0.26 | I2C fast mode |
| LSM6DSOX SDA | P0.27 | I2C fast mode |
| LSM6DSOX address | 0x6A | SA0 is tied to GND |
| Reset | P0.18 | Hardware reset |
| Low-frequency crystal | P0.00, P0.01 | 32.768 kHz crystal |
| SWD | Dedicated SWD pins | Programming and debugging |

The PCB's USB-C connector is used for power and charging, not USB data. The
power switch is a physical power-path switch and is not controlled by an MCU
GPIO.

## Devicetree aliases

C code depends on these logical names:

| Alias | Purpose |
|---|---|
| `baton-imu` | Six-axis LSM6DSOX IMU |
| `baton-button` | Main user button |
| `ble-led` | PWM-controlled Bluetooth status LED |
| `rgb-red-led` | Battery RGB red channel |
| `rgb-green-led` | Battery RGB green channel |
| `rgb-blue-led` | Battery RGB blue channel |

The DK overlay maps `baton-button` to P0.11 and `ble-led` to P0.03. The PCB
overlay maps them to P0.19 and P0.21. Keep application code independent of this
difference.

## Current firmware behavior

### Button

`src/button.c` uses GPIO interrupts on both edges.

- Debounce time: 30 ms
- Multi-click collection window: 600 ms
- Three quick presses toggle Bluetooth
- Holding for 10 seconds performs a cold reboot
- A detected press queues `BUTTON_EVENT_PRESSED`; the main loop prints
  `Baton button pressed`. Initialization prints the configured controller/pin.
- Completed click sequences are delivered as generic click-count events so
  more actions can be added later

Button callbacks enqueue events; slow work runs from the main loop rather than
inside the GPIO interrupt handler.

### Bluetooth

Bluetooth initializes after reboot but starts inactive and does not advertise.

- Triple-click while inactive starts advertising
- Triple-click while active stops advertising
- Deactivation also disconnects the connected phone
- An unexpected disconnect while Bluetooth remains active restarts advertising
- Advertising without a live connection times out after 60 seconds: advertising
  stops, the LED turns off, and Bluetooth becomes inactive. Triple-click opens
  another window. Connecting cancels expiry; disconnecting starts a new window.
  Stored pairing/bonding does not count as a live connection.
- The custom GATT service publishes a fixed, versioned 20-byte motion packet

Motion packet version 1, in little-endian order:

- Byte 0: version
- Byte 1: flags (acceleration valid, gyroscope valid, time synchronized)
- Bytes 2-3: sequence number
- Bytes 4-7: nRF uptime in milliseconds
- Bytes 8-13: accelerometer X/Y/Z as signed 16-bit mg values
- Bytes 14-19: gyroscope X/Y/Z as signed 16-bit values in 0.1 degrees/second
- Successful LSM6DSOX reads populate all six axes and set acceleration-valid
  and gyroscope-valid flags. Time synchronization is not implemented.

Current UUIDs:

- Service: `12345678-1234-5678-1234-56789abcdef0`
- Motion characteristic: `12345678-1234-5678-1234-56789abcdef1`

### LEDs

`src/led.c` owns LED behavior.

Bluetooth LED states:

- Bluetooth inactive: off
- Advertising: PWM breathing fade
- Connected: three 100 ms on/off flashes, then solid on
- Leaving connected: three 100 ms on/off flashes, then breathing if advertising
  or off if inactive. Bluetooth callbacks request states; delayed LED work
  animates the 600 ms transition without delaying connection/disconnection.
  Repeated states and advertising restarts preserve ongoing disconnect flashes.

The current fade uses 25 brightness steps at 60 ms per step. It takes 1.5
seconds to fade on and 1.5 seconds to fade off, for a three-second complete
cycle.

Battery RGB states are prepared for future battery-monitor code:

- Charging: blue
- Above 50%: green
- 20% through 50%: yellow
- Below 20%: red
- Off: all channels off

The PCB RGB LED is common-anode, and devicetree polarity handles its active-low
channels.

### Sensor status

`src/sensor.c` uses the Zephyr sensor API and the `baton-imu` devicetree alias.
NCS v3.4.0 uses `st,lsm6dso` / `CONFIG_LSM6DSO` for basic LSM6DSOX motion
registers (matching WHO_AM_I value 0x6C). Both DK and PCB overlays configure
52 Hz acceleration and gyro, +/-4 g and +/-1000 degrees/second ranges.
Accelerometer LPF2 uses ODR/10 (approximately 5.2 Hz) via `accel-lp-filter`;
all console/BLE acceleration samples are filtered in hardware. Gyroscope filter
settings remain at the driver defaults.
The application polls every 50 ms (BLE updates remain every 200 ms); interrupts and FIFO are not used.
Successful six-axis samples print to the 115200-baud serial console approximately
every 50 ms, one sample per line, even when Bluetooth is inactive.
`CONFIG_LOG_PRINTK=n` routes prints directly to UART to avoid deferred-log batching.
IMU nodes use `zephyr,deferred-init`; `sensor_init()` waits 100 ms before
calling `device_init()` and another 500 ms after initialization for filter/measurement
settling (20 accelerometer samples at 52 Hz take approximately 385 ms). Revisit
this wait when adjusting ODR or filtering. Initialization failure prints identity probes at both SA0 addresses. Readings are converted to mg and
0.1 degrees/second, rounded, and clamped to signed 16 bits. Failed reads leave
the output unchanged and are not published over BLE.

DK and PCB both use SDA P0.27 / SCL P0.26. Their button and LED mappings
remain distinct; always build/flash with the matching overlay/build directory.
Hardware communication and accuracy must be verified on a connected LSM6DSOX.

## Important files

- `src/main.c`: initialization and main event/sample loop
- `src/button.c`, `src/button.h`: interrupt-driven button event module
- `src/bluetooth.c`, `src/bluetooth.h`: BLE state and six-axis motion service
- `src/led.c`, `src/led.h`: Bluetooth PWM LED and battery RGB states
- `src/sensor.c`, `src/sensor.h`: LSM6DSOX six-axis sensor module
- `nrf52840dk_nrf52840.overlay`: development-kit wiring
- `boards/musical_baton.overlay`: final PCB wiring
- `prj.conf`: Zephyr features
- `CMakeLists.txt`: application source list

## Building

Run builds from an nRF Connect SDK terminal configured for NCS v3.4.0.

Development kit:

```sh
west build --no-sysbuild -p always -d build-lsm6dsox-dk -b nrf52840dk/nrf52840 -- \
  -DDTC_OVERLAY_FILE=nrf52840dk_nrf52840.overlay
```

Custom PCB while it still reuses the DK board definition:

```sh
west build --no-sysbuild -p always -d build-lsm6dsox-pcb -b nrf52840dk/nrf52840 -- \
  -DDTC_OVERLAY_FILE=boards/musical_baton.overlay
```

Flash the DK build explicitly (use `-d build-lsm6dsox-pcb` for the PCB):

```sh
west flash -d build-lsm6dsox-dk
```

A future improvement is to create a real `musical_baton/nrf52840` board target
so the PCB hardware description is selected automatically.

The DK startup button message must report pin 11. Pin 19 identifies PCB
button wiring; both builds use the same board target, so verify the overlay
and build directory before flashing.

## Development rules

- Preserve the separation between reusable application behavior and pin mapping.
- Put pin changes in the appropriate overlay instead of C source files.
- Preserve active-low/active-high flags from the schematic.
- Keep interrupt callbacks short and defer work to queues or work items.
- Keep Bluetooth inactive by default after every reboot unless product behavior
  is intentionally changed.
- Build the DK target after firmware changes.
- Validate the PCB overlay after hardware-description changes.
- Verify sensor communication and motion readings on hardware; successful builds
  alone do not verify electrical wiring or accuracy.
- Update `README.rst` with every project change to reflect current behavior,
  wiring, build instructions, and limitations.
