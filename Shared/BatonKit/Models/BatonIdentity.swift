import Foundation

/// Service UUID identifies the baton product type; a peripheral UUID identifies an individual baton.
nonisolated enum BatonIdentity {
    static let serviceUUID = BatonMotionPacket.serviceUUID
    static let nameCharacteristicUUID = "12345678-1234-5678-1234-56789ABCDEF4"
    static let maximumNameBytes = 20

    static func matchesName(serviceUUID: String?, characteristicUUID: String) -> Bool {
        serviceUUID?.uppercased() == self.serviceUUID && characteristicUUID.uppercased() == nameCharacteristicUUID
    }

    static func validatedName(_ input: String) throws -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= maximumNameBytes,
              !input.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0.value == 0x2028 || $0.value == 0x2029 }) else {
            throw NameError.invalid
        }
        return name
    }

    enum NameError: LocalizedError {
        case invalid, invalidResponse
        var errorDescription: String? {
            switch self {
            case .invalid: "Use a name of 1–20 UTF-8 bytes, without control characters. Emoji and accented letters can use more than one byte."
            case .invalidResponse: "The baton returned an unsupported name response."
            }
        }
    }
}

nonisolated struct BatonNameValue: Equatable {
    enum Status: UInt8 { case saved = 0, saving = 1, failed = 2 }
    let status: Status
    let name: String

    init(data: Data) throws {
        let bytes = Array(data)
        guard bytes.count >= 3, bytes.count <= BatonIdentity.maximumNameBytes + 2,
              bytes[0] == 1, let status = Status(rawValue: bytes[1]),
              let name = String(bytes: bytes.dropFirst(2), encoding: .utf8),
              (try? BatonIdentity.validatedName(name)) == name else {
            throw BatonIdentity.NameError.invalidResponse
        }
        self.status = status
        self.name = name
    }

    /// A write ACK accepts a request; only a saved-state readback confirms persistence.
    func confirms(_ requested: String) -> Bool { status == .saved && name == requested }
}
