import CoreBluetooth
import Foundation

func hexString(from data: Data) -> String {
    data.map { String(format: "%02X", $0) }.joined(separator: " ")
}

func dataFromHex(_ input: String) throws -> Data {
    let compact = input.filter { !$0.isWhitespace }
    guard !compact.isEmpty, compact.count.isMultiple(of: 2),
          compact.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
        throw HexInputError.invalid
    }
    var bytes: [UInt8] = []
    var index = compact.startIndex
    while index < compact.endIndex {
        let end = compact.index(index, offsetBy: 2)
        guard let byte = UInt8(compact[index..<end], radix: 16) else {
            throw HexInputError.invalid
        }
        bytes.append(byte)
        index = end
    }
    return Data(bytes)
}

enum HexInputError: LocalizedError {
    case invalid
    var errorDescription: String? {
        "Enter complete hexadecimal bytes, such as 01 FF 03 (with or without spaces)."
    }
}

func propertyNames(_ properties: CBCharacteristicProperties) -> [String] {
    let names: [(CBCharacteristicProperties, String)] = [
        (.read, "Read"), (.write, "Write"),
        (.writeWithoutResponse, "Write Without Response"),
        (.notify, "Notify"), (.indicate, "Indicate"),
        (.broadcast, "Broadcast"),
        (.authenticatedSignedWrites, "Authenticated Signed Writes"),
        (.extendedProperties, "Extended Properties"),
        (.notifyEncryptionRequired, "Notify Encryption Required"),
        (.indicateEncryptionRequired, "Indicate Encryption Required")
    ]
    return names.compactMap { properties.contains($0.0) ? $0.1 : nil }
}

func supportsNotifications(_ properties: CBCharacteristicProperties) -> Bool {
    !properties.intersection([.notify, .indicate, .notifyEncryptionRequired, .indicateEncryptionRequired]).isEmpty
}

func knownUUIDName(_ uuid: CBUUID) -> String? {
    switch uuid.uuidString.uppercased() {
    case BatonMotionPacket.serviceUUID: "Smart Baton Motion Service"
    case BatonMotionPacket.characteristicUUID: "Baton Motion"
    case "1800": "Generic Access"
    case "1801": "Generic Attribute"
    case "180A": "Device Information"
    case "180F": "Battery Service"
    case "1812": "Human Interface Device"
    case "2A00": "Device Name"
    case "2A01": "Appearance"
    case "2A05": "Service Changed"
    case "2A19": "Battery Level"
    case "2A24": "Model Number"
    case "2A25": "Serial Number"
    case "2A26": "Firmware Revision"
    case "2A27": "Hardware Revision"
    case "2A28": "Software Revision"
    case "2A29": "Manufacturer Name"
    default: nil
    }
}
