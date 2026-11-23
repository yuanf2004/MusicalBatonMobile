import Foundation
import Observation

@MainActor @Observable
final class BluetoothEvaluation {
    struct Row {
        let kind: String
        let phone: Double
        let device: UInt32?
        let sequence: UInt16?
        let gap: Int
        let status: String
        let milliseconds: Double?
    }

    private(set) var rows: [Row] = []
    private(set) var running = false
    private(set) var title = ""
    private var start = 0.0
    private var previous: (UInt16, Double)?

    func begin(_ title: String, at time: Double = ProcessInfo.processInfo.systemUptime) {
        rows.removeAll()
        previous = nil
        self.title = title
        start = time
        running = true
    }

    func stop() { running = false }
    func subscriptionEnded() { previous = nil }

    func receive(sequence: UInt16, device: UInt32, at time: Double) {
        guard running else { return }
        var status = "first"
        var gap = 0
        var interval: Double?
        if let (last, received) = previous {
            let delta = sequence &- last
            switch delta {
            case 0: status = "duplicate"
            case 1..<32768:
                status = "forward"
                gap = Int(delta)-1
                interval = (time-received)*1000
            default: status = "out_of_order"
            }
        }
        if status == "first" || status == "forward" { previous = (sequence,time) }
        append(Row(kind: "beat", phone: time-start, device: device, sequence: sequence,
                   gap: gap, status: status, milliseconds: interval))
    }

    private func append(_ row: Row) {
        rows.append(row)
        if rows.count >= 20_000 { stop() }
    }

    func demo() {
        begin("Simulated run", at: 0)
        for i in 0..<1000 {
            let t = Double(i)*0.05
            if i % 100 != 99 {
                receive(sequence: UInt16(i), device: UInt32(i*50), at: t)
            }
            if i % 20 == 0 {
            }
        }
        stop()
    }

    func export() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(title == "Simulated run" ? "bluetooth-simulation.csv" : "bluetooth-evaluation.csv")
        var csv = "event,phone_elapsed_s,baton_uptime_ms,sequence,missing_before,status,arrival_interval_ms\n"
        for r in rows {
            let fields = [r.kind,String(r.phone),r.device.map { String($0) } ?? "",
                          r.sequence.map { String($0) } ?? "",String(r.gap),r.status,
                          r.milliseconds.map { String($0) } ?? ""]
            csv += fields.joined(separator: ",") + "\n"
        }
        try csv.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
