// Antigravity CLI (`agy`) on a remote host, managed over `baocode-server`:
// - Prefers an existing system-installed `antigravity` / `agy` on the host.
// - Otherwise installs via fast 4-second direct remote probe -> automatic
//   fallback to local download (cached per platform) + chunked SHA-512 upload.
// - Provides an in-conversation setup controller ([RemoteAgySetupController])
//   for explicit install confirmation and headless OAuth sign-in.

import 'dart:async';
import 'dart:io';

import 'package:bao_remote/acp.dart' show AcpTransport, AgyBuild, AgyRelease;
import 'package:bao_remote/client.dart' show RemoteClient, RemoteException;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../kernel/antigravity/agy_runtime.dart';
import '../workspace/editor_launcher.dart' show openExternal;
import 'remote_oauth_bridge.dart';
import 'remote_proxy.dart';
import 'ssh_host.dart';

/// Opens a remote Antigravity OAuth authorization [url] on this machine.
typedef RemoteAgyUrlHandler = Future<void> Function(Uri url);

/// Prompts the user to paste an OAuth authorization code when the remote flow
/// requires manual code entry or when the local callback bridge could not bind
/// the requested loopback port ([bridgeActive] is `false`).
///
/// Returning `null` cancels the sign-in flow.
typedef RemoteAgyCodePrompt =
    Future<String?> Function(Uri url, {required bool bridgeActive});

/// Which transfer leg [installRemoteAgy] is currently executing.
enum RemoteAgyInstallPhase {
  /// Probing whether the remote host can reach Google's release feed directly.
  probing,

  /// The remote host is downloading directly from Google.
  remoteDownloading,

  /// Direct probe failed/timed out; downloading on this machine (cached per
  /// target platform) before transferring to the host.
  localDownloading,

  /// Uploading the cached build from this machine to the remote host.
  uploading,
}

/// Lifecycle stage of the in-conversation setup card for Antigravity on an SSH
/// host.
enum RemoteAgySetupStage {
  idle,
  checking,
  needsInstall,
  installing,
  needsSignIn,
  signingIn,
  ready,
  error,
}

final Map<SshHost, Future<void>> _installing = {};
final Map<SshHost, List<void Function(double)>> _progressListeners = {};
final Map<SshHost, List<void Function(RemoteAgyInstallPhase)>> _phaseListeners =
    {};

Future<Map<String, String>> _remoteProxyEnv(RemoteClient client) async {
  try {
    return await remoteProxyEnvironment(client);
  } on Object {
    return const {};
  }
}

void _notifyProgress(SshHost host, double progress) {
  final clamped = progress.clamp(0.0, 1.0).toDouble();
  for (final listener in [...?_progressListeners[host]]) {
    listener(clamped);
  }
}

void _notifyPhase(SshHost host, RemoteAgyInstallPhase phase) {
  for (final listener in [...?_phaseListeners[host]]) {
    listener(phase);
  }
}

/// Default timeout for probing direct remote access to Google's release feed
/// before falling back to local download + chunked upload.
const defaultRemoteAgyProbeTimeout = Duration(seconds: 4);

/// Installs Antigravity CLI (`agy`) on [host], deduplicating concurrent
/// installations per host and updating [SshHost.installingAgy], [onProgress]
/// (0.0 to 1.0), and [onPhase].
///
/// Path 1 probes direct remote download from Google without proxying, using a
/// fast [directProbeTimeout] (default 4s) so overseas hosts download directly
/// at full speed. If that probe fails or times out, Path 2 downloads the target
/// build locally (reusing a SHA-512-verified cache file in [downloads] shared
/// across hosts of the same platform) and uploads it in chunks via
/// [RemoteClient.agyUpload].
Future<void> installRemoteAgy(
  SshHost host, {
  Directory? downloads,
  void Function(double progress)? onProgress,
  void Function(RemoteAgyInstallPhase phase)? onPhase,
  Duration directProbeTimeout = defaultRemoteAgyProbeTimeout,
  Future<void>? cancel,
  AgyRelease? release,
}) {
  if (onProgress != null) {
    (_progressListeners[host] ??= []).add(onProgress);
  }
  if (onPhase != null) {
    (_phaseListeners[host] ??= []).add(onPhase);
  }
  return _installing[host] ??=
      _install(
        host,
        downloads: downloads,
        directProbeTimeout: directProbeTimeout,
        cancel: cancel,
        release: release,
      ).whenComplete(() {
        _installing.remove(host);
        _progressListeners.remove(host);
        _phaseListeners.remove(host);
        host.installingAgy = null;
      });
}

Future<void> _install(
  SshHost host, {
  Directory? downloads,
  required Duration directProbeTimeout,
  Future<void>? cancel,
  AgyRelease? release,
}) async {
  var cancelled = false;
  unawaited(cancel?.then((_) => cancelled = true));

  final client = await host.ready;
  if (cancelled) {
    throw const AgyUnavailable('Installing Antigravity was cancelled');
  }
  host.installingAgy = const ClaudeInstallProgress(0, null);
  _notifyPhase(host, RemoteAgyInstallPhase.probing);

  // Path 1: fast direct probe on the remote host (no local proxy detour).
  var enteredRemoteDownload = false;
  try {
    await client.agyInstall(
      probeTimeout: directProbeTimeout,
      cancel: cancel,
      onProgress: (received, total) {
        if (!enteredRemoteDownload) {
          enteredRemoteDownload = true;
          _notifyPhase(host, RemoteAgyInstallPhase.remoteDownloading);
        }
        host.installingAgy = ClaudeInstallProgress(
          received,
          total > 0 ? total : null,
        );
        if (total > 0) {
          _notifyProgress(host, received / total);
        }
      },
    );
    _notifyProgress(host, 1.0);
    return;
  } on AgyUnavailable {
    if (cancelled) rethrow;
    // Direct remote fetch failed or timed out: fall back to local cache+upload.
  } on RemoteException {
    if (cancelled) {
      throw const AgyUnavailable('Installing Antigravity was cancelled');
    }
    // Direct remote fetch failed: fall back to local download + upload.
  }

  if (cancelled) {
    throw const AgyUnavailable('Installing Antigravity was cancelled');
  }

  // Path 2: local download (with SHA-512 cache shared per platform) + chunked
  // upload to the remote host.
  final platform = client.hello?.platform;
  if (platform == null) {
    throw const AgyUnavailable('The host did not say what it runs');
  }
  _notifyPhase(host, RemoteAgyInstallPhase.localDownloading);
  final rel = release ?? AgyRelease();
  final target = AgyRelease.targetOf(platform);
  final AgyBuild build = await rel.latest(target, cancel: cancel);
  if (cancelled) {
    throw const AgyUnavailable('Installing Antigravity was cancelled');
  }
  final cacheDir =
      downloads ?? Directory(p.join(Directory.systemTemp.path, 'baocode'));
  final ext = build.isArchive ? '.tar.gz' : '';
  final file = File(p.join(cacheDir.path, 'agy-${build.version}-$target$ext'));

  final cached = await AgyRelease.verifySha512(file, build.sha512);
  if (!cached) {
    await rel.download(
      build,
      file,
      cancel: cancel,
      onProgress: (received, total) {
        host.installingAgy = ClaudeInstallProgress(
          received,
          total > 0 ? total : null,
        );
        if (total > 0) {
          _notifyProgress(host, 0.5 * (received / total).clamp(0.0, 1.0));
        }
      },
    );
  }
  if (cancelled) {
    throw const AgyUnavailable('Installing Antigravity was cancelled');
  }

  _notifyPhase(host, RemoteAgyInstallPhase.uploading);
  await client.agyUpload(
    build,
    file,
    cancel: cancel,
    onProgress: (sent, size) {
      host.installingAgy = ClaudeInstallProgress(sent, size, uploading: true);
      if (size > 0) {
        final fraction = (sent / size).clamp(0.0, 1.0);
        _notifyProgress(host, cached ? fraction : 0.5 + 0.5 * fraction);
      }
    },
  );
  _notifyProgress(host, 1.0);
}

Future<void> _defaultOpenUrl(Uri url) async {
  await openExternal(url.toString());
}

/// [AgyRuntime] backed by a remote SSH [host]'s `baocode-server`.
class RemoteAgyRuntime implements AgyRuntime {
  RemoteAgyRuntime(
    this.host, {
    this.openUrl,
    this.requestCode,
    this.release,
  });

  final SshHost host;
  final RemoteAgyUrlHandler? openUrl;
  final RemoteAgyCodePrompt? requestCode;
  final AgyRelease? release;

  @override
  Future<String?> version() async => (await host.ready).agyVersion();

  @override
  Future<String> latestVersion() async {
    final client = await host.ready;
    return client.agyLatestVersion(environment: await _remoteProxyEnv(client));
  }

  @override
  Future<void> install({void Function(double progress)? onProgress}) =>
      installRemoteAgy(host, onProgress: onProgress, release: release);

  @override
  Future<List<AgyModel>> models() async {
    final client = await host.ready;
    return client.agyModels(environment: await _remoteProxyEnv(client));
  }

  @override
  Future<void> signOut() async {
    final client = await host.ready;
    await client.agySignOut(environment: await _remoteProxyEnv(client));
  }

  @override
  Future<void> deleteSession(String sessionId) async =>
      (await host.ready).agyDeleteSession(sessionId);

  @override
  void warm() {}

  @override
  Future<void> stopAll() async {}

  @override
  Future<AcpTransport> start(String cwd) =>
      throw UnsupportedError('Remote Antigravity sessions run via baocode-server');

  @override
  Future<void> signIn({Future<void>? cancel}) async {
    final done = Completer<void>();
    RemoteOAuthCallbackBridge? bridge;
    StreamSubscription<Map<String, Object?>>? subscription;
    var cancelled = false;
    var listening = false;
    var urlHandled = false;
    var receivedDone = false;

    void fail(Object error, [StackTrace? stack]) {
      if (!done.isCompleted) {
        done.completeError(error, stack ?? StackTrace.current);
      }
    }

    Future<void> abort(AgyUnavailable error) async {
      cancelled = true;
      final activeSub = subscription;
      subscription = null;
      await activeSub?.cancel();
      final activeBridge = bridge;
      bridge = null;
      await activeBridge?.close();
      if (listening) {
        fail(error);
      }
    }

    if (cancel != null) {
      unawaited(
        cancel.then((_) {
          if (done.isCompleted) return;
          unawaited(
            abort(
              const AgyUnavailable('Signing in to Antigravity was cancelled'),
            ),
          );
        }),
      );
    }

    final client = await host.ready;
    if (cancelled) {
      throw const AgyUnavailable('Signing in to Antigravity was cancelled');
    }
    final proxyEnv = await _remoteProxyEnv(client);
    if (cancelled) {
      throw const AgyUnavailable('Signing in to Antigravity was cancelled');
    }

    Future<void> handleUrl(
      Uri uri, {
      required int? callbackPort,
      required bool needsCode,
    }) async {
      if (urlHandled || cancelled || done.isCompleted) return;
      urlHandled = true;

      try {
        if (callbackPort != null) {
          bridge = await RemoteOAuthCallbackBridge.start(client, callbackPort);
        }
        if (cancelled || done.isCompleted) {
          final activeBridge = bridge;
          bridge = null;
          await activeBridge?.close();
          return;
        }

        final opener = openUrl ?? _defaultOpenUrl;
        await opener(uri);
        if (cancelled || done.isCompleted) return;

        if (needsCode || bridge == null) {
          final prompt = requestCode;
          if (prompt != null) {
            final code = await prompt(uri, bridgeActive: bridge != null);
            if (cancelled || done.isCompleted) return;
            if (code == null || code.trim().isEmpty) {
              await abort(
                const AgyUnavailable('Signing in to Antigravity was cancelled'),
              );
              return;
            }
            await client.agySubmitAuthCode(code.trim());
          }
        }
      } on AgyUnavailable catch (error, stack) {
        if (!cancelled) {
          final activeSub = subscription;
          subscription = null;
          unawaited(activeSub?.cancel());
          fail(error, stack);
        }
      } on Object catch (error, stack) {
        if (!cancelled) {
          final activeSub = subscription;
          subscription = null;
          unawaited(activeSub?.cancel());
          fail(
            AgyUnavailable(
              'Signing in to Antigravity did not finish',
              detail: '$error',
            ),
            stack,
          );
        }
      }
    }

    try {
      listening = true;
      subscription = client.agySignIn(environment: proxyEnv).listen(
        (event) {
          if (cancelled || done.isCompleted) return;
          switch (event['type']) {
            case 'url':
              final rawUrl = event['url'];
              if (rawUrl is! String || rawUrl.isEmpty) return;
              final uri = Uri.tryParse(rawUrl);
              if (uri == null) return;
              final parsed = parseOAuthUrl(rawUrl);
              final callbackPort = event['callbackPort'] is int
                  ? event['callbackPort'] as int
                  : parsed?.callbackPort;
              final needsCode = event['needsCode'] is bool
                  ? event['needsCode'] as bool
                  : (parsed?.needsCode ?? callbackPort == null);
              unawaited(
                handleUrl(
                  uri,
                  callbackPort: callbackPort,
                  needsCode: needsCode,
                ),
              );
            case 'line':
              if (urlHandled) return;
              final text = event['text'];
              if (text is! String || text.isEmpty) return;
              final info = parseOAuthUrl(text);
              if (info != null) {
                unawaited(
                  handleUrl(
                    info.url,
                    callbackPort: info.callbackPort,
                    needsCode: info.needsCode,
                  ),
                );
              }
            case 'done':
              receivedDone = true;
              if (!done.isCompleted) done.complete();
          }
        },
        onError: (Object error, StackTrace stack) {
          if (cancelled) return;
          if (error is AgyUnavailable) {
            fail(error, stack);
          } else {
            fail(
              AgyUnavailable(
                'Signing in to Antigravity did not finish',
                detail: '$error',
              ),
              stack,
            );
          }
        },
        onDone: () {
          if (cancelled || done.isCompleted) return;
          if (receivedDone) {
            done.complete();
          } else {
            fail(
              const AgyUnavailable(
                'Signing in to Antigravity ended before completing',
              ),
            );
          }
        },
        cancelOnError: true,
      );

      if (cancelled && !done.isCompleted) {
        await abort(
          const AgyUnavailable('Signing in to Antigravity was cancelled'),
        );
      }

      await done.future;
    } finally {
      final activeSub = subscription;
      subscription = null;
      await activeSub?.cancel();
      final activeBridge = bridge;
      bridge = null;
      await activeBridge?.close();
    }
  }
}

/// In-conversation setup state machine for Antigravity ACP on one SSH [host]:
/// checks installation (reusing system-installed `agy` when present), asks for
/// confirmation before downloading, supports fast direct probe -> local cache
/// upload fallback, and drives inline headless OAuth sign-in.
class RemoteAgySetupController extends ChangeNotifier {
  RemoteAgySetupController(
    this.host, {
    this.openUrl,
    this.release,
    this.directProbeTimeout = defaultRemoteAgyProbeTimeout,
    this.downloads,
  });

  final SshHost host;
  final RemoteAgyUrlHandler? openUrl;
  final AgyRelease? release;
  final Duration directProbeTimeout;
  final Directory? downloads;

  RemoteAgySetupStage get stage => _stage;
  RemoteAgySetupStage _stage = RemoteAgySetupStage.idle;

  RemoteAgyInstallPhase? get installPhase => _installPhase;
  RemoteAgyInstallPhase? _installPhase;

  double? get installProgress => _installProgress;
  double? _installProgress;

  Uri? get authUrl => _authUrl;
  Uri? _authUrl;

  bool get bridgeActive => _bridgeActive;
  bool _bridgeActive = false;

  bool get needsCode => _needsCode;
  bool _needsCode = false;

  bool get submittingCode => _submittingCode;
  bool _submittingCode = false;

  String? get error => _error;
  String? _error;

  bool get dismissed => _dismissed;
  bool _dismissed = false;

  /// Incremented each time this host transitions to [RemoteAgySetupStage.ready]
  /// after an install or sign-in, so open conversations can resume seamlessly.
  int get readyEpoch => _readyEpoch;
  int _readyEpoch = 0;

  /// Models returned by the latest successful `agyModels` check.
  List<AgyModel> get models => _models;
  List<AgyModel> _models = const [];

  bool get showsCard =>
      !_dismissed &&
      switch (_stage) {
        RemoteAgySetupStage.needsInstall ||
        RemoteAgySetupStage.installing ||
        RemoteAgySetupStage.needsSignIn ||
        RemoteAgySetupStage.signingIn ||
        RemoteAgySetupStage.error => true,
        RemoteAgySetupStage.idle ||
        RemoteAgySetupStage.checking ||
        RemoteAgySetupStage.ready => false,
      };

  Future<void>? _checking;
  Completer<void>? _installCancel;
  StreamSubscription<Map<String, Object?>>? _signInSub;
  RemoteOAuthCallbackBridge? _bridge;
  RemoteClient? _signInClient;
  bool _signInUrlHandled = false;
  bool _disposed = false;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  /// Checks this host once if not yet inspected or dismissed.
  void ensureChecked() {
    if (_disposed || _dismissed) return;
    if (_stage != RemoteAgySetupStage.idle) return;
    unawaited(check());
  }

  /// Probes whether Antigravity is installed and signed in on [host].
  Future<void> check({bool force = false}) {
    if (!force &&
        (_stage == RemoteAgySetupStage.installing ||
            _stage == RemoteAgySetupStage.signingIn)) {
      return Future.value();
    }
    return _checking ??= _runCheck().whenComplete(() => _checking = null);
  }

  Future<void> _runCheck() async {
    final wasSetupActive =
        _stage == RemoteAgySetupStage.installing ||
        _stage == RemoteAgySetupStage.signingIn ||
        _stage == RemoteAgySetupStage.needsInstall ||
        _stage == RemoteAgySetupStage.needsSignIn;
    _dismissed = false;
    _error = null;
    _stage = RemoteAgySetupStage.checking;
    _emit();
    try {
      final client = await host.ready;
      if (_disposed) return;
      final ver = await client.agyVersion();
      if (_disposed) return;
      if (ver == null) {
        _stage = RemoteAgySetupStage.needsInstall;
        _emit();
        return;
      }
      final proxyEnv = await _remoteProxyEnv(client);
      if (_disposed) return;
      final listed = await client.agyModels(environment: proxyEnv);
      if (_disposed) return;
      _models = listed;
      _stage = RemoteAgySetupStage.ready;
      if (wasSetupActive) _readyEpoch++;
      _emit();
    } on AgyUnavailable catch (e) {
      if (_disposed) return;
      if (e.notInstalled) {
        _stage = RemoteAgySetupStage.needsInstall;
      } else if (e.signIn) {
        _stage = RemoteAgySetupStage.needsSignIn;
      } else {
        _error = '$e';
        _stage = RemoteAgySetupStage.error;
      }
      _emit();
    } on Object {
      if (_disposed) return;
      // Host offline or unreachable is already surfaced by SshHostBanner.
      _stage = RemoteAgySetupStage.idle;
      _emit();
    }
  }

  /// Called when launching an Antigravity turn discovers `agy` is missing.
  void markNeedsInstall() {
    if (_disposed || _stage == RemoteAgySetupStage.installing) return;
    _dismissed = false;
    _error = null;
    _stage = RemoteAgySetupStage.needsInstall;
    _emit();
  }

  /// Called when launching an Antigravity turn discovers `agy` is not signed in.
  void markNeedsSignIn() {
    if (_disposed || _stage == RemoteAgySetupStage.signingIn) return;
    _dismissed = false;
    _error = null;
    _stage = RemoteAgySetupStage.needsSignIn;
    _emit();
  }

  /// Confirms and starts installing Antigravity on [host]. Once installed,
  /// automatically checks sign-in status and opens the sign-in flow if needed.
  Future<void> confirmInstall() async {
    if (_disposed || _stage == RemoteAgySetupStage.installing) return;
    final cancel = _installCancel = Completer<void>();
    _dismissed = false;
    _error = null;
    _installPhase = RemoteAgyInstallPhase.probing;
    _installProgress = null;
    _stage = RemoteAgySetupStage.installing;
    _emit();

    try {
      await installRemoteAgy(
        host,
        downloads: downloads,
        directProbeTimeout: directProbeTimeout,
        cancel: cancel.future,
        release: release,
        onPhase: (phase) {
          if (_disposed || cancel.isCompleted) return;
          _installPhase = phase;
          if (phase == RemoteAgyInstallPhase.probing) {
            _installProgress = null;
          }
          _emit();
        },
        onProgress: (fraction) {
          if (_disposed || cancel.isCompleted) return;
          _installProgress = fraction;
          _emit();
        },
      );
      if (_disposed) return;
      _installCancel = null;
      _installPhase = null;
      _installProgress = null;
      await check(force: true);
      if (!_disposed && _stage == RemoteAgySetupStage.needsSignIn) {
        await startSignIn();
      }
    } on Object catch (e) {
      if (_disposed) return;
      final wasCancelled = cancel.isCompleted;
      _installCancel = null;
      _installPhase = null;
      _installProgress = null;
      if (wasCancelled) {
        _stage = RemoteAgySetupStage.needsInstall;
        _error = null;
      } else {
        _stage = RemoteAgySetupStage.needsInstall;
        _error = '$e';
      }
      _emit();
    }
  }

  /// Cancels an in-flight installation.
  void cancelInstall() {
    final cancel = _installCancel;
    if (cancel != null && !cancel.isCompleted) {
      cancel.complete();
    }
  }

  /// Starts headless OAuth sign-in on [host], opening the browser on this
  /// machine and bridging loopback callbacks when applicable (or exposing an
  /// inline code input inside the card when OOB code entry is required).
  Future<void> startSignIn() async {
    if (_disposed || _stage == RemoteAgySetupStage.signingIn) return;
    await _stopSignInResources();
    _dismissed = false;
    _error = null;
    _authUrl = null;
    _bridgeActive = false;
    _needsCode = false;
    _submittingCode = false;
    _signInUrlHandled = false;
    _stage = RemoteAgySetupStage.signingIn;
    _emit();

    try {
      final client = await host.ready;
      if (_disposed || _stage != RemoteAgySetupStage.signingIn) return;
      _signInClient = client;
      final proxyEnv = await _remoteProxyEnv(client);
      if (_disposed || _stage != RemoteAgySetupStage.signingIn) return;

      var receivedDone = false;
      _signInSub = client.agySignIn(environment: proxyEnv).listen(
        (event) {
          if (_disposed || _stage != RemoteAgySetupStage.signingIn) return;
          switch (event['type']) {
            case 'url':
              final rawUrl = event['url'];
              if (rawUrl is! String || rawUrl.isEmpty) return;
              final uri = Uri.tryParse(rawUrl);
              if (uri == null) return;
              final parsed = parseOAuthUrl(rawUrl);
              final callbackPort = event['callbackPort'] is int
                  ? event['callbackPort'] as int
                  : parsed?.callbackPort;
              final needsCode = event['needsCode'] is bool
                  ? event['needsCode'] as bool
                  : (parsed?.needsCode ?? callbackPort == null);
              unawaited(
                _handleSignInUrl(
                  client,
                  uri,
                  callbackPort: callbackPort,
                  needsCode: needsCode,
                ),
              );
            case 'line':
              if (_signInUrlHandled) return;
              final text = event['text'];
              if (text is! String || text.isEmpty) return;
              final info = parseOAuthUrl(text);
              if (info != null) {
                unawaited(
                  _handleSignInUrl(
                    client,
                    info.url,
                    callbackPort: info.callbackPort,
                    needsCode: info.needsCode,
                  ),
                );
              }
            case 'done':
              receivedDone = true;
              unawaited(_finishSignIn());
          }
        },
        onError: (Object err) {
          if (_disposed || _stage != RemoteAgySetupStage.signingIn) return;
          unawaited(_stopSignInResources());
          _stage = RemoteAgySetupStage.needsSignIn;
          _error = '$err';
          _emit();
        },
        onDone: () {
          if (_disposed || _stage != RemoteAgySetupStage.signingIn) return;
          if (receivedDone) return;
          unawaited(_stopSignInResources());
          _stage = RemoteAgySetupStage.needsSignIn;
          _error = 'Signing in to Antigravity ended before completing';
          _emit();
        },
        cancelOnError: true,
      );
    } on Object catch (err) {
      if (_disposed) return;
      await _stopSignInResources();
      _stage = RemoteAgySetupStage.needsSignIn;
      _error = '$err';
      _emit();
    }
  }

  Future<void> _handleSignInUrl(
    RemoteClient client,
    Uri uri, {
    required int? callbackPort,
    required bool needsCode,
  }) async {
    if (_signInUrlHandled ||
        _disposed ||
        _stage != RemoteAgySetupStage.signingIn) {
      return;
    }
    _signInUrlHandled = true;
    if (callbackPort != null) {
      _bridge = await RemoteOAuthCallbackBridge.start(client, callbackPort);
    }
    if (_disposed || _stage != RemoteAgySetupStage.signingIn) {
      await _bridge?.close();
      _bridge = null;
      return;
    }
    _authUrl = uri;
    _bridgeActive = _bridge != null;
    _needsCode = needsCode || !_bridgeActive;
    _emit();

    try {
      final opener = openUrl ?? _defaultOpenUrl;
      await opener(uri);
    } on Object {
      // User can still click "Open Link" or "Copy Link" in the inline card.
    }
  }

  /// Opens the active OAuth URL again in the browser.
  Future<void> openAuthUrl() async {
    final uri = _authUrl;
    if (uri == null) return;
    final opener = openUrl ?? _defaultOpenUrl;
    await opener(uri);
  }

  /// Submits the authorization code (or full redirect URL) pasted into the
  /// inline card.
  Future<void> submitAuthCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty || _submittingCode) return;
    final client = _signInClient;
    if (client == null) return;
    _submittingCode = true;
    _error = null;
    _emit();
    try {
      await client.agySubmitAuthCode(trimmed);
    } on Object catch (err) {
      if (_disposed) return;
      _submittingCode = false;
      _error = '$err';
      _emit();
    }
  }

  Future<void> _finishSignIn() async {
    await _stopSignInResources();
    if (_disposed) return;
    _submittingCode = false;
    _authUrl = null;
    _bridgeActive = false;
    _needsCode = false;
    _error = null;
    _stage = RemoteAgySetupStage.ready;
    _readyEpoch++;
    _emit();
    // Refresh model list in the background without regressing UI state.
    unawaited(() async {
      try {
        final client = await host.ready;
        final listed = await client.agyModels(
          environment: await _remoteProxyEnv(client),
        );
        if (!_disposed) {
          _models = listed;
          _emit();
        }
      } on Object {
        // Already marked ready; model list can still be refreshed later.
      }
    }());
  }

  /// Cancels an active sign-in flow and returns to [RemoteAgySetupStage.needsSignIn].
  Future<void> cancelSignIn() async {
    await _stopSignInResources();
    if (_disposed) return;
    _authUrl = null;
    _bridgeActive = false;
    _needsCode = false;
    _submittingCode = false;
    _error = null;
    _stage = RemoteAgySetupStage.needsSignIn;
    _emit();
  }

  /// Dismisses the inline card (cancelling any active install or sign-in).
  void dismiss() {
    cancelInstall();
    unawaited(_stopSignInResources());
    _dismissed = true;
    _authUrl = null;
    _bridgeActive = false;
    _needsCode = false;
    _submittingCode = false;
    _error = null;
    if (_stage == RemoteAgySetupStage.installing) {
      _stage = RemoteAgySetupStage.needsInstall;
    } else if (_stage == RemoteAgySetupStage.signingIn) {
      _stage = RemoteAgySetupStage.needsSignIn;
    }
    _emit();
  }

  Future<void> _stopSignInResources() async {
    final sub = _signInSub;
    _signInSub = null;
    await sub?.cancel();
    final bridge = _bridge;
    _bridge = null;
    await bridge?.close();
    _signInClient = null;
  }

  @override
  void dispose() {
    _disposed = true;
    cancelInstall();
    unawaited(_stopSignInResources());
    super.dispose();
  }
}

/// Shared registry of [RemoteAgySetupController]s, one per SSH host.
class RemoteAgySetups {
  RemoteAgySetups({SshHosts? hosts}) : _hostsOverride = hosts;

  static RemoteAgySetups instance = RemoteAgySetups();

  final SshHosts? _hostsOverride;
  final Map<String, RemoteAgySetupController> _controllers = {};

  SshHosts get _hosts => _hostsOverride ?? SshHosts.instance;

  RemoteAgySetupController of(String host) =>
      _controllers[host] ??= RemoteAgySetupController(_hosts[host]);

  void reset() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
  }
}
