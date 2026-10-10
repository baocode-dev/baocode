// Dropping theme extensions on the workbench: a `.vsix` shows what it is
// (its manifest, whether it works with this VS Code and platform, what of
// it applies) and installs once confirmed.
//
// The workbench's drop handling (lib/ide/ide_workbench.dart) calls
// [handleExtensionDrop] with the dropped paths first; it returns whether
// it took them.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../ide/ide_button.dart';
import '../../ide/ide_hover.dart';
import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../capabilities/capability_analysis.dart';
import '../gallery/extension_management_backend.dart';
import '../vsix/target_platform.dart';
import '../vsix/vsix_reader.dart';
import 'extension_widgets.dart';

/// Whether [path] is a .vsix dropped (what the workbench takes rather
/// than opens).
bool isVsixDrop(String path) => path.toLowerCase().endsWith('.vsix');

/// Shows each .vsix among [paths] through [showVsixInstallSheet]. Returns
/// false when none was one (the workbench opens them as it would).
Future<bool> handleExtensionDrop(
  BuildContext context,
  List<String> paths, {
  required ExtensionManagementBackend backend,
  String? locale,
  ValueChanged<InstalledExtension>? onInstalled,
}) async {
  final vsixes = [
    for (final path in paths)
      if (isVsixDrop(path) && await File(path).exists()) path,
  ];
  for (final path in vsixes) {
    if (!context.mounted) break;
    final installed = await showVsixInstallSheet(
      context,
      path,
      backend: backend,
      locale: locale,
    );
    if (installed != null) onInstalled?.call(installed);
  }
  return vsixes.isNotEmpty;
}

/// Shows what the .vsix at [path] is and installs it once confirmed:
/// what it installed, or null.
Future<InstalledExtension?> showVsixInstallSheet(
  BuildContext context,
  String path, {
  required ExtensionManagementBackend backend,
  String? locale,
}) => showGeneralDialog<InstalledExtension>(
  context: context,
  barrierDismissible: true,
  barrierLabel: context.l10n.commonDismiss,
  barrierColor: const Color(0x80000000),
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) => Align(
    alignment: const Alignment(0, -0.6),
    child: VsixInstallSheet(
      path: path,
      backend: backend,
      locale: locale,
      onClose: (installed) => Navigator.pop(context, installed),
    ),
  ),
);

/// The confirmation: the package's manifest, compatibility and capability,
/// and Install.
class VsixInstallSheet extends StatefulWidget {
  const VsixInstallSheet({
    super.key,
    required this.path,
    required this.backend,
    required this.onClose,
    this.locale,
    this.platform,
  });

  final String path;
  final ExtensionManagementBackend backend;
  final ValueChanged<InstalledExtension?> onClose;
  final String? locale;

  /// This machine's when null.
  final ExtensionTargetPlatform? platform;

  @override
  State<VsixInstallSheet> createState() => _VsixInstallSheetState();
}

class _VsixInstallSheetState extends State<VsixInstallSheet> {
  late final Future<_Preview> _preview = _read();
  bool _installing = false;
  Object? _error;

  Future<_Preview> _read() async {
    final package = await ExtensionPackage.openVsix(
      widget.path,
      locale: widget.locale,
    );
    try {
      final capability = analyzeExtensionPackage(package);
      final installed = await widget.backend.getInstalled();
      final current = installed
          .where((e) => e.key == package.manifest.key)
          .firstOrNull;
      return _Preview(package, capability, current);
    } finally {
      await package.close();
    }
  }

  Future<void> _install(_Preview preview) async {
    setState(() {
      _installing = true;
      _error = null;
    });
    try {
      final installed = await widget.backend.install(
        widget.path,
        options: ExtensionInstallOptions(
          preRelease: preview.package.manifest.preRelease,
        ),
      );
      if (mounted) widget.onClose(installed);
    } catch (error) {
      if (mounted) {
        setState(() {
          _installing = false;
          _error = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    final border = colors.get('widget.border');
    final width = math.max(
      480.0,
      math.min(600.0, MediaQuery.sizeOf(context).width * .9),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            widget.onClose(null),
      },
      child: Focus(
        autofocus: true,
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            width: width,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors['editorWidget.background'],
              border: border == null ? null : Border.all(color: border),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Color(0x26000000), blurRadius: 20),
              ],
            ),
            child: FutureBuilder<_Preview>(
              future: _preview,
              builder: (context, snapshot) {
                final preview = snapshot.data;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 24,
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l10n.extsVsixTitle,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colors['editorWidget.foreground'],
                              ),
                            ),
                          ),
                          IdeActionButton(
                            icon: Codicons.close,
                            tooltip: l10n.dialogCloseDialog,
                            onPressed: () => widget.onClose(null),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: snapshot.hasError
                          ? _problem(
                              l10n.extsVsixInvalid(
                                p.basename(widget.path),
                                _errorText(snapshot.error!),
                              ),
                            )
                          : preview == null
                          ? const SizedBox(
                              height: 80,
                              child: Center(
                                child: SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            )
                          : _content(context, preview),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: IdeButton(
                              label: l10n.extInstall,
                              spinning: _installing,
                              onPressed:
                                  preview == null ||
                                      _installing ||
                                      !preview.installable(
                                        widget.platform ??
                                            ExtensionTargetPlatform.current,
                                      )
                                  ? null
                                  : () => unawaited(_install(preview)),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: IdeButton(
                              label: l10n.commonCancel,
                              secondary: true,
                              onPressed: () => widget.onClose(null),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _errorText(Object error) => switch (error) {
    ExtensionPackageException(:final message) => message,
    _ => '$error',
  };

  Widget _problem(String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Codicons.error, size: 16, color: themeColors['errorForeground']),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: TextStyle(fontSize: 13, color: themeColors['foreground']),
        ),
      ),
    ],
  );

  Widget _content(BuildContext context, _Preview preview) {
    final l10n = context.l10n;
    final colors = themeColors;
    final manifest = preview.package.manifest;
    final platform = widget.platform ?? ExtensionTargetPlatform.current;
    final foreground = colors['editorWidget.foreground'];
    final muted = colors['descriptionForeground'];
    final ok = colors.get('testing.iconPassed') ?? const Color(0xFF73C991);
    final bad = colors['errorForeground'];
    Widget check(bool good, String text) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            good ? Codicons.check : Codicons.error,
            size: 14,
            color: good ? ok : bad,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: foreground),
            ),
          ),
        ],
      ),
    );
    final current = preview.current;
    final platformOk = manifest.targetPlatform.isCompatibleWith(platform);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExtensionIcon(bytes: manifest.iconBytes, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    manifest.label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${manifest.id} · v${manifest.version}'
                    '${manifest.preRelease ? ' · ${l10n.extsPreRelease}' : ''}',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  if (manifest.description case final description?)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        description,
                        style: TextStyle(fontSize: 13, color: foreground),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        check(
          manifest.engineCompatible,
          manifest.engineCompatible
              ? l10n.extsEngineCompatible(manifest.engine ?? '*')
              : manifest.engineNotices
                    .map((notice) => engineNoticeText(l10n, notice))
                    .join(' '),
        ),
        check(
          platformOk,
          platformOk
              ? l10n.extsPlatformCompatible(
                  manifest.targetPlatform.isSpecific
                      ? manifest.targetPlatform.label
                      : l10n.extsPlatformUniversal,
                )
              : l10n.extsVsixPlatformMismatch(
                  manifest.targetPlatform.label,
                  platform.label,
                ),
        ),
        if (current != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Codicons.info, size: 14, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.extsVsixReplaces(current.version),
                    style: TextStyle(fontSize: 12, color: foreground),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        CapabilitySummary(preview.capability),
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _problem(l10n.extInstallError(manifest.id, '$error')),
          ),
      ],
    );
  }
}

class _Preview {
  _Preview(this.package, this.capability, this.current);

  final ExtensionPackage package;
  final CapabilityReport capability;

  /// The installed version it replaces.
  final InstalledExtension? current;

  bool installable(ExtensionTargetPlatform platform) =>
      capability.installable &&
      package.manifest.engineCompatible &&
      package.manifest.targetPlatform.isCompatibleWith(platform);
}
