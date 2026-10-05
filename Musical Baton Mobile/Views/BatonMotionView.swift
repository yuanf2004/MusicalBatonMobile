import SwiftUI

struct BatonMotionView: View {
    let packet: BatonMotionPacket

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Baton Motion · v\(packet.version)").font(.subheadline.bold())
            Text("Sequence: \(packet.sequence)")
            Text("Device uptime: \(packet.uptimeMilliseconds) ms")
            Text("Flags: 0x\(String(format: "%02X", packet.flags))")
            Text("Time synchronized: \(packet.timeSynchronized ? "Yes" : "No")")
            Text("Acceleration (mg) · \(packet.accelerationValid ? "Valid" : "Invalid")").bold()
            Text(packet.accelerationValid ? packet.acceleration.milligravityText : "No valid acceleration in this packet")
                .foregroundStyle(packet.accelerationValid ? Color.primary : Color.secondary)
            Text("Gyroscope (°/s) · \(packet.gyroscopeValid ? "Valid" : "Invalid")").bold()
            Text(packet.gyroscopeValid ? packet.gyroscope.degreesPerSecondText : "No valid gyroscope in this packet")
                .foregroundStyle(packet.gyroscopeValid ? Color.primary : Color.secondary)
            if packet.unknownFlags != 0 {
                Text("Unrecognized flag bits: 0x\(String(format: "%02X", packet.unknownFlags))")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption.monospaced())
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
