import Foundation
import os

// Synthetic DEBUG profiling only. Static span names never include content, paths,
// credentials or identifiers. Release builds retain no sampling or signposts.
enum InteractionMetrics {
  struct Span {
    #if DEBUG
    let id: OSSignpostID?
    #endif
  }
  #if DEBUG
  private static let log = OSLog(subsystem: "com.saltypanda.openworkremote", category: .pointsOfInterest)
  private static let enabled = ProcessInfo.processInfo.arguments.contains("-interaction-metrics")
  @MainActor private static var sampling = false
  #endif
  static func begin(_ name: StaticString) -> Span {
    #if DEBUG
    guard enabled else { return Span(id: nil) }
    let id = OSSignpostID(log: log)
    os_signpost(.begin, log: log, name: name, signpostID: id)
    return Span(id: id)
    #else
    return Span()
    #endif
  }
  static func end(_ name: StaticString, _ span: Span) {
    #if DEBUG
    if let id = span.id { os_signpost(.end, log: log, name: name, signpostID: id) }
    #endif
  }
  static func measure<T>(_ name: StaticString, _ action: () throws -> T) rethrows -> T {
    let span = begin(name)
    defer { end(name, span) }
    return try action()
  }
  @MainActor static func startSampling() {
    #if DEBUG
    guard enabled, !sampling else { return }
    sampling = true
    Task {
      let clock = ContinuousClock()
      let started = clock.now
      var delays: [Double] = []
      while started.duration(to: clock.now) < .seconds(300) {
        let before = clock.now
        do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        let elapsed = before.duration(to: clock.now).components
        delays.append(max(0, Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15 - 50))
      }
      let sorted = delays.sorted()
      let report: [String: Double] = ["samples": Double(sorted.count), "durationSeconds": 300,
        "p95MainActorWakeupDelayMs": sorted[Int(Double(sorted.count - 1) * 0.95)],
        "maxMainActorWakeupDelayMs": sorted.last ?? 0,
        "wakeupsOver250Ms": Double(sorted.filter { $0 > 250 }.count)]
      // Write once, off the main actor. This is scheduler delay, not tap-to-pixel latency.
      await Task.detached {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: .sortedKeys) {
          try? data.write(to: folder.appending(path: "interaction-metrics.json"), options: [.atomic, .completeFileProtection])
        }
      }.value
    }
    #endif
  }
}
