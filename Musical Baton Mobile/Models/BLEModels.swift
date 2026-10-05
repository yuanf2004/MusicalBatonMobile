import CoreBluetooth
import Foundation
import Observation

struct BLEDevice: Identifiable {
    var id: UUID { peripheral.identifier }
    let peripheral: CBPeripheral
    var name: String
    var hasKnownName: Bool
    var advertisedServiceUUIDs: [String]
    var rssi: Int
    var isConnectable: Bool
}

@Observable
final class BLEService: Identifiable {
    let id = UUID()
    let service: CBService
    var characteristics: [BLECharacteristic] = []
    var isDiscovering = true
    var error: String?

    init(_ service: CBService) { self.service = service }
}

@Observable
final class BLECharacteristic: Identifiable {
    let id = UUID()
    let characteristic: CBCharacteristic
    var value: Data?
    var isMotionParsingEnabled = false
    var motionPacket: BatonMotionPacket?
    var motionDecodeError: String?
    var motionHistory = MotionHistory()
    var isNotifying = false
    var notificationPending = false
    var readPending = false
    var writePending = false
    var error: String?

    init(_ characteristic: CBCharacteristic) {
        self.characteristic = characteristic
        isNotifying = characteristic.isNotifying
        updateValue(characteristic.value)
    }

    var isBatonMotion: Bool {
        BatonMotionPacket.matches(serviceUUID: characteristic.service?.uuid.uuidString,
                                  characteristicUUID: characteristic.uuid.uuidString)
    }

    func updateValue(_ data: Data?) {
        value = data
        motionPacket = nil
        motionDecodeError = nil
        guard isBatonMotion, isMotionParsingEnabled else {
            motionHistory = MotionHistory()
            return
        }
        guard let data else { return }
        do {
            let packet = try BatonMotionPacket(data: data)
            motionPacket = packet
            motionHistory.append(packet)
        } catch { motionDecodeError = error.localizedDescription }
    }
}

struct BLELogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let message: String
}
