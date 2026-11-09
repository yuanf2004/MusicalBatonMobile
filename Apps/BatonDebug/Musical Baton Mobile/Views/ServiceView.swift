import CoreBluetooth
import SwiftUI

struct ServiceView: View {
    let manager: BLEManager
    let service: BLEService
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if service.isDiscovering {
                ProgressView("Discovering characteristics…")
            } else if let error = service.error {
                Text(error).foregroundStyle(.red)
            } else if service.characteristics.isEmpty {
                Text("No characteristics found").foregroundStyle(.secondary)
            }
            ForEach(service.characteristics) { characteristic in
                CharacteristicView(manager: manager, model: characteristic)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(knownUUIDName(service.service.uuid) ?? "Service").font(.headline)
                Text(service.service.uuid.uuidString)
                    .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
}
