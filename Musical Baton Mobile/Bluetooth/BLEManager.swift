import CoreBluetooth
import Foundation
import Observation

// CoreBluetooth delivers all delegates on the main queue supplied below.
@MainActor
@Observable
final class BLEManager: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
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
    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var connectionTimeout: Task<Void, Never>?
    @ObservationIgnored private var deviceIndices: [UUID: Int] = [:]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    var batonMotionCharacteristic: BLECharacteristic? {
        services.flatMap(\.characteristics).first { $0.isBatonMotion }
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

    func startScanning() {
        guard bluetoothState == .poweredOn, activeDevice == nil else { return }
        devices.removeAll()
        deviceIndices.removeAll()
        errorMessage = nil
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
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
            log("Characteristic discovered [\(service.uuid)]: \(model.characteristic.uuid)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let model = model(for: characteristic) else { return }
        model.readPending = false
        if let error { characteristicError("Value update failed: \(error.localizedDescription)", model); return }
        model.error = nil
        model.updateValue(characteristic.value)
        if let data = characteristic.value {
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
        if let error { characteristicError("Notification change failed: \(error.localizedDescription)", model); return }
        model.error = nil
        log("Notifications \(characteristic.isNotifying ? "enabled" : "disabled") [\(characteristic.uuid)]")
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let model = model(for: characteristic) else { return }
        model.writePending = false
        if let error { characteristicError("Write failed: \(error.localizedDescription)", model); return }
        model.error = nil
        log("Write acknowledged [\(characteristic.uuid)]")
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard peripheral.identifier == activeDevice?.id, !isDisconnecting else { return }
        log("GATT services changed; rediscovering")
        services.removeAll()
        discoverServices(peripheral)
    }
}
