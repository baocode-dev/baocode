// Inline in-conversation setup card for Antigravity ACP on an SSH host, styled
// after the browser_watch card (_WatchCard): prompts before installing (when no
// system `agy` is found on the host), shows direct-probe vs local-relay
// transfer progress with cancel, and completes headless OAuth sign-in inline.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ide/ide_button.dart';
import '../ide/ide_input.dart';
import '../l10n/l10n.dart';
import '../models/model_provider.dart';
import '../models/model_providers.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'remote_agy.dart';
import 'remote_location.dart';

/// Shown above the composer in a remote SSH conversation when an Antigravity
/// ACP model is selected and the host needs installation or Google sign-in.
///
/// Mirrors the visual rhythm of `browser_watch`'s `_WatchCard`: a compact
/// bordered card with a status dot, title, concise instructions, inline input
/// when manual OAuth code entry is needed, and Cancel / primary action buttons.
class RemoteAgySetupCard extends StatefulWidget {
  const RemoteAgySetupCard({
    super.key,
    required this.location,
    required this.model,
    this.onReady,
    this.controller,
    this.providers,
  });

  /// The conversation's working directory (`ssh://<host>/...` for remote).
  final String? location;

  /// The currently selected model ref (`<provider>/<model>`).
  final String? model;

  /// Called when the host becomes ready after an install or sign-in flow so
  /// the conversation can automatically retry / resume.
  final VoidCallback? onReady;

  /// Explicit controller override under test.
  final RemoteAgySetupController? controller;

  /// Providers registry override under test.
  final ModelProviders? providers;

  @override
  State<RemoteAgySetupCard> createState() => _RemoteAgySetupCardState();
}

class _RemoteAgySetupCardState extends State<RemoteAgySetupCard> {
  final _codeController = TextEditingController();
  RemoteAgySetupController? _controller;
  int _lastReadyEpoch = 0;
  bool _copied = false;
  Timer? _copiedTimer;

  String? get _host => switch (widget.location) {
    final location? => RemoteLocation.hostOf(location),
    null => null,
  };

  bool get _isAgyModel {
    if (widget.controller != null) return true;
    final ref = widget.model;
    if (ref == null || ref.isEmpty) return false;
    final resolved = (widget.providers ?? ModelProviders.current).resolve(ref);
    if (resolved == null) return false;
    final (provider, info) = resolved;
    return provider.protocolOf(info) == ProviderProtocol.agy;
  }

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant RemoteAgySetupCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location ||
        oldWidget.model != widget.model ||
        oldWidget.controller != widget.controller) {
      _syncController();
    }
  }

  void _syncController() {
    final next = _resolveController();
    if (!identical(_controller, next)) {
      _controller?.removeListener(_onControllerChanged);
      _controller = next;
      _lastReadyEpoch = next?.readyEpoch ?? 0;
      _controller?.addListener(_onControllerChanged);
    }
    if (next != null) {
      next.ensureChecked();
    }
  }

  RemoteAgySetupController? _resolveController() {
    if (widget.controller case final explicit?) return explicit;
    final host = _host;
    if (host == null || !_isAgyModel) return null;
    return RemoteAgySetups.instance.of(host);
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.readyEpoch > _lastReadyEpoch) {
      _lastReadyEpoch = controller.readyEpoch;
      _codeController.clear();
      widget.onReady?.call();
    }
    if (mounted) setState(() {});
  }

  Future<void> _copyLink(Uri url) async {
    await Clipboard.setData(ClipboardData(text: url.toString()));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _submitCode(RemoteAgySetupController controller) {
    final text = _codeController.text.trim();
    if (text.isEmpty || controller.submittingCode) return;
    unawaited(controller.submitAuthCode(text));
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    _copiedTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.showsCard) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    final hostName = RemoteLocation.hostName(controller.host.host);
    final muted = TextStyle(color: AppColors.textMuted, fontSize: 12);
    final dotColor = switch (controller.stage) {
      RemoteAgySetupStage.needsInstall ||
      RemoteAgySetupStage.needsSignIn => AppColors.caution,
      RemoteAgySetupStage.installing ||
      RemoteAgySetupStage.signingIn => AppColors.accent,
      RemoteAgySetupStage.error => AppColors.removed,
      _ => AppColors.accent,
    };
    final title = switch (controller.stage) {
      RemoteAgySetupStage.needsInstall => l10n.agyRemoteInstallTitle(hostName),
      RemoteAgySetupStage.installing => l10n.agyRemoteInstallingTitle(hostName),
      RemoteAgySetupStage.needsSignIn ||
      RemoteAgySetupStage.signingIn => l10n.agyRemoteSignInTitle(hostName),
      RemoteAgySetupStage.error => l10n.agyRemoteErrorTitle(hostName),
      _ => '',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.bubbleFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ..._body(context, controller, hostName, muted),
        ],
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    RemoteAgySetupController controller,
    String hostName,
    TextStyle muted,
  ) {
    final l10n = context.l10n;
    final error = controller.error;
    switch (controller.stage) {
      case RemoteAgySetupStage.needsInstall:
        return [
          Text(l10n.agyRemoteInstallHint(hostName), style: muted),
          if (error != null) _errorText(error),
          const SizedBox(height: 10),
          Row(
            children: [
              const Spacer(),
              IdeButton(
                label: l10n.commonCancel,
                secondary: true,
                onPressed: controller.dismiss,
              ),
              const SizedBox(width: 8),
              IdeButton(
                label: l10n.agyInstall,
                icon: Codicons.cloudDownload,
                onPressed: () => unawaited(controller.confirmInstall()),
              ),
            ],
          ),
        ];

      case RemoteAgySetupStage.installing:
        final progress = controller.installProgress;
        final percent = progress == null ? null : (progress * 100).round();
        final statusText = switch (controller.installPhase) {
          RemoteAgyInstallPhase.probing || null =>
            l10n.agyRemoteInstallProbing(hostName),
          RemoteAgyInstallPhase.remoteDownloading =>
            percent == null
                ? l10n.agyRemoteInstallDirect(hostName)
                : l10n.agyRemoteInstallDirectProgress(hostName, percent),
          RemoteAgyInstallPhase.localDownloading =>
            percent == null
                ? l10n.agyRemoteInstallLocal(hostName)
                : l10n.agyRemoteInstallLocalProgress(hostName, percent),
          RemoteAgyInstallPhase.uploading =>
            l10n.agyRemoteInstallUploading(hostName, percent ?? 0),
        };
        return [
          Text(statusText, style: muted),
          const SizedBox(height: 8),
          SizedBox(
            height: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: controller.installPhase == RemoteAgyInstallPhase.probing
                    ? null
                    : progress,
                color: themeColors['progressBar.background'],
                backgroundColor: themeColors['editorWidget.border'],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Spacer(),
              IdeButton(
                label: l10n.commonCancel,
                secondary: true,
                onPressed: controller.cancelInstall,
              ),
            ],
          ),
        ];

      case RemoteAgySetupStage.needsSignIn:
        return [
          Text(l10n.agyRemoteSignInPrompt(hostName), style: muted),
          if (error != null) _errorText(error),
          const SizedBox(height: 10),
          Row(
            children: [
              const Spacer(),
              IdeButton(
                label: l10n.commonCancel,
                secondary: true,
                onPressed: controller.dismiss,
              ),
              const SizedBox(width: 8),
              IdeButton(
                label: l10n.agyRemoteSignInStart,
                icon: Codicons.account,
                onPressed: () => unawaited(controller.startSignIn()),
              ),
            ],
          ),
        ];

      case RemoteAgySetupStage.signingIn:
        final url = controller.authUrl;
        final showCodeInput = url != null && controller.needsCode;
        final hint = url == null
            ? l10n.agyRemoteSignInPreparing
            : showCodeInput
            ? l10n.agyRemoteSignInPasteHint
            : l10n.agyRemoteSignInWaitingBrowser;
        return [
          Text(hint, style: muted),
          if (showCodeInput) ...[
            const SizedBox(height: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _codeController,
              builder: (context, _, _) => IgnorePointer(
                ignoring: controller.submittingCode,
                child: IdeInputBox(
                  controller: _codeController,
                  placeholder: l10n.agyRemoteCodePlaceholder,
                  semanticsLabel: l10n.agyRemoteCodePlaceholder,
                  onSubmitted: (_) => _submitCode(controller),
                ),
              ),
            ),
          ],
          if (error != null) _errorText(error),
          const SizedBox(height: 10),
          Row(
            children: [
              if (url != null) ...[
                IdeButton(
                  label: l10n.agyRemoteOpenLink,
                  icon: Codicons.linkExternal,
                  secondary: true,
                  onPressed: () => unawaited(controller.openAuthUrl()),
                ),
                const SizedBox(width: 6),
                IdeButton(
                  label: _copied
                      ? l10n.agyRemoteLinkCopied
                      : l10n.agyRemoteCopyLink,
                  icon: _copied ? Codicons.check : Codicons.copy,
                  secondary: true,
                  onPressed: () => unawaited(_copyLink(url)),
                ),
              ],
              const Spacer(),
              IdeButton(
                label: l10n.commonCancel,
                secondary: true,
                onPressed: () => unawaited(controller.cancelSignIn()),
              ),
              if (showCodeInput) ...[
                const SizedBox(width: 8),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _codeController,
                  builder: (context, value, _) => IdeButton(
                    label: l10n.agyRemoteCodeSubmit,
                    spinning: controller.submittingCode,
                    onPressed:
                        controller.submittingCode || value.text.trim().isEmpty
                        ? null
                        : () => _submitCode(controller),
                  ),
                ),
              ],
            ],
          ),
        ];

      case RemoteAgySetupStage.error:
        return [
          if (error != null) _errorText(error, topPadding: 0),
          const SizedBox(height: 10),
          Row(
            children: [
              const Spacer(),
              IdeButton(
                label: l10n.commonCancel,
                secondary: true,
                onPressed: controller.dismiss,
              ),
              const SizedBox(width: 8),
              IdeButton(
                label: l10n.agyRemoteRetry,
                onPressed: () => unawaited(controller.check(force: true)),
              ),
            ],
          ),
        ];

      case RemoteAgySetupStage.idle ||
          RemoteAgySetupStage.checking ||
          RemoteAgySetupStage.ready:
        return const [];
    }
  }

  Widget _errorText(String message, {double topPadding = 6}) => Padding(
    padding: EdgeInsets.only(top: topPadding),
    child: SelectableText(
      message,
      style: TextStyle(
        color: themeColors['errorForeground'],
        fontSize: 12,
      ),
    ),
  );
}
