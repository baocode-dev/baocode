import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../ide/ide_button.dart';
import '../../ide/ide_hover.dart';
import '../../ide/ide_input.dart';
import '../../l10n/l10n.dart';
import '../../models/featured_upstreams.dart';
import '../../models/model_icons.dart';
import '../../models/model_providers.dart';
import '../../models/model_runtime.dart';
import '../../models/upstream.dart';
import '../../models/upstream_import.dart';
import '../../theme/codicons.dart';
import '../../theme/ui_tokens.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'model_dialogs.dart';
import 'models_page.dart';

/// Asks whether to add the upstream a site handed over ([UpstreamImport]):
/// the site, as BaoCode lists it when it does, its name (to change), where
/// requests go, how, and its key masked; then fetches its models ([list])
/// for the user to check those to offer, and adds it with them; or, when it
/// is one there already, gives that one the key. Nothing is added without
/// the user's yes. Completes with the upstream's id; null when the user
/// said no, to either.
Future<String?> showUpstreamImportDialog(
  BuildContext context,
  UpstreamImport import, {
  ModelProviders? providers,
  Future<List<FeaturedUpstream>>? featured,
  ModelLister list = listUpstreamModels,
}) async {
  final store = providers ?? ModelProviders.current;
  final listed = FeaturedUpstream.at(
    import.host,
    await (featured ?? FeaturedUpstream.load()),
  );
  if (!context.mounted) return null;
  final l10n = context.l10n;
  final existing = import.existingIn(store.providers);
  final hasKey = import.key.isNotEmpty;
  final buttons = [
    if (existing == null)
      l10n.modelsImportAdd
    else ...[
      hasKey
          ? l10n.modelsImportUpdateKey(existing.name)
          : l10n.modelsImportOpenExisting(existing.name),
      l10n.modelsImportAsNew,
    ],
  ];
  final result = await showGeneralDialog<(int, String)>(
    context: context,
    // Closed by its buttons, Escape or the close button: a click beside
    // it would lose what was typed.
    barrierDismissible: false,
    barrierLabel: l10n.commonDismiss,
    barrierColor: const Color(0x80000000),
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => _ImportDialog(
      import: import,
      listed: listed,
      existing: existing?.name,
      buttons: buttons,
    ),
  );
  if (result == null) return null;
  final (button, typed) = result;
  if (existing != null && button == 0) {
    if (hasKey) await store.setKey(existing.id, import.key);
    return existing.id;
  }
  final name = typed.trim().isEmpty ? import.name : typed.trim();
  final id = store.newId(name);
  final provider = UpstreamImport(
    name: name,
    protocol: import.protocol,
    baseUrl: import.baseUrl,
  ).toProvider(id);
  if (!context.mounted) return null;
  final models = await showFetchModelsDialog(
    context,
    provider: provider,
    key: () async => hasKey ? import.key : null,
    list: list,
    apply: context.l10n.modelsImportFinish,
    skip: context.l10n.modelsImportWithoutModels,
    loading: context.l10n.modelsImportPreparing,
    // The site, and the upstream's name, while its models are got.
    loadingLead: Row(
      children: [
        _SiteLogo(import: import, listed: listed, size: 28),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: UiText.reading,
              fontWeight: FontWeight.w600,
              color: themeColors['editorWidget.foreground'],
            ),
          ),
        ),
      ],
    ),
    minLoading: const Duration(seconds: 2),
  );
  if (models == null) return null;
  await store.save(provider.copyWith(models: models));
  if (hasKey) await store.setKey(id, import.key);
  return id;
}

/// The import's dialog, in the IDE's dialog's chrome (see `ide_dialog.dart`):
/// the site at the top, what is imported as a form, the buttons, Cancel
/// last. Pops with the button chosen and the name typed; null when
/// dismissed.
class _ImportDialog extends StatefulWidget {
  const _ImportDialog({
    required this.import,
    required this.listed,
    required this.existing,
    required this.buttons,
  });

  final UpstreamImport import;
  final FeaturedUpstream? listed;

  /// The name of the upstream it is there as already.
  final String? existing;
  final List<String> buttons;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  late final _name = TextEditingController(text: widget.import.name);
  var _closed = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Once: Enter in the name is both a shortcut here and its submission.
  void _close(int? button) {
    if (_closed) return;
    _closed = true;
    Navigator.pop(context, button == null ? null : (button, _name.text));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    final import = widget.import;
    final listed = widget.listed;
    final foreground = colors['editorWidget.foreground'];
    final dim = colors['descriptionForeground'];
    final border = colors.get('widget.border');
    final shadow = colors.get('widget.shadow');
    final width = math.max(
      480.0,
      math.min(560.0, MediaQuery.sizeOf(context).width * .9),
    );
    final about = listed?.describe(
      Localizations.localeOf(context).languageCode,
    );

    Widget field(String label, Widget value) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(fontSize: UiText.secondary, color: dim),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );
    Widget text(String value, {Color? color}) => SelectableText(
      value,
      maxLines: 1,
      style: TextStyle(fontSize: UiText.body, color: color ?? foreground),
    );
    Widget note(IconData icon, String value) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: dim),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: UiText.secondary,
                height: 18 / 12,
                color: dim,
              ),
            ),
          ),
        ],
      ),
    );

    final buttons = [...widget.buttons, l10n.commonCancel];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => _close(null),
        const SingleActivator(LogicalKeyboardKey.enter): () => _close(0),
      },
      child: Focus(
        autofocus: true,
        child: Align(
          alignment: const Alignment(0, -0.6),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: width,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors['editorWidget.background'],
                border: border == null ? null : Border.all(color: border),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  const BoxShadow(color: Color(0x26000000), blurRadius: 20),
                  if (shadow != null) BoxShadow(color: shadow, blurRadius: 8),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 24,
                    child: Align(
                      alignment: Alignment.topRight,
                      child: IdeActionButton(
                        icon: Codicons.close,
                        tooltip: l10n.dialogCloseDialog,
                        onPressed: () => _close(null),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            _SiteLogo(import: import, listed: listed),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          listed?.name ??
                                              l10n.modelsImportTitle(
                                                import.host,
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: UiText.title,
                                            fontWeight: FontWeight.w600,
                                            color: foreground,
                                          ),
                                        ),
                                      ),
                                      if (listed != null) ...[
                                        const SizedBox(width: 8),
                                        _Badge(l10n.modelsImportListedBadge),
                                      ],
                                    ],
                                  ),
                                  if (listed != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      about ?? import.host,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: UiText.secondary,
                                        color: dim,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        field(
                          l10n.modelsImportNamePlaceholder,
                          IdeInputBox(
                            controller: _name,
                            placeholder: import.name,
                            autofocus: true,
                            semanticsLabel: l10n.modelsImportNamePlaceholder,
                            onSubmitted: (_) => _close(0),
                          ),
                        ),
                        field(
                          l10n.modelsImportProtocol,
                          text(
                            ModelsSettingsPage.protocolName(
                              context,
                              import.protocol,
                            ),
                          ),
                        ),
                        field(l10n.modelsImportUrl, text(import.baseUrl)),
                        field(
                          l10n.modelsImportKeyLabel,
                          import.key.isEmpty
                              ? text(l10n.modelsImportNoKey, color: dim)
                              : text(import.maskedKey),
                        ),
                        const SizedBox(height: 10),
                        if (widget.existing case final name?)
                          note(Codicons.info, l10n.modelsImportExisting(name)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 16, left: 12),
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      children: [
                        for (final (index, label) in buttons.indexed)
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: IdeButton(
                              label: label,
                              secondary: index > 0,
                              onPressed: () => _close(
                                index == buttons.length - 1 ? null : index,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The site's mark, [size] square: the logo BaoCode lists it with, else its
/// site's icon, else a globe.
class _SiteLogo extends StatelessWidget {
  const _SiteLogo({required this.import, required this.listed, this.size = 40});

  final UpstreamImport import;
  final FeaturedUpstream? listed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final icon = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors['list.hoverBackground'],
        borderRadius: BorderRadius.circular(size / 4),
      ),
      child: ProviderIconView(
        icon: null,
        site: UpstreamUrls.parse(import.baseUrl),
        size: size * .55,
        color: colors['descriptionForeground'],
      ),
    );
    final logo = listed?.logo;
    if (logo == null) return icon;
    final file = File(logo);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: logo.toLowerCase().endsWith('.svg')
          ? SvgPicture.file(
              file,
              width: size,
              height: size,
              errorBuilder: (_, _, _) => icon,
            )
          : Image.file(
              file,
              width: size,
              height: size,
              errorBuilder: (_, _, _) => icon,
            ),
    );
  }
}

/// "Officially listed", between the halves of a laurel wreath: the site
/// is one BaoCode lists.
class _Badge extends StatelessWidget {
  const _Badge(this.label);

  final String label;

  // Hugeicons' laurel-wreath-left-01 and -right-01 (MIT,
  // https://github.com/hugeicons/hugeicons-react), by way of Iconify.
  static const _left =
      '<svg viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linejoin="round" stroke-width="1.5" d="M9.246 6.611c-.213 1.642 1.104 3.166 1.104 3.166s1.663-1.138 1.876-2.78c.213-1.643-1.104-3.167-1.104-3.167S9.46 4.97 9.246 6.611ZM7.683 12.13c.696 1.503 2.624 2.093 2.624 2.093s.8-1.847.104-3.35s-2.624-2.094-2.624-2.094s-.8 1.848-.104 3.351Zm.821 5.285c1.328.993 3.306.599 3.306.599s-.176-2.005-1.504-2.998S7 14.417 7 14.417s.176 2.005 1.504 2.998Zm3.609 4.298c1.505.698 3.359-.095 3.359-.095s-.587-1.925-2.092-2.624c-1.505-.698-3.358.096-3.358.096s.586 1.925 2.091 2.623Zm1.668-18.745c-1.21 1.133-1.164 3.144-1.164 3.144s2.01.176 3.22-.957s1.164-3.145 1.164-3.145s-2.01-.175-3.22.958Z"/></svg>';
  static const _right =
      '<svg viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linejoin="round" stroke-width="1.5" d="M16.756 6.611c.213 1.642-1.104 3.166-1.104 3.166s-1.663-1.138-1.877-2.78C13.562 5.353 14.88 3.83 14.88 3.83s1.663 1.139 1.877 2.781Zm1.561 5.519c-.696 1.503-2.624 2.093-2.624 2.093s-.8-1.847-.104-3.35s2.625-2.094 2.625-2.094s.8 1.848.103 3.351Zm-.82 5.285c-1.328.993-3.306.599-3.306.599s.176-2.005 1.504-2.998s3.306-.599 3.306-.599s-.176 2.005-1.504 2.998Zm-3.609 4.298c-1.505.698-3.359-.095-3.359-.095s.587-1.925 2.092-2.624c1.505-.698 3.358.096 3.358.096s-.586 1.925-2.091 2.623ZM12.22 2.968c1.21 1.133 1.164 3.144 1.164 3.144s-2.01.176-3.22-.957S9 2.01 9 2.01s2.01-.175 3.22.958Z"/></svg>';

  @override
  Widget build(BuildContext context) {
    final color = themeColors['descriptionForeground'];
    Widget half(String svg) => SvgPicture.string(
      svg,
      width: 16,
      height: 16,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        half(_left),
        Text(
          label,
          style: TextStyle(
            fontSize: UiText.secondary,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        half(_right),
      ],
    );
  }
}
