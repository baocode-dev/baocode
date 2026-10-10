// Importing extensions from VS Code, Cursor, Windsurf and VSCodium: pick
// the editors, see the plan (what Open VSX has, what is proprietary and
// what could only be copied, each with a checkbox; copies only with
// consent), import, then the report.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ide/ide_button.dart';
import '../../ide/ide_hover.dart';
import '../../keybindings/vscode_import.dart' show VsCodeProduct;
import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../capabilities/capability_analysis.dart';
import '../gallery/extension_management_backend.dart';
import '../import/extension_import.dart';
import '../import/proprietary_extensions.dart';
import 'extension_widgets.dart';

/// Shows the import dialog; completes with the report, or null when
/// nothing was imported.
Future<ImportReport?> showExtensionImportDialog(
  BuildContext context, {
  required ExtensionImportPlanner planner,
  required ExtensionImporter importer,
  required ExtensionManagementBackend backend,
  String? settingsPath,
}) => showGeneralDialog<ImportReport>(
  context: context,
  barrierDismissible: false,
  barrierLabel: context.l10n.commonDismiss,
  barrierColor: const Color(0x80000000),
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) => Center(
    child: ExtensionImportDialog(
      planner: planner,
      importer: importer,
      backend: backend,
      settingsPath: settingsPath,
      onClose: (report) => Navigator.pop(context, report),
    ),
  ),
);

enum _Stage { detecting, choose, planning, plan, running, report }

class ExtensionImportDialog extends StatefulWidget {
  const ExtensionImportDialog({
    super.key,
    required this.planner,
    required this.importer,
    required this.backend,
    required this.onClose,
    this.settingsPath,
    this.initialPlan,
    this.initialReport,
  });

  final ExtensionImportPlanner planner;
  final ExtensionImporter importer;
  final ExtensionManagementBackend backend;
  final ValueChanged<ImportReport?> onClose;

  /// Our `settings.json`, to import the extensions' settings into.
  final String? settingsPath;

  /// Starts at the plan (or the report).
  final ImportPlan? initialPlan;
  final ImportReport? initialReport;

  @override
  State<ExtensionImportDialog> createState() => _ExtensionImportDialogState();
}

class _ExtensionImportDialogState extends State<ExtensionImportDialog> {
  _Stage _stage = _Stage.detecting;
  Map<VsCodeProduct, int> _products = const {};
  final Set<VsCodeProduct> _chosen = {};
  ImportPlan? _plan;
  ImportReport? _report;
  final Set<String> _selected = {};
  bool _importSettings = true;
  (int, int) _progress = (0, 0);
  String? _running;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialReport != null) {
      _report = widget.initialReport;
      _stage = _Stage.report;
    } else if (widget.initialPlan case final plan?) {
      _setPlan(plan);
    } else {
      unawaited(_detect());
    }
  }

  Future<void> _detect() async {
    try {
      final products = await widget.planner.detectProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _chosen.addAll(products.keys);
        _stage = _Stage.choose;
        if (products.length == 1) unawaited(_makePlan());
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _makePlan() async {
    setState(() {
      _stage = _Stage.planning;
      _progress = (0, 0);
      _error = null;
    });
    try {
      final installed = await widget.backend.getInstalled();
      final plan = await widget.planner.plan(
        [
          for (final product in VsCodeProduct.values)
            if (_chosen.contains(product)) product,
        ],
        installed: installed,
        onProgress: (done, total) {
          if (mounted) setState(() => _progress = (done, total));
        },
      );
      if (mounted) setState(() => _setPlan(plan));
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _stage = _Stage.choose;
        });
      }
    }
  }

  void _setPlan(ImportPlan plan) {
    _plan = plan;
    _selected
      ..clear()
      ..addAll(plan.defaultSelection);
    _stage = _Stage.plan;
  }

  Future<void> _run() async {
    final plan = _plan!;
    setState(() {
      _stage = _Stage.running;
      _progress = (0, _selected.length);
    });
    final report = await widget.importer.run(
      plan,
      selected: _selected,
      consented: {
        for (final item in plan.withAction(ImportAction.copyLocal))
          if (_selected.contains(item.key)) item.key,
      },
      settingsPath: _importSettings ? widget.settingsPath : null,
      onProgress: (item, done, total) {
        if (mounted) {
          setState(() {
            _running = item.source.manifest.label;
            _progress = (done, total);
          });
        }
      },
    );
    if (mounted) {
      setState(() {
        _report = report;
        _stage = _Stage.report;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    final size = MediaQuery.sizeOf(context);
    final border = colors.get('widget.border');
    final (body, buttons) = switch (_stage) {
      _Stage.detecting => (_waiting(l10n.extsImportDetecting), <Widget>[]),
      _Stage.choose => (_choose(context), _chooseButtons(context)),
      _Stage.planning => (
        _waiting(
          _progress.$2 == 0
              ? l10n.extsImportDetecting
              : l10n.extsImportScanning(_progress.$1, _progress.$2),
        ),
        <Widget>[],
      ),
      _Stage.plan => (_planList(context), _planButtons(context)),
      _Stage.running => (
        _waiting(
          l10n.extsImportRunning(_running ?? '', _progress.$1, _progress.$2),
        ),
        <Widget>[],
      ),
      _Stage.report => (_reportList(context), _reportButtons(context)),
    };
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_stage != _Stage.running) widget.onClose(_report);
        },
      },
      child: Focus(
        autofocus: true,
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            width: math.min(680, size.width * .92),
            constraints: BoxConstraints(maxHeight: size.height * .85),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors['editorWidget.background'],
              border: border == null ? null : Border.all(color: border),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Color(0x26000000), blurRadius: 20),
              ],
            ),
            child: Column(
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
                          _stage == _Stage.report
                              ? l10n.extsReportTitle
                              : l10n.extsImportTitle,
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
                        onPressed: _stage == _Stage.running
                            ? null
                            : () => widget.onClose(_report),
                      ),
                    ],
                  ),
                ),
                if (_error case final error?)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Text(
                      '$error',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors['errorForeground'],
                      ),
                    ),
                  ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: body,
                  ),
                ),
                if (buttons.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        const Spacer(),
                        for (final button in buttons)
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: button,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _waiting(String text) => SizedBox(
    height: 96,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: themeColors['foreground']),
          ),
        ),
      ],
    ),
  );

  TextStyle get _text =>
      TextStyle(fontSize: 13, color: themeColors['editorWidget.foreground']);
  TextStyle get _muted =>
      TextStyle(fontSize: 12, color: themeColors['descriptionForeground']);

  Widget _choose(BuildContext context) {
    final l10n = context.l10n;
    if (_products.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(l10n.extsImportNoEditors, style: _text),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.extsImportFrom, style: _text),
        const SizedBox(height: 8),
        for (final MapEntry(key: product, value: count) in _products.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ExtensionCheckbox(
              checked: _chosen.contains(product),
              label: l10n.extsImportProduct(product.label, count),
              onChanged: (value) => setState(() {
                if (value) {
                  _chosen.add(product);
                } else {
                  _chosen.remove(product);
                }
              }),
            ),
          ),
      ],
    );
  }

  List<Widget> _chooseButtons(BuildContext context) => [
    IdeButton(
      label: context.l10n.extsImportContinue,
      onPressed: _chosen.isEmpty ? null : () => unawaited(_makePlan()),
    ),
    IdeButton(
      label: context.l10n.commonCancel,
      secondary: true,
      onPressed: () => widget.onClose(null),
    ),
  ];

  Widget _planList(BuildContext context) {
    final l10n = context.l10n;
    final plan = _plan!;
    final sections = [
      (ImportAction.reinstall, l10n.extsImportSectionReinstall),
      (ImportAction.proprietary, l10n.extsImportSectionProprietary),
      (ImportAction.copyLocal, l10n.extsImportSectionCopy),
      (ImportAction.unavailable, l10n.extsImportSectionUnavailable),
      (ImportAction.skip, l10n.extsImportSectionSkipped),
    ];
    final settingsCount = plan.settings.only(_selected).settings.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.extsImportSummary(
            plan.items.length,
            plan.products.map((product) => product.label).join(', '),
          ),
          style: _muted,
        ),
        const SizedBox(height: 8),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final (action, title) in sections)
                if (plan.withAction(action).isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      '$title (${plan.withAction(action).length})',
                      style: _text.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  for (final item in plan.withAction(action)) _planItem(item),
                ],
            ],
          ),
        ),
        if (widget.settingsPath != null && !plan.settings.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ExtensionCheckbox(
              checked: _importSettings && settingsCount > 0,
              label: l10n.extsImportSettings(settingsCount),
              onChanged: settingsCount == 0
                  ? null
                  : (value) => setState(() => _importSettings = value),
            ),
          ),
      ],
    );
  }

  Widget _planItem(ImportPlanItem item) {
    final l10n = context.l10n;
    final manifest = item.source.manifest;
    final selected = _selected.contains(item.key);
    final details = <Widget>[];
    switch (item.action) {
      case ImportAction.reinstall:
        details.add(
          Text(
            [
              l10n.extsImportVersions(
                item.source.version,
                item.gallery!.version,
              ),
              if (item.preReleaseFallback) l10n.extsImportPreReleaseOnly,
            ].join(' · '),
            style: _muted,
          ),
        );
      case ImportAction.proprietary:
        details.add(
          Text(_proprietaryText(l10n, item.rule!.reason), style: _muted),
        );
        final available = item.alternatives.where((a) => a.available);
        details.add(
          Text(
            item.alternatives.isEmpty
                ? l10n.extsImportNoAlternative
                : available.isEmpty
                ? l10n.extsImportAlternativeUnavailable(
                    item.alternatives.map((a) => a.id).join(', '),
                  )
                : l10n.extsImportAlternative(
                    available.first.gallery!.label,
                    available.first.id,
                  ),
            style: _muted,
          ),
        );
      case ImportAction.copyLocal:
        details.add(
          Text(
            switch (item.galleryProblem) {
              ImportGalleryProblem.incompatibleEngine =>
                l10n.extsImportCopyEngine,
              ImportGalleryProblem.noCompatiblePlatform =>
                l10n.extsImportCopyPlatform,
              _ => l10n.extsImportCopyNotFound,
            },
            style: _muted,
          ),
        );
        details.add(Text(l10n.extsImportCopyConsent, style: _muted));
      case ImportAction.skip:
        details.add(
          Text(
            item.skipReason == ImportSkipReason.alreadyInstalled
                ? l10n.extsImportSkipInstalled
                : l10n.extsImportSkipEditor,
            style: _muted,
          ),
        );
      case ImportAction.unavailable:
        details.add(
          Text(l10n.extsImportUnavailable(item.error ?? ''), style: _muted),
        );
    }
    final capability = item.capability;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ExtensionCheckbox(
        checked: selected,
        label: manifest.label,
        onChanged: item.selectable
            ? (value) => setState(() {
                if (value) {
                  _selected.add(item.key);
                } else {
                  _selected.remove(item.key);
                }
              })
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExtensionIcon(bytes: manifest.iconBytes, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          manifest.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _text.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          item.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _muted,
                        ),
                      ),
                      if (capability != null &&
                          capability.level != ExtensionCapabilityLevel.full)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: CapabilityBadge(capability.level),
                        ),
                    ],
                  ),
                  ...details,
                  Text(
                    item.source.products.map((p) => p.label).join(', '),
                    style: _muted.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _proprietaryText(AppLocalizations l10n, ProprietaryReason reason) =>
      switch (reason) {
        ProprietaryReason.license => l10n.extsProprietaryLicense,
        ProprietaryReason.remoteDevelopment => l10n.extsProprietaryRemote,
        ProprietaryReason.aiAssistant => l10n.extsProprietaryAi,
        ProprietaryReason.notebooks => l10n.extsProprietaryNotebooks,
      };

  List<Widget> _planButtons(BuildContext context) {
    final count = _plan!.items
        .where((item) => item.selectable && _selected.contains(item.key))
        .length;
    return [
      IdeButton(
        label: context.l10n.extsImportButton(count),
        onPressed: count == 0 ? null : () => unawaited(_run()),
      ),
      IdeButton(
        label: context.l10n.commonCancel,
        secondary: true,
        onPressed: () => widget.onClose(null),
      ),
    ];
  }

  Widget _reportList(BuildContext context) {
    final l10n = context.l10n;
    final report = _report!;
    final colors = themeColors;
    final ok = colors.get('testing.iconPassed') ?? const Color(0xFF73C991);
    (IconData, Color, String) line(ImportReportEntry entry) =>
        switch (entry.outcome) {
          ImportOutcome.installed => (
            Codicons.check,
            ok,
            l10n.extsReportInstalled(entry.version ?? ''),
          ),
          ImportOutcome.alternativeInstalled => (
            Codicons.check,
            ok,
            l10n.extsReportAlternative(entry.alternativeId ?? ''),
          ),
          ImportOutcome.copied => (Codicons.check, ok, l10n.extsReportCopied),
          ImportOutcome.notImported => (
            Codicons.circleSlash,
            colors['descriptionForeground'],
            l10n.extsReportNotImported,
          ),
          ImportOutcome.failed => (
            Codicons.error,
            colors['errorForeground'],
            l10n.extsReportFailed(entry.error ?? ''),
          ),
        };
    final order = [
      ImportOutcome.failed,
      ImportOutcome.installed,
      ImportOutcome.alternativeInstalled,
      ImportOutcome.copied,
      ImportOutcome.notImported,
    ];
    final entries = [...report.entries]
      ..sort((a, b) => order.indexOf(a.outcome) - order.indexOf(b.outcome));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.extsReportSummary(
            report.count(ImportOutcome.installed) +
                report.count(ImportOutcome.alternativeInstalled) +
                report.count(ImportOutcome.copied),
            report.count(ImportOutcome.failed),
          ),
          style: _text,
        ),
        const SizedBox(height: 8),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(line(entry).$1, size: 14, color: line(entry).$2),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: entry.label,
                                style: _text.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              TextSpan(text: '  ${line(entry).$3}', style: _muted),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (report.settingsAdded.isNotEmpty || report.settingsKept.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              l10n.extsReportSettings(
                report.settingsAdded.length,
                report.settingsKept.length,
              ),
              style: _text,
            ),
          ),
        if (report.settingsError case final error?)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              l10n.extsReportSettingsFailed(error),
              style: _text.copyWith(color: colors['errorForeground']),
            ),
          ),
      ],
    );
  }

  List<Widget> _reportButtons(BuildContext context) => [
    IdeButton(
      label: context.l10n.commonClose,
      onPressed: () => widget.onClose(_report),
    ),
  ];
}
