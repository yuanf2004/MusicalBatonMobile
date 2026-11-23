import Foundation

@main
struct BluetoothEvaluationChecks {
    @MainActor static func main() throws {
        let run = BluetoothEvaluation()
        run.begin("Test", at: 0)
        for (i, value) in [65535, 0, 2, 2, 1, 3].enumerated() {
            run.receive(.beat, sequence: UInt16(value), device: 0, at: Double(i))
        }
        precondition(run.rows.map(\.status) == ["first","forward","forward","duplicate","out_of_order","forward"])
        precondition(run.rows.map(\.gap) == [0,0,1,0,0,0])
        run.subscriptionEnded(.beat)
        run.receive(.beat, sequence: 40, device: 0, at: 10)
        precondition(run.rows.last?.status == "first")
        run.demo()
        precondition(!run.running && run.rows.filter { $0.kind == "motion" }.reduce(0) { $0 + $1.gap } == 9)
        precondition(run.rows.filter { $0.kind == "read" }.count == 50)
        let file = try run.export()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let csv = try String(contentsOf: file, encoding: .utf8)
        precondition(csv.split(separator: "\n").count == run.rows.count + 1)
        print("Bluetooth evaluation sequence, simulation and CSV checks passed")
    }
}
