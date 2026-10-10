import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Closing the window quits, unless the menu bar icon is up: the close
  /// button only hides the window then, and AppKit counts a window ordered
  /// out as closed (see Attention.swift). With the IDE's windows, the app
  /// stays, as a Mac app does: the Dock's icon opens the main window again.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    if AppWindows.shared?.started ?? false { return false }
    // Launched for what the system asks to open, the main window is put
    // out of sight before Flutter has started (see application(_:open:)).
    if OpenRequests.shared.atLaunch { return false }
    return !(Attention.shared?.hidesOnClose ?? false)
  }

  /// The app asks before it quits (see quit_confirmation.dart), in its
  /// window (the one in front, with the IDE's): brought up for it, from
  /// the Dock's Quit too.
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    bringWindowFront()
    return super.applicationShouldTerminate(sender)
  }

  /// A click on the Dock icon brings back the window the close button hid
  /// (see Attention.swift); the main one, once all are closed. With the
  /// IDE's windows, Flutter decides which (an IDE's window, when the app
  /// opens to the IDE); a minimized one is brought back as AppKit does.
  override func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    if flag || sender.windows.contains(where: { $0.isMiniaturized }) { return true }
    if let windows = AppWindows.shared, windows.started {
      windows.reopen()
    } else if let window = mainFlutterWindow {
      window.makeKeyAndOrderFront(nil)
    }
    return true
  }

  /// The Dock icon's menu: the app's windows, and New Window (see
  /// AppWindows.swift).
  override func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    AppWindows.shared?.dockMenu()
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Files and folders the system asks the app to open: the `code`
  /// command's (`open -b`), Finder's Open With, those dropped on the Dock
  /// icon (see CFBundleDocumentTypes in Info.plist); the Finder
  /// extension's `baocode://` URLs and the extensions' (an OAuth callback;
  /// see OpenRequests.request). At launch they come before Flutter is ready
  /// for them, and wait (see OpenRequests).
  override func application(_ application: NSApplication, open urls: [URL]) {
    let paths = urls.filter(\.isFileURL).map { $0.standardizedFileURL.path }
    let requests = urls.compactMap(OpenRequests.request(from:))
    // An extension's URI opens nothing of its own: the app comes forward
    // (from the browser, after signing in) as it was.
    let uris = requests.filter { $0.first == OpenRequests.uriMarker }
    let opens = requests.filter { $0.first != OpenRequests.uriMarker }
    if !uris.isEmpty && !OpenRequests.shared.atLaunch && paths.isEmpty
      && opens.isEmpty
    {
      bringWindowFront()
    }
    for request in uris { OpenRequests.shared.deliver(request: request) }
    if !paths.isEmpty || !opens.isEmpty {
      let atLaunch = OpenRequests.shared.atLaunch
      if !paths.isEmpty { OpenRequests.shared.deliver(paths) }
      for request in opens { OpenRequests.shared.deliver(request: request) }
      if atLaunch {
        // Launched for them, the app opens to what they open alone (see
        // OpenRequests.launchRequest): the main window stays out of sight
        // unless Flutter shows it (it does without the IDE's windows).
        AppWindows.shared?.main.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
      } else if AppWindows.shared?.started ?? false {
        // With the IDE's windows, the app shows the one they open in.
        NSApp.activate(ignoringOtherApps: true)
      } else {
        bringWindowFront()
      }
    }
    super.application(application, open: urls)
  }

  private func bringWindowFront() {
    if let windows = AppWindows.shared, windows.started {
      windows.bringFront()
    } else if let window = mainFlutterWindow {
      if window.isMiniaturized { window.deminiaturize(nil) }
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
  }
}

/// The paths the system asks the app to open, for Flutter, over
/// `baocode/open` (see open_requests.dart): kept until Flutter takes them
/// (`takePending`, which also says it is ready for each as it comes), sent
/// as they come after that (`open`). The app's own, not the window's: the
/// system can ask before the window has its channel.
final class OpenRequests {
  static let shared = OpenRequests()

  /// The marker of an extension's URI (code_args.dart's uriRequestMarker).
  static let uriMarker = "\u{0}uri"

  private var pending: [String] = []
  /// Requests that came before Flutter was ready, each whole: they go after
  /// the paths, as Flutter reads what follows a request's marker as its.
  private var pendingRequests: [[String]] = []
  private var ready = false
  private var channel: FlutterMethodChannel?

  /// What the app was launched for (`launchRequest`): `agent` for Open
  /// with BaoCode, `ide` for anything else to open, by the first that came
  /// before Flutter asked; nil for none.
  private var launchRequest: String?
  private var launchAsked = false

  /// Whether what comes now is what the app was launched for: Flutter has
  /// not asked yet (see `launchRequest`).
  var atLaunch: Bool { !launchAsked }

  /// Answers Flutter over [messenger]'s `baocode/open` (see
  /// MainFlutterWindow.swift).
  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "baocode/open", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "launchRequest":
        // Asked once, before Flutter decides what shows at launch.
        self.launchAsked = true
        result(self.launchRequest)
      case "takePending":
        result(self.pending + self.pendingRequests.flatMap { $0 })
        self.pending = []
        self.pendingRequests = []
        self.ready = true
        self.launchAsked = true
      case "stop":
        // Flutter stopped listening: kept again until it next asks.
        self.ready = false
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Hands [paths] to Flutter, or keeps them until it is ready.
  func deliver(_ paths: [String]) {
    if atLaunch && launchRequest == nil { launchRequest = "ide" }
    if ready, let channel {
      channel.invokeMethod("open", arguments: paths)
    } else {
      pending.append(contentsOf: paths)
    }
  }

  /// Hands a request (see [request(from:)]) to Flutter, or keeps it until
  /// it is ready.
  func deliver(request: [String]) {
    if atLaunch && launchRequest == nil && request.first != Self.uriMarker {
      launchRequest = request.first == "\u{0}agent" ? "agent" : "ide"
    }
    if ready, let channel {
      channel.invokeMethod("open", arguments: request)
    } else {
      pendingRequests.append(request)
    }
  }

  /// What a `baocode://` URL of the Finder extension asks (see
  /// FinderExtension/FinderSync.swift), as the request Explorer's menu
  /// makes on Windows (see open_requests.cpp and code_args.dart): `agent`,
  /// Open with BaoCode, a new agent with the paths (its marker, then them);
  /// `ide`, Open with Fast Ide, the paths in a new window as `code -n`
  /// opens them (the `code` command's marker, a folder to start from, `-n`,
  /// then them). Any other `baocode://` URL is an extension's
  /// (`baocode://<publisher.name>/…`, see url_service.dart): its marker, then
  /// it. Nil for another scheme, or Open with's without absolute paths.
  static func request(from url: URL) -> [String]? {
    guard url.scheme == "baocode",
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return nil }
    guard components.host == "agent" || components.host == "ide" else {
      return [uriMarker, url.absoluteString]
    }
    let paths = (components.queryItems ?? [])
      .filter { $0.name == "path" }
      .compactMap(\.value)
      .filter { $0.hasPrefix("/") }
    guard let first = paths.first else { return nil }
    switch components.host {
    case "agent":
      return ["\u{0}agent"] + paths
    case "ide":
      return ["\u{0}code", first, "-n"] + paths
    default:
      return nil
    }
  }
}
