import Foundation

@main
struct BatonIdentityChecks {
    static func main() throws {
        for name in ["Smart Baton", "Orchestra 2", "12345678901234567890", "Bâton", "🎵 Baton"] {
            let trimmed = try BatonIdentity.validatedName("  " + name + "  ")
            precondition(trimmed == name)
            let value = try BatonNameValue(data: Data([1, 0]) + Data(name.utf8))
            precondition(value.confirms(name))
            precondition(!value.confirms("Other baton"))
        }
        for name in ["", "  ", String(repeating: "a", count: 21), String(repeating: "🎵", count: 6), "a\nb", "a\u{7f}", "a\u{85}", "a\u{2028}b"] {
            precondition((try? BatonIdentity.validatedName(name)) == nil)
        }
        let saved = try BatonNameValue(data: Data([1,0]) + Data("New baton".utf8))
        let saving = try BatonNameValue(data: Data([1,1]) + Data("Old baton".utf8))
        let failed = try BatonNameValue(data: Data([1,2]) + Data("Old baton".utf8))
        precondition(saved.confirms("New baton"))
        precondition(!saving.confirms("Old baton") && !failed.confirms("Old baton"))
        var prefixed = Data([0xff]); prefixed.append(Data([1,0]) + Data("Baton".utf8))
        let sliced = try BatonNameValue(data: prefixed.dropFirst())
        precondition(sliced.name == "Baton")
        for bytes in [[UInt8](), [1,0], [2,0,65], [1,3,65], [1,0,0], [1,0,0xff], [1,0,0xc0,0xaf], [1,0,32,65], [1,0]+Array(repeating:65,count:21)] {
            precondition((try? BatonNameValue(data: Data(bytes))) == nil)
        }
        precondition(BatonIdentity.matchesName(serviceUUID: BatonIdentity.serviceUUID.lowercased(), characteristicUUID: BatonIdentity.nameCharacteristicUUID.lowercased()))
        precondition(!BatonIdentity.matchesName(serviceUUID: "180F", characteristicUUID: BatonIdentity.nameCharacteristicUUID))
        precondition(BatonIdentity.serviceUUID == BatonMotionPacket.serviceUUID)
        print("Baton identity, UTF-8 name limits, saved/pending/failure verification, slices and malformed packet checks passed")
    }
}
