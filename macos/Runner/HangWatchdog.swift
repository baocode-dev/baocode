import Cocoa
import Darwin
import FlutterMacOS

/// Watches, from a thread of its own, the app's main thread: AppKit's, and
/// Flutter's platform and UI threads, which are one with it. When it stops
/// answering for [hangSeconds], the event log (lib/platform/event_log.dart's
/// events.log) says so at once (`[hang]`), and `/usr/bin/sample` writes what
/// each of the app's threads was doing to the logs folder's
/// `hangs/hang-<YYYYMMDD-HHMMSS>-<pid>.txt`, which a diagnostics upload
/// sends. As it answers again, Flutter is told how long it was (`hangEnded`),
/// and writes that with what the app was showing (lib/diagnostics/
/// hang_watch.dart). A hang the user ends by quitting leaves the line and
/// the sample; the next run says the run before ended without a word.
///
/// The Dart code's frames read `??? (in App) load address … + 0x…`:
/// `dart run tool/symbolize_jank_sample.dart` names them with the release's
/// symbols (CI's symbols-macos artifact).
///
/// What it costs: a block on the main queue each second, and nothing else
/// until a hang. The sample (which suspends the app many times a second
/// while it runs) is taken [maxSamples] times a run at most, once a hang;
/// [keptSamples] stay in the folder. The computer asleep or the app stopped
/// in a debugger is no hang; a debug build is not watched.
///
/// Its channel is `baocode/logs` (the Windows app's too, see windows/runner/
/// log_folder.h): `setFolder` (path) the logs folder, from Flutter as it
/// starts. Nothing is written before that.
final class HangWatchdog {
  static let shared = HangWatchdog()

  /// How long the main thread may not answer before it counts as hung.
  /// Past AppKit's spinning cursor (2 s), well short of the user giving up.
  static let hangSeconds: UInt64 = 4

  /// How long a hang is sampled.
  static let sampleSeconds = 3

  /// The most samples a run takes, and the most hangs its event log tells
  /// of: a hang that comes and goes is written a few times, not on and on.
  static let maxSamples = 3
  static let maxLines = 20

  /// The most samples kept in the folder, across runs: the oldest go as a
  /// new one is written.
  static let keptSamples = 10

  /// Longer than this between two of the watch's 1 s rounds, the watch was
  /// not running either (the computer asleep, the app stopped, App Nap): the
  /// main thread had no turn, and is given a fresh start.
  static let watchGapNanoseconds: UInt64 = 3_000_000_000

  /// The longest a sample is waited for: past it, it is stopped.
  static let sampleTimeout: TimeInterval = 30

  private let lock = NSLock()

  /// The logs folder, as Flutter said; nil before then. Under [lock].
  private var folder: String?

  /// When the ping on the main queue now was posted ([uptime]); nil when
  /// it was answered. Under [lock].
  private var pingSince: UInt64?

  /// The hang under way, as written: its sample's name under the logs
  /// folder, "" for none; nil while there is no hang written. Under [lock].
  private var written: String?

  private var started = false
  private var channel: FlutterMethodChannel?

  // The watch thread's own.
  private var lines = 0
  private var samples = 0

  /// Starts watching, once, and answers Flutter over [messenger]'s
  /// `baocode/logs`. From the main thread.
  func start(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "baocode/logs", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "setFolder":
        if let path = call.arguments as? String, !path.isEmpty {
          self?.locked { self?.folder = path }
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    #if DEBUG
    // A debug build's Dart code (JIT, hot reload) holds the thread for
    // seconds as it is: no hang to tell of.
    return
    #else
    if started { return }
    started = true
    let thread = Thread { [weak self] in self?.watch() }
    thread.name = "dev.baocode.hang-watchdog"
    thread.qualityOfService = .utility
    thread.start()
    #endif
  }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  /// Nanoseconds the computer has been running, its sleep left out: waking
  /// up is no hang.
  private static func uptime() -> UInt64 {
    clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
  }

  /// Whether a debugger holds the app: stopped in it, it answers no one.
  private static func beingDebugged() -> Bool {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return false }
    return (info.kp_proc.p_flag & P_TRACED) != 0
  }

  private func watch() {
    var lastRound = Self.uptime()
    while true {
      Thread.sleep(forTimeInterval: 1)
      let now = Self.uptime()
      let late = now - lastRound > Self.watchGapNanoseconds
      lastRound = now
      if late || Self.beingDebugged() {
        // The ping waiting, if any, counts from now.
        locked {
          if pingSince != nil { pingSince = now }
        }
        continue
      }
      let hung: UInt64? = locked {
        guard let since = pingSince else {
          pingSince = now
          return nil
        }
        return written == nil ? now - since : nil
      }
      guard let hung else {
        if locked({ pingSince == now }) {
          DispatchQueue.main.async { [weak self] in self?.answered() }
        }
        continue
      }
      if hung >= Self.hangSeconds * 1_000_000_000 {
        report(after: hung)
        // The sample took its time: the next round's gap is no sleep.
        lastRound = Self.uptime()
      }
    }
  }

  /// The ping run on the main thread: it is there. A hang written ends.
  private func answered() {
    let now = Self.uptime()
    let (since, sample) = locked { () -> (UInt64?, String?) in
      defer {
        pingSince = nil
        written = nil
      }
      return (pingSince, written)
    }
    guard let since, let sample else { return }
    var arguments: [String: Any] = ["seconds": Double(now - since) / 1e9]
    if !sample.isEmpty { arguments["sample"] = sample }
    channel?.invokeMethod("hangEnded", arguments: arguments)
  }

  /// The main thread has not answered for [hung] nanoseconds: the event log
  /// says so, and a sample of it is taken. On the watch thread.
  private func report(after hung: UInt64) {
    // Answered since it was found hung: not one to write.
    let folder = locked { () -> String?? in
      guard pingSince != nil else { return nil }
      written = ""
      return .some(self.folder)
    }
    guard let folder, let folder, lines < Self.maxLines else { return }
    lines += 1
    let seconds = hung / 1_000_000_000
    let now = Date()
    let stamp = Self.format("yyyyMMdd-HHmmss", now)
    let name = "hang-\(stamp)-\(getpid()).txt"
    let sampled = samples < Self.maxSamples
    var line =
      "the main thread (Flutter's platform and UI) has not answered for \(seconds) s"
    if sampled { line += "; sample hangs/\(name)" }
    append(event: line, at: now, to: folder)
    guard sampled else { return }
    samples += 1
    locked {
      if written != nil { written = "hangs/\(name)" }
    }
    let hangs = (folder as NSString).appendingPathComponent("hangs")
    try? FileManager.default.createDirectory(
      atPath: hangs, withIntermediateDirectories: true)
    prune(hangs)
    let path = (hangs as NSString).appendingPathComponent(name)
    if let failed = sample(into: path) {
      append(event: "sample hangs/\(name) not taken: \(failed)", at: Date(), to: folder)
    }
  }

  /// Samples the app into [path] with `/usr/bin/sample`, waited for: why it
  /// was not written, or nil.
  private func sample(into path: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
    // -mayDie: the binaries' symbols read at once, for a sample of an app
    // the user quits before it is done.
    process.arguments = ["\(getpid())", "\(Self.sampleSeconds)", "-mayDie", "-file", path]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return "\(error.localizedDescription)"
    }
    let deadline = Date().addingTimeInterval(Self.sampleTimeout)
    while process.isRunning && Date() < deadline {
      Thread.sleep(forTimeInterval: 0.2)
    }
    if process.isRunning {
      process.terminate()
      return "still running after \(Int(Self.sampleTimeout)) s"
    }
    if process.terminationStatus != 0 {
      return "sample exited with \(process.terminationStatus)"
    }
    return FileManager.default.fileExists(atPath: path) ? nil : "no file"
  }

  /// Leaves room in [hangs] for one more sample: of the hang-*.txt there,
  /// all but the newest keptSamples - 1 go. Their names sort as their times.
  private func prune(_ hangs: String) {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: hangs) else {
      return
    }
    let samples = names.filter { $0.hasPrefix("hang-") && $0.hasSuffix(".txt") }.sorted()
    guard samples.count >= Self.keptSamples else { return }
    for name in samples.prefix(samples.count - (Self.keptSamples - 1)) {
      try? FileManager.default.removeItem(
        atPath: (hangs as NSString).appendingPathComponent(name))
    }
  }

  /// Writes [message] to the event log in [folder], as Flutter's lines:
  /// "<time> [hang] message". Flutter does not write while the main
  /// thread is held.
  private func append(event message: String, at time: Date, to folder: String) {
    let line = "\(Self.format("yyyy-MM-dd'T'HH:mm:ss.SSSSSS", time)) [hang] \(message)\n"
    let path = (folder as NSString).appendingPathComponent("events.log")
    let fd = open(path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
    guard fd >= 0 else { return }
    defer { close(fd) }
    let bytes = Array(line.utf8)
    _ = bytes.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
  }

  /// [date] in local time, as Dart's DateTime.toIso8601String() has it.
  private static func format(_ pattern: String, _ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = .current
    formatter.dateFormat = pattern
    return formatter.string(from: date)
  }
}
