import CoreBluetooth
import Foundation

// Standalone checks: compile with DataFormatting.swift and BatonMotionPacket.swift.
let binary = Data([0x00, 0x01, 0x7F, 0x80, 0xFF])
precondition(hexString(from: binary) == "00 01 7F 80 FF")
let roundTrip = try dataFromHex(hexString(from: binary))
precondition(roundTrip == binary)
let compactHex = try dataFromHex("01ff\nA2\t03")
precondition(compactHex == Data([1, 255, 162, 3]))
precondition(hexString(from: Data()) == "")
precondition(String(data: Data([0xFF]), encoding: .utf8) == nil)
precondition(String(data: Data("Baton 🎵".utf8), encoding: .utf8) == "Baton 🎵")
for invalid in ["", " ", "0", "01 F", "GG", "0x01", "01,FF", "ＦＦ"] {
    do {
        _ = try dataFromHex(invalid)
        fatalError("Accepted invalid input: \(invalid)")
    } catch HexInputError.invalid {} catch { fatalError("Unexpected error: \(error)") }
}
precondition(supportsNotifications(.notify))
precondition(supportsNotifications(.indicate))
precondition(supportsNotifications(.notifyEncryptionRequired))
precondition(!supportsNotifications([.read, .write]))
precondition(propertyNames([.read, .writeWithoutResponse, .indicate]) == ["Read", "Write Without Response", "Indicate"])
precondition(knownUUIDName(CBUUID(string: "FFFF")) == nil)
print("Data formatting, binary preservation, input validation, and property checks passed.")

// Golden packet: LE sequence 0x1234, uptime 0x12345678,
// accel [1000, -1000, -32768] mg; gyro [123, -123, 32767] tenths °/s.
let payload: [UInt8] = [
    1, 7, 0x34, 0x12, 0x78, 0x56, 0x34, 0x12,
    0xE8, 0x03, 0x18, 0xFC, 0x00, 0x80,
    0x7B, 0x00, 0x85, 0xFF, 0xFF, 0x7F
]
let motion = try BatonMotionPacket(data: Data(payload))
precondition(motion.version == 1 && motion.flags == 7)
precondition(motion.sequence == 0x1234 && motion.uptimeMilliseconds == 0x12345678)
precondition(motion.acceleration.x == 1000 && motion.acceleration.y == -1000 && motion.acceleration.z == Int16.min)
precondition(motion.gyroscope.x == 123 && motion.gyroscope.y == -123 && motion.gyroscope.z == Int16.max)
precondition(motion.accelerationValid && motion.gyroscopeValid && motion.timeSynchronized)
precondition(motion.unknownFlags == 0)
precondition(motion.gyroscope.degreesPerSecondText.contains("-12.3"))
let padded = Data([0xFF] + payload)
let sliced = try BatonMotionPacket(data: padded.dropFirst())
precondition(sliced.sequence == motion.sequence && sliced.acceleration.z == Int16.min)
for flags: UInt8 in [0, 1, 2, 4, 0xFF] {
    var bytes = payload
    bytes[1] = flags
    let packet = try BatonMotionPacket(data: Data(bytes))
    precondition(packet.accelerationValid == (flags & 1 != 0))
    precondition(packet.gyroscopeValid == (flags & 2 != 0))
    precondition(packet.timeSynchronized == (flags & 4 != 0))
    precondition(packet.unknownFlags == flags & 0xF8)
    if flags == 0 { precondition(packet.logSummary.contains("Accel: invalid | Gyro: invalid")) }
}
var maximum = [UInt8](repeating: 0xFF, count: 20)
maximum[0] = 1
let maxPacket = try BatonMotionPacket(data: Data(maximum))
precondition(maxPacket.sequence == UInt16.max && maxPacket.uptimeMilliseconds == UInt32.max)
precondition(maxPacket.acceleration.x == -1 && maxPacket.gyroscope.z == -1)
for count in [0, 1, 19, 21] {
    do {
        _ = try BatonMotionPacket(data: Data(repeating: 1, count: count))
        fatalError("Accepted invalid motion length: \(count)")
    } catch BatonMotionPacket.DecodeError.invalidLength(let actual) { precondition(actual == count) }
}
var future = payload
future[0] = 2
do {
    _ = try BatonMotionPacket(data: Data(future))
    fatalError("Accepted unsupported version")
} catch BatonMotionPacket.DecodeError.unsupportedVersion(let version) { precondition(version == 2) }
precondition(BatonMotionPacket.matches(serviceUUID: BatonMotionPacket.serviceUUID.lowercased(),
                                      characteristicUUID: BatonMotionPacket.characteristicUUID.lowercased()))
precondition(!BatonMotionPacket.matches(serviceUUID: "180F", characteristicUUID: BatonMotionPacket.characteristicUUID))
precondition(!BatonMotionPacket.matches(serviceUUID: BatonMotionPacket.serviceUUID, characteristicUUID: "2A19"))
print("Motion packet endian, signed boundaries, flags, units, length, version, and UUID checks passed.")

func historyPacket(sequence: UInt16, uptime: UInt32, flags: UInt8 = 3, accelerationX: Int16 = 1000) throws -> BatonMotionPacket {
    var bytes = payload
    bytes[1] = flags
    bytes[2] = UInt8(truncatingIfNeeded: sequence)
    bytes[3] = UInt8(truncatingIfNeeded: sequence >> 8)
    let rawAcceleration = UInt16(bitPattern: accelerationX)
    bytes[8] = UInt8(truncatingIfNeeded: rawAcceleration)
    bytes[9] = UInt8(truncatingIfNeeded: rawAcceleration >> 8)
    for offset in 0..<4 { bytes[4 + offset] = UInt8(truncatingIfNeeded: uptime >> (offset * 8)) }
    return try BatonMotionPacket(data: Data(bytes))
}
var history = MotionHistory()
history.append(try historyPacket(sequence: UInt16.max, uptime: UInt32.max - 99))
history.append(try historyPacket(sequence: 0, uptime: 100))
precondition(history.samples.count == 2 && history.samples.last?.elapsedMilliseconds == 200)
precondition(history.lastIntervalMilliseconds == 200 && history.clockResetCount == 0)
precondition(history.samples.last?.accelerationSegment == 0)
history.append(try historyPacket(sequence: 0, uptime: 100))
precondition(history.receivedCount == 3 && history.samples.count == 2)
history.append(try historyPacket(sequence: 2, uptime: 500))
precondition(history.samples.last?.accelerationSegment == 1 && history.samples.last?.gyroscopeSegment == 1)
history.append(try historyPacket(sequence: 3, uptime: 700, flags: 2))
let invalidSample = history.samples.last!
precondition(MotionChannel.accelerationX.value(in: invalidSample.packet) == nil)
precondition(MotionChannel.gyroscopeX.value(in: invalidSample.packet) == 12.3)
history.append(try historyPacket(sequence: 4, uptime: 900))
precondition(history.samples.last?.accelerationSegment == 2 && history.samples.last?.gyroscopeSegment == 1)
precondition(MotionChannel.accelerationY.value(in: history.samples.last!.packet) == -1000)
precondition(MotionChannel.gyroscopeY.value(in: history.samples.last!.packet) == -12.3)
history.append(try historyPacket(sequence: 0, uptime: 50))
precondition(history.clockResetCount == 1 && history.samples.count == 1)
precondition(history.samples.last?.elapsedMilliseconds == 0 && history.lastIntervalMilliseconds == nil)
var timedHistory = MotionHistory()
for index in 0...400 {
    timedHistory.append(try historyPacket(sequence: UInt16(index), uptime: UInt32(index * 200)))
}
precondition(timedHistory.samples.count == 301)
precondition(timedHistory.samples.first?.elapsedMilliseconds == 20_000)
precondition(timedHistory.visibleSamples(seconds: 10).count == 51)
precondition(timedHistory.visibleSamples(seconds: 30).count == 151)
var fastHistory = MotionHistory()
for index in 0...2000 {
    fastHistory.append(try historyPacket(sequence: UInt16(index), uptime: UInt32(index)))
}
precondition(fastHistory.samples.count == 1000 && fastHistory.receivedCount == 2001)
fastHistory = MotionHistory()
precondition(fastHistory.samples.isEmpty && fastHistory.receivedCount == 0)
print("Motion history rollover, clock reset, duplicate, gap, validity, units, window, and memory-bound checks passed.")

// Display reduction must keep spikes, endpoints, and invalid-data gaps without
// changing the recorded samples, even when a 50 Hz window reaches the cap.
var displayHistory = MotionHistory()
for index in 0..<1000 {
    let x: Int16 = index == 317 ? 30_000 : (index == 318 ? -30_000 : 1000)
    displayHistory.append(try historyPacket(sequence: UInt16(index), uptime: UInt32(index * 20),
                                            flags: index == 500 ? 2 : 3, accelerationX: x))
}
let display = MotionGraphSnapshot(history: displayHistory, latestPacket: nil, parsingEnabled: true,
                                  errorMessage: nil, windowSeconds: 30)
precondition(display.traces.count == 6 && display.receivedCount == 1000)
precondition(displayHistory.samples.count == 1000 && display.latestPacket?.sequence == 999)
for trace in display.traces {
    precondition(trace.pointCount <= 256)
    let points = trace.segments.flatMap { $0 }
    precondition(points.last?.time == 0)
    precondition(zip(points, points.dropFirst()).allSatisfy { $0.time <= $1.time })
    precondition(points.allSatisfy { trace.yRange.contains($0.value) })
}
let accelXTrace = display.traces.first { $0.channel == .accelerationX }!
let accelXValues = accelXTrace.segments.flatMap { $0 }.map(\.value)
precondition(accelXValues.contains(30_000) && accelXValues.contains(-30_000))
precondition(accelXTrace.segments.count == 2)
precondition(display.traces.first { $0.channel == .gyroscopeX }!.segments.count == 1)
let accelerationRanges = display.traces.filter { $0.channel.isAcceleration }.map(\.yRange)
precondition(accelerationRanges.allSatisfy { $0 == accelerationRanges[0] })
let emptyDisplay = MotionGraphSnapshot(history: MotionHistory(), latestPacket: nil, parsingEnabled: false,
                                       errorMessage: nil, windowSeconds: 10)
precondition(emptyDisplay.traces.allSatisfy { $0.segments.isEmpty })
precondition(emptyDisplay.latestPacket == nil && !emptyDisplay.parsingEnabled)
let shortDisplay = MotionGraphSnapshot(history: displayHistory, latestPacket: nil, parsingEnabled: true,
                                       errorMessage: "Malformed packet", windowSeconds: 10)
precondition(shortDisplay.traces.flatMap { $0.segments.flatMap { $0 } }.allSatisfy { $0.time >= -10 })
precondition(shortDisplay.errorMessage == "Malformed packet" && shortDisplay.latestPacket?.sequence == 999)
print("Graph point budget, peak preservation, gaps, ordering, units, windows, and source retention checks passed.")
