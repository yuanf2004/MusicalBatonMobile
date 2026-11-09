import CoreBluetooth
import Foundation
import Observation

@MainActor
@Observable
final class ProductSession {
    let manager = BLEManager()
    let preferences = ProductPreferences()
    private(set) var notice: String?
    private(set) var scanStarted: TimeInterval?
    private(set) var connectedAt: TimeInterval?
    private(set) var lastMotionAt: TimeInterval?
    private(set) var now = ProcessInfo.processInfo.systemUptime
    @ObservationIgnored private var telemetryRequests = Set<UUID>()

    var deviceName: String {
        guard let d = manager.activeDevice else { return "Your baton" }
        return preferences.name(id: d.id, fallback: d.name)
    }
    var motionIsFresh: Bool { lastMotionAt.map { now - $0 < 3 } ?? false }
    var connectionRemaining: Int? {
        guard let start = connectedAt, preferences.connectionSeconds > 0 else { return nil }
        return max(0, preferences.connectionSeconds - Int(now - start))
    }

    func startScanning() {
        notice = nil
        manager.startScanning(serviceUUIDs: [BatonMotionPacket.serviceUUID])
        scanStarted = manager.isScanning ? ProcessInfo.processInfo.systemUptime : nil
    }
    func stopScanning() { manager.stopScanning(); scanStarted = nil }
    func connect(_ device: BLEDevice) {
        notice = nil
        scanStarted = nil
        manager.connect(to: device)
    }
    func connectionChanged() {
        now = ProcessInfo.processInfo.systemUptime
        connectedAt = manager.isConnected ? now : nil
        lastMotionAt = nil
        telemetryRequests.removeAll()
    }
    func motionReceived() {
        guard manager.isConnected, let data = manager.batonMotionCharacteristic?.value,
              let p = try? BatonMotionPacket(data: data), p.accelerationValid, p.gyroscopeValid else { return }
        lastMotionAt = ProcessInfo.processInfo.systemUptime
    }
    func tick() {
        now = ProcessInfo.processInfo.systemUptime
        if manager.isScanning && ConnectionTimePolicy.expired(start: scanStarted, now: now, limit: preferences.scanSeconds) {
            stopScanning()
            notice = "Search finished. Triple-press your baton and search again if it didn't appear."
        }
        if manager.isConnected && !manager.isDisconnecting &&
            ConnectionTimePolicy.expired(start: connectedAt, now: now, limit: preferences.connectionSeconds) {
            notice = "Your connection time limit was reached. Reconnect whenever you're ready."
            manager.disconnect()
        }
        prepareMotionHealth()
        prepareDeviceInformation()
    }
    private func prepareDeviceInformation() {
        guard manager.isConnected, !manager.isDisconnecting else { return }
        for model in manager.services.filter({ $0.service.uuid == CBUUID(string: "180A") }).flatMap(\.characteristics) {
            guard ["2A25", "2A26", "2A27"].contains(model.characteristic.uuid.uuidString),
                  model.characteristic.properties.contains(.read), !model.readPending,
                  !telemetryRequests.contains(model.id) else { continue }
            telemetryRequests.insert(model.id)
            manager.read(model)
        }
    }
    private func prepareMotionHealth() {
        guard manager.isConnected, !manager.isDisconnecting,
              let motion = manager.batonMotionCharacteristic,
              !telemetryRequests.contains(motion.id), !motion.notificationPending else { return }
        guard motion.characteristic.properties.contains(.notify) else { return }
        telemetryRequests.insert(motion.id)
        if !motion.isNotifying { manager.setNotifications(true, for: motion) }
    }
}
