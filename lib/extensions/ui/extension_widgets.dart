/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// What the Extensions view, the extension page and the dialogs share: an
// extension's icon, its capability badge and reasons, the prominent and
// secondary buttons, a checkbox, install counts and ratings.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/extensions/browser/extensionsWidgets.ts
// (`InstallCountWidget`, `RatingsWidget`) and media/extensionActions.css.
//
// Deviations: the capability badge is BaoCode's (no webviews).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../capabilities/capability_analysis.dart';
import '../gallery/open_vsx_client.dart';
import '../vsix/engine_version.dart';

/// `InstallCountWidget.getInstallLabel`: `9.4M`, `120K`, `950`.
String formatInstallCount(int count) {
  if (count >= 1000000) {
    final value = count / 1000000;
    return '${value >= 100 ? value.round() : _oneDecimal(value)}M';
  }
  if (count >= 1000) {
    final value = count / 1000;
    return '${value >= 100 ? value.round() : _oneDecimal(value)}K';
  }
  return '$count';
}

String _oneDecimal(double value) {
  final text = value.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// An extension's icon: [bytes] (an installed one's), else [url] fetched
/// through [gallery], else the extensions codicon.
class ExtensionIcon extends StatefulWidget {
  const ExtensionIcon({
    super.key,
    this.bytes,
    this.url,
    this.gallery,
    this.size = 36,
  });

  final Uint8List? bytes;
  final String? url;
  final OpenVsxClient? gallery;
  final double size;

  @override
  State<ExtensionIcon> createState() => _ExtensionIconState();
}

class _ExtensionIconState extends State<ExtensionIcon> {
  Future<Uint8List>? _fetch;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(ExtensionIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.bytes != widget.bytes) {
      _start();
    }
  }

  void _start() {
    final (url, gallery) = (widget.url, widget.gallery);
    _fetch = widget.bytes == null && url != null && gallery != null
        ? gallery.fetchBytes(url)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    Widget fallback() => Icon(
      Codicons.extensions,
      size: size * .8,
      color: themeColors['descriptionForeground'],
    );
    Widget image(Uint8List bytes) {
      final svg = bytes.length > 4 &&
          String.fromCharCodes(bytes.take(256)).contains('<svg');
      return svg
          ? SvgPicture.memory(bytes, width: size, height: size)
          : Image.memory(
              bytes,
              width: size,
              height: size,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => fallback(),
            );
    }

    final Widget child;
    if (widget.bytes case final bytes?) {
      child = image(bytes);
    } else if (_fetch case final fetch?) {
      child = FutureBuilder<Uint8List>(
        future: fetch,
        builder: (context, snapshot) => snapshot.hasData
            ? image(snapshot.data!)
            : snapshot.hasError
            ? fallback()
            : const SizedBox.shrink(),
      );
    } else {
      child = fallback();
    }
    return SizedBox.square(dimension: size, child: Center(child: child));
  }
}

/// The capability level's label, icon and color.
({String label, String detail, IconData icon, Color color}) capabilityStyle(
  AppLocalizations l10n,
  ExtensionCapabilityLevel level,
) => switch (level) {
  ExtensionCapabilityLevel.full => (
    label: l10n.extsCapabilityFull,
    detail: l10n.extsCapabilityFullDetail,
    icon: Codicons.check,
    color: themeColors.get('testing.iconPassed') ?? const Color(0xFF73C991),
  ),
  ExtensionCapabilityLevel.partial => (
    label: l10n.extsCapabilityPartial,
    detail: l10n.extsCapabilityPartialDetail,
    icon: Codicons.warning,
    color: themeColors['editorWarning.foreground'],
  ),
  ExtensionCapabilityLevel.needsWebview => (
    label: l10n.extsCapabilityNeedsWebview,
    detail: l10n.extsCapabilityNeedsWebviewDetail,
    icon: Codicons.circleSlash,
    color: themeColors['errorForeground'],
  ),
};

/// A finding, worded.
String capabilityFindingText(AppLocalizations l10n, CapabilityFinding finding) {
  final detail = finding.detail ?? '';
  return switch (finding.kind) {
    CapabilityFindingKind.webviewView => l10n.extsFindingWebviewView(detail),
    CapabilityFindingKind.customEditor => l10n.extsFindingCustomEditor(detail),
    CapabilityFindingKind.notebook => l10n.extsFindingNotebook(detail),
    CapabilityFindingKind.notebookRenderer => l10n.extsFindingNotebookRenderer(
      detail,
    ),
    CapabilityFindingKind.webviewPanelCode => l10n.extsFindingWebviewPanelCode(
      detail,
    ),
    CapabilityFindingKind.webviewViewCode => l10n.extsFindingWebviewViewCode(
      detail,
    ),
    CapabilityFindingKind.customEditorCode => l10n.extsFindingCustomEditorCode(
      detail,
    ),
    CapabilityFindingKind.notebookCode => l10n.extsFindingNotebookCode(detail),
    CapabilityFindingKind.browserOnly => l10n.extsFindingBrowserOnly,
    CapabilityFindingKind.scanIncomplete => l10n.extsFindingScanIncomplete,
  };
}

String coreFeatureText(AppLocalizations l10n, CoreFeature feature) =>
    switch (feature) {
      CoreFeature.languageFeatures => l10n.extsCoreLanguageFeatures,
      CoreFeature.languageServer => l10n.extsCoreLanguageServer,
      CoreFeature.syntaxHighlighting => l10n.extsCoreSyntaxHighlighting,
      CoreFeature.snippets => l10n.extsCoreSnippets,
      CoreFeature.debugging => l10n.extsCoreDebugging,
      CoreFeature.themes => l10n.extsCoreThemes,
      CoreFeature.tasks => l10n.extsCoreTasks,
      CoreFeature.treeViews => l10n.extsCoreTreeViews,
      CoreFeature.sourceControl => l10n.extsCoreSourceControl,
      CoreFeature.testing => l10n.extsCoreTesting,
      CoreFeature.jsonSchemas => l10n.extsCoreJsonSchemas,
      CoreFeature.terminal => l10n.extsCoreTerminal,
      CoreFeature.authentication => l10n.extsCoreAuthentication,
      CoreFeature.localization => l10n.extsCoreLocalization,
    };

/// Why an `engines.vscode` is not accepted, worded.
String engineNoticeText(AppLocalizations l10n, EngineNotice notice) =>
    switch (notice.kind) {
      EngineNoticeKind.mismatch => l10n.extsEngineIncompatible(
        notice.current,
        notice.requested,
      ),
      EngineNoticeKind.missing => l10n.extsEngineMissing,
      _ => l10n.extsEngineInvalid(notice.requested),
    };

/// The capability as a small pill: icon and label, its detail on hover
/// (a tooltip).
class CapabilityBadge extends StatelessWidget {
  const CapabilityBadge(this.level, {super.key, this.compact = false});

  final ExtensionCapabilityLevel level;

  /// The icon only.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = capabilityStyle(context.l10n, level);
    final icon = Icon(style.icon, size: 14, color: style.color);
    return Tooltip(
      message: '${style.label}: ${style.detail}',
      waitDuration: const Duration(milliseconds: 500),
      child: Semantics(
        label: style.label,
        child: compact
            ? icon
            : Container(
                padding: const EdgeInsets.fromLTRB(4, 1, 6, 1),
                decoration: BoxDecoration(
                  border: Border.all(color: style.color.withValues(alpha: .6)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(width: 3),
                    Text(
                      style.label,
                      style: TextStyle(fontSize: 11, color: style.color),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// The capability, its reasons and what still works, as the extension page
/// and the VSIX sheet show them.
class CapabilitySummary extends StatelessWidget {
  const CapabilitySummary(this.report, {super.key, this.fromManifest = false});

  final CapabilityReport report;

  /// The code was not checked (a gallery extension not installed).
  final bool fromManifest;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = capabilityStyle(l10n, report.level);
    final text = themeColors['foreground'];
    final muted = themeColors['descriptionForeground'];
    final reasons = [
      for (final finding in report.findings) capabilityFindingText(l10n, finding),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CapabilityBadge(report.level),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                style.detail,
                style: TextStyle(fontSize: 12, color: text),
              ),
            ),
          ],
        ),
        for (final reason in reasons)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1, right: 6),
                  child: Icon(Codicons.circleSmallFilled, size: 12, color: muted),
                ),
                Expanded(
                  child: Text(reason, style: TextStyle(fontSize: 12, color: text)),
                ),
              ],
            ),
          ),
        if (report.level == ExtensionCapabilityLevel.partial &&
            report.coreFeatures.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.extsStillWorks(
                [
                  for (final feature in report.coreFeatures)
                    coreFeatureText(l10n, feature),
                ].join(l10n.extsListSeparator),
              ),
              style: TextStyle(fontSize: 12, color: text),
            ),
          ),
        if (fromManifest)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.extsCapabilityFromManifest,
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: muted,
              ),
            ),
          ),
      ],
    );
  }
}

/// `.extension-action.label`: 11px text padded 0 5px within a 1px border;
/// prominent (`extensionButton.prominent*`) or not (`extensionButton.*`).
class ExtensionActionButton extends StatefulWidget {
  const ExtensionActionButton({
    super.key,
    required this.label,
    this.onPressed,
    this.prominent = true,
    this.large = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool prominent;

  /// The extension page's: 13px, padded 2 8.
  final bool large;

  @override
  State<ExtensionActionButton> createState() => _ExtensionActionButtonState();
}

class _ExtensionActionButtonState extends State<ExtensionActionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final colors = themeColors;
    final prefix = widget.prominent
        ? 'extensionButton.prominent'
        : 'extensionButton.';
    String key(String name) => widget.prominent
        ? '$prefix$name'
        : 'extensionButton.${name[0].toLowerCase()}${name.substring(1)}';
    final background =
        colors.get(key(enabled && _hover ? 'HoverBackground' : 'Background')) ??
        colors['button.secondaryBackground'];
    final foreground =
        colors.get(key('Foreground')) ?? colors['button.secondaryForeground'];
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Opacity(
            opacity: enabled ? 1 : .6,
            child: Container(
              constraints: BoxConstraints(maxWidth: widget.large ? 260 : 150),
              margin: const EdgeInsets.only(left: 4),
              padding: widget.large
                  ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
                  : const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: background,
                border: Border.all(
                  color: colors.get('extensionButton.border') ??
                      Colors.transparent,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: widget.large ? 13 : 11,
                  height: widget.large ? 18 / 13 : 14 / 11,
                  color: foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A checkbox with its label, as the dialogs draw theirs.
class ExtensionCheckbox extends StatelessWidget {
  const ExtensionCheckbox({
    super.key,
    required this.checked,
    required this.onChanged,
    this.label,
    this.child,
  });

  final bool checked;

  /// Null: disabled.
  final ValueChanged<bool>? onChanged;
  final String? label;

  /// Instead of [label].
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final enabled = onChanged != null;
    return Semantics(
      checked: checked,
      enabled: enabled,
      label: label,
      onTap: enabled ? () => onChanged!(!checked) : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => onChanged!(!checked) : null,
          child: Opacity(
            opacity: enabled ? 1 : .5,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: colors['checkbox.background'],
                    border: Border.all(color: colors['checkbox.border']),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: checked
                      ? Icon(
                          Codicons.check,
                          size: 16,
                          color: colors['checkbox.foreground'],
                        )
                      : null,
                ),
                Expanded(
                  child:
                      child ??
                      ExcludeSemantics(
                        child: Text(
                          label ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            color: colors['editorWidget.foreground'],
                          ),
                        ),
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `RatingsWidget`: five stars and the count.
class ExtensionRating extends StatelessWidget {
  const ExtensionRating({super.key, required this.rating, this.count});

  final double rating;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final color = themeColors.get('extensionIcon.starForeground') ??
        const Color(0xFFFF8E00);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            rating >= i
                ? Codicons.starFull
                : rating >= i - .5
                ? Codicons.starHalf
                : Codicons.starEmpty,
            size: 14,
            color: color,
          ),
        if (count case final count?)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              '($count)',
              style: TextStyle(
                fontSize: 12,
                color: themeColors['descriptionForeground'],
              ),
            ),
          ),
      ],
    );
  }
}
