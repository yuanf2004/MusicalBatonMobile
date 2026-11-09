import CoreBluetooth
import SwiftUI

struct CharacteristicView: View {
    let manager: BLEManager
    let model: BLECharacteristic
    @State private var writeInput = ""
    @State private var inputFormat: InputFormat = .hex
    @State private var withoutResponse = false
    @State private var inputError: String?

    private enum InputFormat: String, CaseIterable { case hex = "HEX", utf8 = "UTF-8" }
    private var properties: CBCharacteristicProperties { model.characteristic.properties }
    private var canWrite: Bool { properties.contains(.write) || properties.contains(.writeWithoutResponse) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(knownUUIDName(model.characteristic.uuid) ?? "Characteristic").font(.subheadline.bold())
            Text(model.characteristic.uuid.uuidString).font(.caption.monospaced()).textSelection(.enabled)
            Text("Properties: \(propertyNames(properties).joined(separator: ", "))")
                .font(.caption).foregroundStyle(.secondary)
            if let data = model.value {
                valueLabel("HEX (\(data.count) bytes)", data.isEmpty ? "(empty)" : hexString(from: data))
                valueLabel("UTF-8", String(data: data, encoding: .utf8).map { $0.isEmpty ? "(empty)" : $0 } ?? "Not valid UTF-8")
            } else {
                Text("No value received yet").font(.caption).foregroundStyle(.secondary)
            }
            if properties.contains(.read) {
                Button(model.readPending ? "Reading…" : "Read") { manager.read(model) }
                    .buttonStyle(.bordered).disabled(model.readPending)
            }
            if supportsNotifications(properties) {
                Toggle("Notifications: \(model.isNotifying ? "ON" : "OFF")", isOn: Binding(
                    get: { model.isNotifying },
                    set: { manager.setNotifications($0, for: model) }
                ))
                .font(.subheadline)
                .disabled(model.notificationPending)
                if model.notificationPending { ProgressView("Updating notifications…").font(.caption) }
            }
            if model.isBatonMotion {
                Toggle("Live motion parsing", isOn: Binding(
                    get: { model.isMotionParsingEnabled },
                    set: { manager.setMotionParsing($0, for: model) }
                ))
                .font(.subheadline)
                Text("Decode received values on this iPhone.").font(.caption).foregroundStyle(.secondary)
                if let packet = model.motionPacket {
                    BatonMotionView(packet: packet)
                } else if let error = model.motionDecodeError {
                    Text("Baton packet: \(error)").font(.caption).foregroundStyle(.orange)
                } else if model.isMotionParsingEnabled {
                    Text("Waiting for a motion value. Enable Notifications or tap Read.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if canWrite {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Write Value").font(.caption.bold())
                    Picker("Input format", selection: $inputFormat) {
                        ForEach(InputFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    TextField(inputFormat == .hex ? "01 FF 03" : "Text to send", text: $writeInput)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if properties.contains(.write) && properties.contains(.writeWithoutResponse) {
                        Toggle("Without response", isOn: $withoutResponse).font(.caption)
                    }
                    Button(model.writePending ? "Writing…" : "Write") { sendWrite() }
                        .buttonStyle(.bordered)
                        .disabled(writeInput.isEmpty || model.writePending)
                    if let inputError { Text(inputError).font(.caption).foregroundStyle(.red) }
                }
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(.vertical, 8)
    }

    private func valueLabel(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            Text(value).font(.caption.monospaced()).textSelection(.enabled)
        }
    }

    private func sendWrite() {
        do {
            let data = try inputFormat == .hex ? dataFromHex(writeInput) : Data(writeInput.utf8)
            inputError = nil
            let type: CBCharacteristicWriteType = !properties.contains(.write) || withoutResponse ? .withoutResponse : .withResponse
            manager.write(data, to: model, type: type)
        } catch { inputError = error.localizedDescription }
    }
}
