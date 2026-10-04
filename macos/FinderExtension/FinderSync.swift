import Cocoa
import FinderSync

/// Finder's context menu on files, folders, a folder's background and the
/// sidebar (and the toolbar button, once added to the toolbar): Open with
/// BaoCode, a new agent in a window of its own, and Open with Fast Ide, a
/// new IDE window, as the Windows installer adds them to Explorer's (see
/// tool/baocode.iss). Turned on and off in the app's settings, or System
/// Settings' extensions (see lib/platform/context_menu_io.dart).
///
/// The extension is sandboxed, as app extensions are: it hands the paths
/// to the app it is in through a `baocode://` URL, which the app turns into
/// the request Explorer's menu makes on Windows (see AppDelegate.swift).
class FinderSync: FIFinderSync {
  override init() {
    super.init()
    let controller = FIFinderSyncController.default()
    controller.directoryURLs = Self.volumes()
    // A disk mounted later has the menu too.
    let center = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
      center.addObserver(forName: name, object: nil, queue: .main) { _ in
        controller.directoryURLs = Self.volumes()
      }
    }
  }

  /// Every folder: the startup disk and those mounted.
  private static func volumes() -> Set<URL> {
    var urls: Set<URL> = [URL(fileURLWithPath: "/")]
    if let mounted = FileManager.default.mountedVolumeURLs(
      includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]
    ) {
      urls.formUnion(mounted)
    }
    return urls
  }

  /// The app the extension is in: BaoCode.app/Contents/PlugIns/….appex.
  private static let appURL = Bundle.main.bundleURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  private static var chinese: Bool {
    Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
  }

  /// "Open with BaoCode", in the words the Windows installer uses.
  private static func openWith(_ name: String) -> String {
    chinese ? "用 \(name) 打开" : "Open with \(name)"
  }

  private static func icon(size: CGFloat) -> NSImage {
    let image = NSWorkspace.shared.icon(forFile: appURL.path)
    image.size = NSSize(width: size, height: size)
    return image
  }

  override var toolbarItemName: String { "BaoCode" }

  override var toolbarItemToolTip: String {
    Self.chinese ? "在 BaoCode 中打开当前文件夹" : "Open the current folder in BaoCode"
  }

  override var toolbarItemImage: NSImage { Self.icon(size: 32) }

  /// What the menu was last asked for, for its items' actions: the
  /// selection's, or the folder's the window shows.
  private static var menuKind: FIMenuKind = .contextualMenuForItems

  override func menu(for menuKind: FIMenuKind) -> NSMenu {
    let menu = NSMenu(title: "")
    switch menuKind {
    case .contextualMenuForItems, .contextualMenuForContainer,
      .contextualMenuForSidebar, .toolbarItemMenu:
      Self.menuKind = menuKind
    @unknown default:
      return menu
    }
    let icon = Self.icon(size: 16)
    let agent = NSMenuItem(
      title: Self.openWith("BaoCode"), action: #selector(openAgent(_:)), keyEquivalent: "")
    agent.image = icon
    menu.addItem(agent)
    let ide = NSMenuItem(
      title: Self.openWith("Fast Ide"), action: #selector(openIde(_:)), keyEquivalent: "")
    ide.image = icon
    menu.addItem(ide)
    return menu
  }

  @objc func openAgent(_ sender: AnyObject?) {
    open(mode: "agent")
  }

  @objc func openIde(_ sender: AnyObject?) {
    open(mode: "ide")
  }

  /// The items the menu is on: those selected (on items, and the toolbar's
  /// with a selection), else the folder the window shows or the sidebar's
  /// item.
  private func targets() -> [URL] {
    let controller = FIFinderSyncController.default()
    if Self.menuKind == .contextualMenuForItems || Self.menuKind == .toolbarItemMenu,
      let selected = controller.selectedItemURLs(), !selected.isEmpty
    {
      return selected
    }
    return [controller.targetedURL()].compactMap { $0 }
  }

  /// Hands the targets to the app: `baocode://<mode>?path=…&path=…`.
  private func open(mode: String) {
    let paths = targets().filter(\.isFileURL).map(\.path)
    guard !paths.isEmpty else { return }
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~/")
    var components = URLComponents()
    components.scheme = "baocode"
    components.host = mode
    components.percentEncodedQuery = paths.map {
      "path=" + ($0.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
    }.joined(separator: "&")
    guard let url = components.url else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    // This copy of the app, not whichever claims the scheme; that one if
    // it cannot be told apart.
    NSWorkspace.shared.open(
      [url], withApplicationAt: Self.appURL, configuration: configuration
    ) { _, error in
      if error != nil {
        DispatchQueue.main.async { NSWorkspace.shared.open(url) }
      }
    }
  }
}
