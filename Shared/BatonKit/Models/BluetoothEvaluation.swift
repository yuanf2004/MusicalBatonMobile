import Foundation
import Observation

@MainActor @Observable
final class BluetoothEvaluation {
    enum Stream: String { case beat, motion }
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
    private var previous: [Stream: (UInt16, Double)] = [:]
    private var readStart: Double?

    func begin(_ title: String, at time: Double = ProcessInfo.processInfo.systemUptime) {
        rows.removeAll()
        previous.removeAll()
        readStart = nil
        self.title = title
        start = time
        running = true
    }

    func stop() { running = false; readStart = nil }
    func subscriptionEnded(_ stream: Stream) { previous[stream] = nil }

    func requestedRead(at time: Double) {
        if running { readStart = time }
    }

    func finishedRead(at time: Double, success: Bool) {
        guard running, let sent = readStart else { return }
        readStart = nil
        append(Row(kind: "read", phone: time-start, device: nil, sequence: nil, gap: 0,
                   status: success ? "ok" : "error", milliseconds: success ? (time-sent)*1000 : nil))
    }

    func receive(_ stream: Stream, sequence: UInt16, device: UInt32, at time: Double) {
        guard running else { return }
        var status = "first"
        var gap = 0
        var interval: Double?
        if let (last, received) = previous[stream] {
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
        if status == "first" || status == "forward" { previous[stream] = (sequence,time) }
        append(Row(kind: stream.rawValue, phone: time-start, device: device, sequence: sequence,
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
                receive(.motion, sequence: UInt16(i), device: UInt32(i*50), at: t)
            }
            if i % 6 == 0 {
                receive(.beat, sequence: UInt16(i/6), device: UInt32(i*50), at: t)
            }
            if i % 20 == 0 {
                requestedRead(at: t)
                finishedRead(at: t+0.020+Double(i%3)*0.004, success: true)
            }
        }
        stop()
    }

    func export() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(title == "Simulated run" ? "bluetooth-simulation.csv" : "bluetooth-evaluation.csv")
        var csv = "event,phone_elapsed_s,baton_uptime_ms,sequence,missing_before,status,arrival_interval_or_read_rtt_ms\n"
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
