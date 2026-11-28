import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/ide_button.dart';
import '../../kernel/antigravity/agy_runtime.dart';
import '../../l10n/l10n.dart';
import '../../models/upstream.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'settings_widgets.dart';

/// An Antigravity CLI upstream's own settings: the CLI installed and kept
/// up to date by the app, and the Google account it is signed in with.
/// Its models are listed once signed in ([onModels]).
class AgySettingsGroup extends StatefulWidget {
  const AgySettingsGroup({super.key, required this.onModels, this.runtime});

  /// The models the account has, listed after signing in, installing, or
  /// on opening.
  final void Function(List<RemoteModel> models) onModels;

  /// This machine's when null.
  final AgyRuntime? runtime;

  @override
  State<AgySettingsGroup> createState() => _AgySettingsGroupState();
}

class _AgySettingsGroupState extends State<AgySettingsGroup> {
  AgyRuntime get _runtime => widget.runtime ?? AgyRuntime.local;

  String? _version;
  String? _latest;
  bool _read = false;
  double? _installing;

  /// Whether signed in, as listing the models said; null when not known.
  bool? _signedIn;
  int _models = 0;
  bool _busy = false;
  String? _error;

  /// Completed to give up signing in, while signing in.
  Completer<void>? _cancelSignIn;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final version = await _runtime.version();
      if (!mounted) return;
      setState(() {
        _version = version;
        _read = true;
      });
      unawaited(_checkLatest());
      if (version != null) await _list();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _read = true;
        _error = '$error';
      });
    }
  }

  Future<void> _checkLatest() async {
    try {
      final latest = await _runtime.latestVersion();
      if (mounted) setState(() => _latest = latest);
    } on AgyUnavailable {
      // Offline: the version installed is all that is said.
    }
  }

  Future<void> _list() async {
    try {
      final models = await _runtime.models();
      if (!mounted) return;
      setState(() {
        _signedIn = true;
        _models = models.length;
        _error = null;
      });
      widget.onModels([
        for (final model in models)
          RemoteModel(
            model.id,
            label: model.label,
            efforts: model.efforts.isEmpty ? null : model.efforts,
            images: true,
          ),
      ]);
    } on AgyUnavailable catch (error) {
      if (!mounted) return;
      setState(() {
        _signedIn = error.signIn ? false : _signedIn;
        _error = error.signIn ? null : '$error';
      });
    }
  }

  Future<void> _install() async {
    setState(() {
      _installing = 0;
      _error = null;
    });
    try {
      await _runtime.install(
        onProgress: (progress) {
          if (mounted) setState(() => _installing = progress);
        },
      );
      final version = await _runtime.version();
      if (!mounted) return;
      setState(() => _version = version);
      await _list();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _installing = null);
    }
  }

  Future<void> _sign(bool inside) async {
    final cancel = inside ? Completer<void>() : null;
    setState(() {
      _busy = true;
      _error = null;
      _cancelSignIn = cancel;
    });
    try {
      if (cancel != null) {
        await _runtime.signIn(cancel: cancel.future);
        await _list();
      } else {
        await _runtime.signOut();
        if (mounted) setState(() => _signedIn = false);
      }
    } on Object catch (error) {
      // Given up: nothing went wrong.
      if (mounted && !(cancel?.isCompleted ?? false)) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _cancelSignIn = null;
        });
      }
    }
  }

  @override
  void dispose() {
    if (_cancelSignIn case final cancel? when !cancel.isCompleted) {
      cancel.complete();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final version = _version;
    final latest = _latest;
    final installing = _installing;
    final outdated = version != null && latest != null && latest != version;
    final error = _error;
    return SettingsGroup(
      title: l10n.agyCli,
      description: l10n.agyCliDescription,
      children: [
        SettingsRow(
          label: l10n.agyCli,
          below: [
            Text(
              [
                if (installing != null)
                  l10n.agyInstalling((installing * 100).round())
                else if (version != null)
                  l10n.agyVersion(version)
                else if (_read)
                  l10n.agyNotInstalled,
                if (outdated && installing == null)
                  l10n.agyUpdateAvailable(latest),
              ].join(' · '),
              style: SettingsText.description,
            ),
          ],
          trailing: version == null || outdated
              ? IdeButton(
                  label: version == null ? l10n.agyInstall : l10n.agyUpdate,
                  icon: Codicons.cloudDownload,
                  secondary: version != null,
                  spinning: installing != null,
                  onPressed: installing != null || !_read
                      ? null
                      : () => unawaited(_install()),
                )
              : const SizedBox.shrink(),
        ),
        if (version != null)
          SettingsRow(
            label: l10n.agyAccount,
            description: l10n.agyAccountDescription,
            below: [
              if (_busy && _signedIn != true)
                Text(l10n.agySigningIn, style: SettingsText.description)
              else if (_signedIn case final signedIn?)
                Text(
                  signedIn ? l10n.agySignedIn(_models) : l10n.agyNotSignedIn,
                  style: SettingsText.description.copyWith(
                    color: signedIn ? AppColors.added : null,
                  ),
                ),
              if (error != null)
                SelectableText(
                  error,
                  style: SettingsText.description.copyWith(
                    color: themeColors['errorForeground'],
                  ),
                ),
            ],
            trailing: switch (_cancelSignIn) {
              // Signing in, in the browser: given up here.
              final cancel? => IdeButton(
                label: l10n.commonCancel,
                icon: Codicons.close,
                secondary: true,
                onPressed: cancel.isCompleted
                    ? null
                    : () => setState(cancel.complete),
              ),
              null => IdeButton(
                label: _signedIn == true ? l10n.agySignOut : l10n.agySignIn,
                icon: _signedIn == true ? Codicons.signOut : Codicons.account,
                secondary: _signedIn == true,
                spinning: _busy,
                onPressed: _busy
                    ? null
                    : () => unawaited(_sign(_signedIn != true)),
              ),
            },
          )
        else if (error != null)
          SettingsRow(
            label: '',
            below: [
              SelectableText(
                error,
                style: SettingsText.description.copyWith(
                  color: themeColors['errorForeground'],
                ),
              ),
            ],
          ),
      ],
    );
  }
}
