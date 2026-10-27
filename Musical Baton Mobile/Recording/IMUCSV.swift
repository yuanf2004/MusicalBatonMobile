import Foundation

nonisolated struct IMURecordingMetadata: Sendable {
    let deviceID: String
    let deviceName: String
    let serviceUUID: String
    let characteristicUUID: String
}

nonisolated struct IMUCSVRow: Sendable {
    let receivedAt: Date
    let elapsedMilliseconds: Double
    let metadata: IMURecordingMetadata
    let data: Data
}

nonisolated struct IMUCSVEncoding {
    static let columns = [
        "received_at_utc", "phone_elapsed_ms", "device_id", "device_name",
        "service_uuid", "characteristic_uuid", "packet_length_bytes", "packet_version",
        "flags", "sequence", "device_uptime_ms", "acceleration_valid", "gyroscope_valid",
        "time_synchronized", "accel_x_mg", "accel_y_mg", "accel_z_mg",
        "gyro_x_deg_per_s", "gyro_y_deg_per_s", "gyro_z_deg_per_s", "raw_hex", "decode_error"
    ]
    static var header: Data { Data((columns.joined(separator: ",") + "\r\n").utf8) }

    static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    static func encode(_ row: IMUCSVRow, formatter: ISO8601DateFormatter) -> (data: Data, malformed: Bool) {
        let packet: BatonMotionPacket?
        let decodeError: String
        do { packet = try BatonMotionPacket(data: row.data); decodeError = "" }
        catch { packet = nil; decodeError = error.localizedDescription }
        let accel = packet.flatMap { $0.accelerationValid ? $0.acceleration : nil }
        let gyro = packet.flatMap { $0.gyroscopeValid ? $0.gyroscope : nil }
        func integer(_ value: Int16?) -> String { value.map { String($0) } ?? "" }
        func degrees(_ value: Int16?) -> String {
            value.map { String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), Double($0) / 10) } ?? ""
        }
        func number<T: BinaryInteger>(_ value: T?) -> String { value.map { String($0) } ?? "" }
        func flag(_ value: Bool?) -> String { value.map { $0 ? "1" : "0" } ?? "" }
        var fields: [String] = [
            formatter.string(from: row.receivedAt),
            String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), row.elapsedMilliseconds),
            row.metadata.deviceID, row.metadata.deviceName, row.metadata.serviceUUID, row.metadata.characteristicUUID
        ]
        fields.append(String(row.data.count))
        fields.append(number(row.data.first))
        fields.append(number(packet?.flags))
        fields.append(number(packet?.sequence))
        fields.append(number(packet?.uptimeMilliseconds))
        fields.append(flag(packet?.accelerationValid))
        fields.append(flag(packet?.gyroscopeValid))
        fields.append(flag(packet?.timeSynchronized))
        fields.append(integer(accel?.x))
        fields.append(integer(accel?.y))
        fields.append(integer(accel?.z))
        fields.append(degrees(gyro?.x))
        fields.append(degrees(gyro?.y))
        fields.append(degrees(gyro?.z))
        fields.append(row.data.map { String(format: "%02X", $0) }.joined(separator: " "))
        fields.append(decodeError)
        return (Data((fields.map(escape).joined(separator: ",") + "\r\n").utf8), packet == nil)
    }
}

nonisolated struct IMUCSVFileSummary: Sendable {
    let url: URL
    let writtenRows: Int
    let malformedRows: Int
    let errorMessage: String?
}

/// All mutable writer state is confined to its FIFO queue after initialization.
/// Unchecked Sendable permits dispatching that private state, not direct access.
nonisolated final class IMUCSVFileWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "SmartBaton.IMUCSV", qos: .utility)
    private let url: URL
    private let handle: FileHandle
    private let formatter = ISO8601DateFormatter()
    private let onFailure: @Sendable (String) -> Void
    private var writtenRows = 0
    private var malformedRows = 0
    private var failure: String?
    private var finished = false

    init(url: URL, onFailure: @escaping @Sendable (String) -> Void) throws {
        self.url = url
        self.onFailure = onFailure
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try IMUCSVEncoding.header.write(to: url, options: .atomic)
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
    }

    func append(_ row: IMUCSVRow) {
        queue.async { [self] in
            guard !finished, failure == nil else { return }
            let encoded = IMUCSVEncoding.encode(row, formatter: formatter)
            do {
                try handle.write(contentsOf: encoded.data)
                writtenRows += 1
                if encoded.malformed { malformedRows += 1 }
            } catch {
                failure = error.localizedDescription
                onFailure(error.localizedDescription)
            }
        }
    }

    func finish(_ completion: @escaping @Sendable (IMUCSVFileSummary) -> Void) {
        queue.async { [self] in
            if !finished {
                do { try handle.synchronize() } catch { failure = failure ?? error.localizedDescription }
                do { try handle.close() } catch { failure = failure ?? error.localizedDescription }
                finished = true
            }
            completion(IMUCSVFileSummary(url: url, writtenRows: writtenRows,
                                         malformedRows: malformedRows, errorMessage: failure))
        }
    }
}
