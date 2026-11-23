import CoreBluetooth
import Foundation
import Observation

// CoreBluetooth delivers all delegates on the main queue supplied below.
@MainActor
@Observable
final class BLEManager: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    private(set) var batteryPercentage: Int?
    @ObservationIgnored private var batteryPolling: Task<Void, Never>?

    private func startBatteryPolling(_ model: BLECharacteristic) {
        batteryPolling?.cancel()
        batteryPolling = Task { [weak self, weak model] in
            while !Task.isCancelled {
                guard let self, let model, self.isConnected else { return }
                if !model.readPending { self.read(model) }
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
    }

    private(set) var bluetoothState: CBManagerState = .unknown
    private(set) var isScanning = false
    private(set) var devices: [BLEDevice] = []
    private(set) var activeDevice: BLEDevice?
    private(set) var isConnected = false
    private(set) var isDisconnecting = false
    private(set) var isDiscoveringServices = false
    private(set) var services: [BLEService] = []
    private(set) var logs: [BLELogEntry] = []
    var errorMessage: String?
    var remotePracticeAllowed = false
    private(set) var batonPracticeState: BatonPracticePacket.State?
    @ObservationIgnored private var practicePolling: Task<Void, Never>?
    @ObservationIgnored private var practiceConfirmed = false
    @ObservationIgnored private var practiceCommandSequence: UInt16 = 0
    @ObservationIgnored private var practiceCommandActive = false
    @ObservationIgnored private var lastPracticeReply: TimeInterval?
    @ObservationIgnored private var holdSequence: UInt8?

    private var practiceCharacteristic: BLECharacteristic? {
        services.flatMap(\.characteristics).first { $0.isBatonPractice }
    }

    private func writePractice(_ active: Bool) {
        guard let model = practiceCharacteristic, !model.writePending,
              let peripheral = usablePeripheral(for: model) else { return }
        if active != practiceCommandActive {
            practiceCommandSequence &+= 1
            practiceCommandActive = active
        }
        model.writePending = true
        peripheral.writeValue(BatonPracticePacket.command(active: active, sequence: practiceCommandSequence),
                              for: model.characteristic, type: .withResponse)
    }

    private func startPracticePolling() {
        practicePolling?.cancel()
        holdSequence = nil
        lastPracticeReply = nil
        practiceConfirmed = false
        practicePolling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isConnected, let model = self.practiceCharacteristic else { return }
                let now = ProcessInfo.processInfo.systemUptime
                if let last = self.lastPracticeReply, now - last > 3, self.conducting.isEnabled {
                    self.stopConducting(reason: "Baton control timed out. Start practice again.")
                }
                // Never renew an active lease after a stale connection or app suspension.
                let fresh = self.lastPracticeReply.map { now - $0 <= 3 } ?? false
                self.writePractice(fresh && self.conducting.isEnabled && self.profileSettingsApplied)
                if !model.readPending { self.read(model) }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    private func receivePractice(_ data: Data) {
        guard let packet = BatonPracticePacket(data: data) else {
            stopConducting(reason: "Invalid baton practice response.")
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let fresh = lastPracticeReply.map { now - $0 <= 3 } ?? false
        lastPracticeReply = now
        batonPracticeState = packet.state
        let previous = holdSequence
        holdSequence = packet.holdSequence
        if fresh, let previous, previous != packet.holdSequence {
            // Multiple requests between polls cancel in pairs; never replay on connection.
            if (packet.holdSequence &- previous) % 2 == 1 {
                if conducting.isEnabled { stopConducting() }
                else if remotePracticeAllowed { setConductingMode(true) }
            }
        }
        guard packet.commandSequence == practiceCommandSequence else { return }
        if packet.state == .failed {
            stopConducting(reason: "The baton could not change its sensor sampling rate.")
            return
        }
        if packet.state == .calibrating, conducting.isEnabled {
            practiceConfirmed = false
            conducting.notificationState(ready: false, calibrating: true)
            // Calibration needs a still baton, not an arbitrary setup deadline.
            // The polling timeout and firmware lease still guard link failure.
            beatSubscriptionTimeout?.cancel()
        } else if packet.state == .active, conducting.isEnabled, profileSettingsApplied {
            practiceConfirmed = true
            updateConductingReadiness()
        } else if packet.state == .idle, practiceConfirmed, conducting.isEnabled {
            stopConducting(reason: "The baton returned to low-power idle. Start practice again.")
        }
    }

    private(set) var batonDeviceName: String?
    private(set) var isRenamingBaton = false
    private(set) var batonNameMessage: String?
    private(set) var batonNameError: String?
    @ObservationIgnored private var requestedBatonName: String?
    @ObservationIgnored private var nameConfirmation: Task<Void, Never>?

    let imuRecorder = IMURecorder()
    let conducting = ConductingController()
    let conductingProfiles = ConductingProfileStore()
    @ObservationIgnored private var pendingProfileSettings: Data?
    @ObservationIgnored private var profileSettingsApplied = false
    @ObservationIgnored private var lastConductingMotionLog: TimeInterval = 0
    @ObservationIgnored private var beatSubscriptionTimeout: Task<Void, Never>?
    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var connectionTimeout: Task<Void, Never>?
    @ObservationIgnored private var deviceIndices: [UUID: Int] = [:]

    override init() {
        super.init()
        imuRecorder.onEvent = { [weak self] message in self?.log(message) }
        central = CBCentralManager(delegate: self, queue: .main)
    }

    var batonMotionCharacteristic: BLECharacteristic? {
        services.flatMap(\.characteristics).first { $0.isBatonMotion }
    }

    var batonBeatCharacteristic: BLECharacteristic? {
        services.flatMap(\.characteristics).first { $0.isBatonBeat }
    }

    var batonSettingsCharacteristic: BLECharacteristic? {
        services.flatMap(\.characteristics).first { $0.isBatonSettings }
    }

    var batonNameCharacteristic: BLECharacteristic? {
        services.flatMap(\.characteristics).first { $0.isBatonName }
    }

    func renameBaton(_ input: String) {
        guard !isRenamingBaton else { return }
        batonNameError = nil
        batonNameMessage = nil
        guard !conducting.isEnabled else {
            batonNameError = "Stop practice before renaming your baton."
            return
        }
        guard let model = batonNameCharacteristic,
              let peripheral = usablePeripheral(for: model),
              model.characteristic.properties.contains([.read, .write]) else {
            batonNameError = "This baton needs the name-enabled firmware before its device name can be changed."
            return
        }
        guard !model.readPending, !model.writePending else {
            batonNameError = "A name request is still pending. Wait a moment and try again."
            return
        }
        do {
            let name = try BatonIdentity.validatedName(input)
            let data = Data(name.utf8)
            guard data.count <= peripheral.maximumWriteValueLength(for: .withResponse) else {
                batonNameError = "The connection cannot send this name. Reconnect and try again."
                return
            }
            requestedBatonName = name
            isRenamingBaton = true
            model.writePending = true
            model.error = nil
            peripheral.writeValue(data, for: model.characteristic, type: .withResponse)
            // Also covers a missing write ACK. No success is reported on ACK alone.
            nameConfirmation?.cancel()
            nameConfirmation = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                self?.finishNameRequest(error: "Could not confirm the saved name. Reconnect to check the baton before retrying.")
            }
        } catch { batonNameError = error.localizedDescription }
    }

    private func pollSavedName() {
        nameConfirmation?.cancel()
        nameConfirmation = Task { [weak self] in
            for _ in 0..<40 {
                guard let self, self.isRenamingBaton, let model = self.batonNameCharacteristic else { return }
                if !model.readPending { self.read(model) }
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
            self?.finishNameRequest(error: "Could not confirm the saved name. Reconnect to check the baton before retrying.")
        }
    }

    private func finishNameRequest(error: String? = nil) {
        nameConfirmation?.cancel()
        nameConfirmation = nil
        requestedBatonName = nil
        isRenamingBaton = false
        batonNameError = error
        batonNameMessage = error == nil ? "Name saved on your baton." : nil
    }

    private func receiveBatonName(_ data: Data) {
        do {
            let value = try BatonNameValue(data: data)
            if value.status == .saved {
                batonDeviceName = value.name
                activeDevice?.name = value.name
                if let id = activeDevice?.id, let index = deviceIndices[id] {
                    devices[index].name = value.name
                }
            }
            guard let requested = requestedBatonName else { return }
            if value.status == .failed {
                finishNameRequest(error: "The baton couldn't save the name. Its previous name is unchanged; try again.")
            } else if value.confirms(requested) {
                finishNameRequest()
            }
        } catch {
            if isRenamingBaton { finishNameRequest(error: error.localizedDescription) }
        }
    }

    func setConductingMode(_ enabled: Bool) {
        guard enabled else { stopConducting(); return }
        guard !conducting.isEnabled else { return }
        guard practiceCharacteristic == nil || lastPracticeReply != nil else {
            conducting.fail("Waiting for baton power status. Try Start Practice again in a moment.")
            return
        }
        practiceConfirmed = false
        guard !isRenamingBaton else {
            conducting.fail("Wait for your baton name to finish saving before starting practice.")
            return
        }
        guard isConnected, !isDisconnecting, let model = batonBeatCharacteristic,
              model.characteristic.properties.contains(.notify),
              let settings = batonSettingsCharacteristic,
              settings.characteristic.properties.contains([.read, .write]) else {
            conducting.fail("Profiles need updated baton firmware. Flash the profile-enabled build and reconnect.")
            return
        }
        guard !settings.writePending, !settings.readPending else {
            conducting.fail("A settings request is still pending. Wait or reconnect before trying again.")
            return
        }
        guard let profile = conductingProfiles.selected else {
            conducting.fail("Create and select a profile first.")
            return
        }
        if conducting.filterMode == .gesture {
            guard let motion = batonMotionCharacteristic,
                  motion.characteristic.properties.contains(.notify) else {
                conducting.fail("ML filtering needs motion notifications. Select Peak + strength or reconnect.")
                return
            }
        }
        conducting.start(profile: profile)
        guard conducting.isEnabled, let peripheral = usablePeripheral(for: settings) else { return }
        profileSettingsApplied = false
        let payload = ConductingSettingsPacket.encode(profile.sensitivity)
        pendingProfileSettings = payload
        settings.writePending = true
        settings.error = nil
        peripheral.writeValue(payload, for: settings.characteristic, type: .withResponse)
        if !model.isNotifying && !model.notificationPending { setNotifications(true, for: model) }
        if conducting.filterMode == .gesture, let motion = batonMotionCharacteristic,
           !motion.isNotifying && !motion.notificationPending { setNotifications(true, for: motion) }
        updateConductingReadiness()
        beatSubscriptionTimeout?.cancel()
        beatSubscriptionTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard let self, self.conducting.isEnabled, !self.conducting.isReady else { return }
            self.stopConducting()
            self.conducting.fail("Profile setup timed out. Reconnect and try again.")
        }
        log("Applying conducting profile: \(profile.name)")
    }

    private func updateConductingReadiness() {
        let motionReady = conducting.filterMode != .gesture ||
            (batonMotionCharacteristic?.isNotifying == true && batonMotionCharacteristic?.notificationPending == false)
        let ready = (practiceCharacteristic == nil || practiceConfirmed) && motionReady && profileSettingsApplied && batonBeatCharacteristic?.isNotifying == true
            && batonBeatCharacteristic?.notificationPending == false
        conducting.notificationState(ready: ready, calibrating: batonPracticeState == .calibrating)
        if ready { beatSubscriptionTimeout?.cancel() }
    }

    func stopConducting(reason: String = "Conducting Mode is off.") {
        practiceConfirmed = false
        if practiceCommandActive { writePractice(false) }
        beatSubscriptionTimeout?.cancel()
        beatSubscriptionTimeout = nil
        pendingProfileSettings = nil
        profileSettingsApplied = false
        conducting.stop(reason: reason)
    }

    var bluetoothStatus: String {
        switch bluetoothState {
        case .poweredOn: "Bluetooth is on"
        case .poweredOff: "Bluetooth is off. Turn it on to scan."
        case .unauthorized: "Bluetooth access denied. Allow access in Settings."
        case .unsupported: "Bluetooth Low Energy is unavailable on this device."
        case .resetting: "Bluetooth is resetting. Please wait."
        case .unknown: "Checking Bluetooth availability…"
        @unknown default: "Bluetooth is unavailable."
        }
    }

    func startScanning(serviceUUIDs: [String]? = nil) {
        guard bluetoothState == .poweredOn, activeDevice == nil else { return }
        devices.removeAll()
        deviceIndices.removeAll()
        errorMessage = nil
        central.scanForPeripherals(withServices: serviceUUIDs?.map { CBUUID(string: $0) }, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
        log("Scanning started")
    }

    func stopScanning() {
        guard isScanning else { return }
        central.stopScan()
        isScanning = false
        log("Scanning stopped")
    }

    func connect(to device: BLEDevice) {
        guard bluetoothState == .poweredOn, activeDevice == nil, device.isConnectable else { return }
        stopScanning()
        errorMessage = nil
        services.removeAll()
        batonDeviceName = nil
        batonNameMessage = nil
        batonNameError = nil
        activeDevice = device
        device.peripheral.delegate = self
        log("Connecting to \(device.name)…")
        central.connect(device.peripheral)
        connectionTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, !self.isConnected, !self.isDisconnecting, self.activeDevice != nil else { return }
            self.report("Connection timed out. Make sure the device is advertising and try again.")
            self.disconnect()
        }
    }

    func disconnect() {
        guard let device = activeDevice, !isDisconnecting else { return }
        connectionTimeout?.cancel()
        stopConducting(reason: "Device disconnecting.")
        imuRecorder.stop(reason: "Disconnect requested")
        isDisconnecting = true
        log(isConnected ? "Disconnecting from \(device.name)…" : "Cancelling connection to \(device.name)…")
        central.cancelPeripheralConnection(device.peripheral)
    }

    func read(_ model: BLECharacteristic) {
        guard let peripheral = usablePeripheral(for: model), model.characteristic.properties.contains(.read), !model.readPending else { return }
        model.error = nil
        model.readPending = true
        log("Read requested [\(model.characteristic.uuid)]")
        peripheral.readValue(for: model.characteristic)
    }

    func setNotifications(_ enabled: Bool, for model: BLECharacteristic) {
        guard let peripheral = usablePeripheral(for: model), supportsNotifications(model.characteristic.properties), !model.notificationPending else { return }
        model.error = nil
        model.notificationPending = true
        if !enabled, model.isBatonBeat { stopConducting(reason: "Beat notifications disabled.") }
        if !enabled, model.isBatonMotion { imuRecorder.stop(reason: "Motion notifications disabled") }
        log("Notifications \(enabled ? "enable" : "disable") requested [\(model.characteristic.uuid)]")
        peripheral.setNotifyValue(enabled, for: model.characteristic)
    }

    func write(_ data: Data, to model: BLECharacteristic, type: CBCharacteristicWriteType) {
        guard let peripheral = usablePeripheral(for: model), !model.writePending else { return }
        let required: CBCharacteristicProperties = type == .withResponse ? .write : .writeWithoutResponse
        guard model.characteristic.properties.contains(required) else { return }
        let limit = peripheral.maximumWriteValueLength(for: type)
        guard data.count <= limit else {
            characteristicError("Write is \(data.count) bytes; this connection allows at most \(limit) bytes per write.", model)
            return
        }
        guard type != .withoutResponse || peripheral.canSendWriteWithoutResponse else {
            characteristicError("The write buffer is full. Try again shortly.", model)
            return
        }
        if model.isBatonSettings { stopConducting(reason: "Settings changed. Enable your profile again to continue.") }
        model.error = nil
        model.writePending = type == .withResponse
        log("TX [\(model.characteristic.uuid)] \(type == .withResponse ? "with response" : "without response (unacknowledged)"): \(hexString(from: data))")
        peripheral.writeValue(data, for: model.characteristic, type: type)
    }

    func setMotionParsing(_ enabled: Bool, for model: BLECharacteristic) {
        guard model.isBatonMotion else { return }
        model.isMotionParsingEnabled = enabled
        model.updateValue(model.value)
        log("Baton motion parsing \(enabled ? "enabled" : "disabled") [\(model.characteristic.uuid)]")
        if let packet = model.motionPacket { log(packet.logSummary) }
        else if let error = model.motionDecodeError { log("DECODE ERROR: \(error)") }
    }

    func startIMURecording(duration: TimeInterval) {
        guard isConnected, !isDisconnecting, let device = activeDevice,
              let model = batonMotionCharacteristic else {
            report("Connect to the baton motion service before recording.")
            return
        }
        guard model.isNotifying, !model.notificationPending else {
            report("Enable motion Notifications and wait for confirmation before recording.")
            return
        }
        do {
            try imuRecorder.start(duration: duration, metadata: IMURecordingMetadata(
                deviceID: device.id.uuidString, deviceName: device.name,
                serviceUUID: model.characteristic.service?.uuid.uuidString ?? BatonMotionPacket.serviceUUID,
                characteristicUUID: model.characteristic.uuid.uuidString))
        } catch { report("Could not start recording: \(error.localizedDescription)") }
    }

    func clearLogs() { logs.removeAll() }

    private func log(_ message: String) {
        logs.append(BLELogEntry(message: message))
        // Keep sustained motion streams from growing memory indefinitely.
        if logs.count > 1000 { logs.removeFirst(logs.count - 1000) }
    }

    private func report(_ message: String) {
        errorMessage = message
        log("ERROR: \(message)")
    }

    private func characteristicError(_ message: String, _ model: BLECharacteristic) {
        model.error = message
        report("[\(model.characteristic.uuid)] \(message)")
    }

    private func usablePeripheral(for model: BLECharacteristic) -> CBPeripheral? {
        guard isConnected, !isDisconnecting,
              services.contains(where: { $0.characteristics.contains(where: { $0 === model }) }) else { return nil }
        return activeDevice?.peripheral
    }

    private func model(for characteristic: CBCharacteristic) -> BLECharacteristic? {
        services.flatMap(\.characteristics).first { $0.characteristic === characteristic }
    }

    private func resetConnection() {
        batteryPolling?.cancel()
        batteryPolling = nil
        batteryPercentage = nil
        practicePolling?.cancel()
        practicePolling = nil
        lastPracticeReply = nil
        batonPracticeState = nil
        holdSequence = nil
        practiceConfirmed = false
        if isRenamingBaton { finishNameRequest(error: "Disconnected before the saved name was confirmed. Reconnect to check the baton name.") }
        batonDeviceName = nil
        stopConducting()
        conducting.resetConnection()
        imuRecorder.stop(reason: "Device disconnected")
        connectionTimeout?.cancel()
        connectionTimeout = nil
        activeDevice?.peripheral.delegate = nil
        activeDevice = nil
        isConnected = false
        isDisconnecting = false
        isDiscoveringServices = false
        services.removeAll()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        log(bluetoothStatus)
        if central.state != .poweredOn {
            stopScanning()
            if activeDevice != nil {
                report("Connection ended: \(bluetoothStatus)")
                resetConnection()
            }
            devices.removeAll()
            deviceIndices.removeAll()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard isScanning else { return }
        let previous = deviceIndices[peripheral.identifier].map { devices[$0] }
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        // Individual advertising packets may omit the name and service list.
        // Retain metadata learned from earlier packets for this peripheral UUID.
        let name = [advertisedName, previous.flatMap { $0.hasKnownName ? $0.name : nil }, peripheral.name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let advertisedServices = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            + (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? [])
        let serviceUUIDs = Set((previous?.advertisedServiceUUIDs ?? []) + advertisedServices.map(\.uuidString))
        let device = BLEDevice(peripheral: peripheral, name: name ?? "Unknown Device",
                               hasKnownName: name != nil, advertisedServiceUUIDs: serviceUUIDs.sorted(),
                               rssi: RSSI.intValue,
                               isConnectable: (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
                                   ?? previous?.isConnectable ?? true)
        if let index = deviceIndices[device.id] {
            if device.name != devices[index].name { log("Device name updated: \(device.name) [\(device.id)]") }
            devices[index] = device
        } else {
            deviceIndices[device.id] = devices.count
            devices.append(device)
            log("Found \(device.name) RSSI \(RSSI.intValue)")
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral.identifier == activeDevice?.id else { return }
        connectionTimeout?.cancel()
        if isDisconnecting { central.cancelPeripheralConnection(peripheral); return }
        isConnected = true
        log("Connected to \(activeDevice?.name ?? "device")")
        discoverServices(peripheral)
    }

    private func discoverServices(_ peripheral: CBPeripheral) {
        isDiscoveringServices = true
        log("Discovering services…")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == activeDevice?.id else { return }
        if isDisconnecting {
            log("Connection cancelled")
        } else {
            report("Connection failed: \(error?.localizedDescription ?? "Unknown error")")
        }
        resetConnection()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == activeDevice?.id else { return }
        let wasRequested = isDisconnecting
        log("Disconnected from \(activeDevice?.name ?? "device")")
        if let error { report("Disconnected: \(error.localizedDescription)") }
        else if !wasRequested { report("The device disconnected unexpectedly. Scan again to reconnect.") }
        resetConnection()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral.identifier == activeDevice?.id, !isDisconnecting else { return }
        isDiscoveringServices = false
        if let error { report("Service discovery failed: \(error.localizedDescription)"); return }
        services = (peripheral.services ?? []).map(BLEService.init)
        if services.isEmpty { log("No GATT services found") }
        for model in services {
            log("Service discovered: \(model.service.uuid)")
            peripheral.discoverCharacteristics(nil, for: model.service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let serviceModel = services.first(where: { $0.service === service }), !isDisconnecting else { return }
        serviceModel.isDiscovering = false
        if let error {
            serviceModel.error = error.localizedDescription
            report("Characteristic discovery [\(service.uuid)] failed: \(error.localizedDescription)")
            return
        }
        serviceModel.characteristics = (service.characteristics ?? []).map(BLECharacteristic.init)
        for model in serviceModel.characteristics {
            if service.uuid == CBUUID(string: "180F"),
               model.characteristic.uuid == CBUUID(string: "2A19"),
               model.characteristic.properties.contains(.read) { startBatteryPolling(model) }

            log("Characteristic discovered [\(service.uuid)]: \(model.characteristic.uuid)")
            if model.isBatonName, model.characteristic.properties.contains(.read) { read(model) }
            if model.isBatonPractice, model.characteristic.properties.contains([.read, .write]) {
                startPracticePolling()
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let receivedAt = Date()
        let receivedUptime = ProcessInfo.processInfo.systemUptime
        guard let model = model(for: characteristic) else { return }
        model.readPending = false
        if characteristic.service?.uuid == CBUUID(string: "180F"),
           characteristic.uuid == CBUUID(string: "2A19") {
            if error == nil, let data = characteristic.value, data.count == 1,
               let value = data.first, value <= 100 { batteryPercentage = Int(value) }
            else { batteryPercentage = nil }
            if error != nil { return } // An unavailable battery must not interrupt practice.
        }
        if let error {
            if model.isBatonPractice { stopConducting(reason: "Baton control failed: \(error.localizedDescription)") }
            if model.isBatonName, isRenamingBaton { finishNameRequest(error: error.localizedDescription) }
            if model.isBatonSettings, pendingProfileSettings != nil {
                stopConducting()
                conducting.fail("Could not verify the baton settings: \(error.localizedDescription)")
            }
            characteristicError("Value update failed: \(error.localizedDescription)", model)
            return
        }
        model.error = nil
        model.updateValue(characteristic.value)
        if model.isBatonName, let data = characteristic.value { receiveBatonName(data) }
        if model.isBatonPractice, let data = characteristic.value { receivePractice(data) }
        if model.isBatonSettings, let expected = pendingProfileSettings, conducting.isEnabled {
            pendingProfileSettings = nil
            if characteristic.value == expected {
                profileSettingsApplied = true
                writePractice(true)
                updateConductingReadiness()
                log("Conducting sensitivity confirmed by baton")
            } else {
                stopConducting()
                conducting.fail("The baton did not confirm the selected sensitivity. Reconnect and try again.")
            }
        }
        if let data = characteristic.value {
            if model.isBatonBeat {
                do {
                    let beat = try BatonBeatPacket(data: data)
                    if model.isNotifying { conducting.receive(beat, receivedAt: receivedUptime) }
                    log("BEAT seq=\(beat.sequence) t=\(beat.uptimeMilliseconds) strength=\(beat.strength)")
                } catch { log("BEAT DECODE ERROR: \(error.localizedDescription)") }
            }
            if model.isBatonMotion {
                imuRecorder.receive(data, at: receivedAt, uptime: receivedUptime)
                if model.isNotifying, let packet = try? BatonMotionPacket(data: data) {
                    conducting.receiveMotion(packet, receivedAt: receivedUptime)
                }
            }
            // Keep every motion sample for ML/history/recording, but avoid dozens
            // of terminal strings and UI mutations per second during playback.
            if model.isBatonMotion && conducting.isEnabled {
                if receivedUptime - lastConductingMotionLog < 1 { return }
                lastConductingMotionLog = receivedUptime
            }
            log("RX [\(characteristic.uuid)]: \(data.isEmpty ? "(empty)" : hexString(from: data))")
        } else { log("RX [\(characteristic.uuid)]: no value") }
        if let packet = model.motionPacket {
            log(packet.logSummary)
        } else if let error = model.motionDecodeError {
            log("DECODE ERROR [\(characteristic.uuid)]: \(error)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard let model = model(for: characteristic) else { return }
        model.notificationPending = false
        model.isNotifying = characteristic.isNotifying
        if model.isBatonMotion, !model.isNotifying { imuRecorder.stop(reason: "Motion notifications ended") }
        if model.isBatonMotion, conducting.isEnabled, conducting.filterMode == .gesture {
            if let error { stopConducting(); conducting.fail("Motion notifications failed: \(error.localizedDescription)") }
            else if !model.isNotifying { stopConducting(reason: "Motion notifications ended. Enable Conducting Mode to retry.") }
            else { updateConductingReadiness() }
        }
        if model.isBatonBeat {
            if let error { conducting.fail("Beat notifications failed: \(error.localizedDescription)") }
            else if !model.isNotifying { stopConducting(reason: "Beat notifications ended.") }
            else { updateConductingReadiness() }
        }
        if let error { characteristicError("Notification change failed: \(error.localizedDescription)", model); return }
        model.error = nil
        log("Notifications \(characteristic.isNotifying ? "enabled" : "disabled") [\(characteristic.uuid)]")
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let model = model(for: characteristic) else { return }
        model.writePending = false
        if let error {
            if model.isBatonPractice { stopConducting(reason: "Baton control failed: \(error.localizedDescription)") }
            if model.isBatonName, isRenamingBaton { finishNameRequest(error: error.localizedDescription) }
            if model.isBatonSettings, pendingProfileSettings != nil {
                stopConducting()
                conducting.fail("The baton rejected the profile: \(error.localizedDescription)")
            }
            characteristicError("Write failed: \(error.localizedDescription)", model)
            return
        }
        if model.isBatonPractice, !conducting.isEnabled, practiceCommandActive { writePractice(false) }
        if model.isBatonName, requestedBatonName != nil { pollSavedName() }
        if model.isBatonSettings, pendingProfileSettings != nil, conducting.isEnabled {
            // Write acknowledgement alone is not enough; verify the stored setting.
            read(model)
        }
        model.error = nil
        log("Write acknowledged [\(characteristic.uuid)]")
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard peripheral.identifier == activeDevice?.id, !isDisconnecting else { return }
        if isRenamingBaton { finishNameRequest(error: "Baton services changed. Reconnect before renaming.") }
        batonDeviceName = nil
        stopConducting(reason: "Baton services changed. Enable the mode after discovery finishes.")
        conducting.resetConnection()
        imuRecorder.stop(reason: "GATT services changed")
        log("GATT services changed; rediscovering")
        services.removeAll()
        discoverServices(peripheral)
    }
}
