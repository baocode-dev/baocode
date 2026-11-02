import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../forge/forge_accounts.dart';
import '../../forge/forge_api.dart';
import '../../forge/forge_ref.dart';
import '../../forge/forge_view.dart';
import '../../ide/ide_button.dart';
import '../../ide/ide_dialog.dart';
import '../../ide/ide_input.dart';
import '../../ide/ide_spinning.dart';
import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../../workspace/editor_launcher.dart' show openExternal;
import 'model_dialogs.dart';
import 'settings_widgets.dart';

/// Settings → Accounts: the GitHub and GitLab accounts the stashes' issues
/// and pull requests are asked of (docs/stash.md), signed in from the
/// browser or with a token; signed out here.
class AccountsSettingsPage extends StatelessWidget {
  const AccountsSettingsPage({super.key, this.accounts});

  /// The app's; none under test or on the web.
  final ForgeAccounts? accounts;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final accounts = this.accounts;
    if (accounts == null) {
      return SettingsPage(
        title: l10n.settingsSectionAccounts,
        description: l10n.accountsDescription,
        children: const [],
      );
    }
    return ListenableBuilder(
      listenable: accounts,
      builder: (context, _) => SettingsPage(
        title: l10n.settingsSectionAccounts,
        description: l10n.accountsDescription,
        children: [
          if (accounts.accounts.isNotEmpty)
            SettingsGroup(
              title: l10n.accountsSignedIn,
              children: [
                for (final account in accounts.accounts)
                  _AccountRow(accounts: accounts, account: account),
              ],
            ),
          SettingsGroup(
            title: l10n.accountsAdd,
            description: l10n.accountsKeptLocally,
            children: [
              for (final kind in ForgeKind.values)
                SettingsRow(
                  label: kind.label,
                  description: switch (kind) {
                    ForgeKind.github => l10n.accountsGitHubHosts,
                    ForgeKind.gitlab => l10n.accountsGitLabHosts,
                  },
                  trailing: SettingsButtons(
                    children: [
                      if (accounts.canSignInFromBrowser(kind, kind.publicHost))
                        IdeButton(
                          label: l10n.accountsSignInBrowser,
                          leading: ForgeLogo(kind),
                          onPressed: () => unawaited(
                            showForgeDeviceDialog(context, accounts, kind),
                          ),
                        ),
                      IdeButton(
                        label: l10n.accountsSignInToken,
                        secondary: true,
                        onPressed: () => unawaited(
                          showForgeTokenDialog(context, accounts, kind),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.accounts, required this.account});

  final ForgeAccounts accounts;
  final ForgeAccount account;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SettingsRow(
      label: switch (account.name) {
        final name? when name.isNotEmpty && name != account.login =>
          '${account.login} ($name)',
        _ => account.login,
      },
      description: [
        '${account.kind.label} · ${account.host}'
            '${account.scheme == 'http' ? ' (http)' : ''}',
        switch (account.via) {
          ForgeSignIn.browser => l10n.accountsViaBrowser,
          ForgeSignIn.token => l10n.accountsViaToken,
        },
      ].join(' · '),
      trailing: IdeButton(
        label: l10n.accountsSignOut,
        secondary: true,
        onPressed: () => unawaited(_signOut(context)),
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final l10n = context.l10n;
    final forge = account.kind.label;
    final answer = await showIdeDialog(
      context,
      message: l10n.accountsSignOutTitle(account.login, forge),
      detail: l10n.accountsSignOutDetail(forge),
      buttons: [l10n.accountsSignOut, l10n.accountsRevoke(forge)],
    );
    switch (answer) {
      case 0:
        await accounts.signOut(account.host);
      case 1:
        await accounts.signOut(account.host);
        await openExternal('${forgeRevokePage(account)}');
    }
  }
}

/// Where [account]'s authorization is revoked on its forge: the app's (signed
/// in from the browser) or the tokens' page.
Uri forgeRevokePage(ForgeAccount account) => account.base.replace(
  path: switch ((account.kind, account.via)) {
    (ForgeKind.github, ForgeSignIn.browser) => '/settings/applications',
    (ForgeKind.github, ForgeSignIn.token) => '/settings/tokens',
    (ForgeKind.gitlab, ForgeSignIn.browser) => '/-/user_settings/applications',
    (ForgeKind.gitlab, ForgeSignIn.token) =>
      '/-/user_settings/personal_access_tokens',
  },
);

/// Where a token for BaoCode is made on [site], what it needs checked.
Uri forgeNewTokenPage(ForgeKind kind, Uri site) => switch (kind) {
  ForgeKind.github => site.replace(
    path: '/settings/tokens/new',
    queryParameters: {'scopes': 'repo,read:user', 'description': 'BaoCode'},
  ),
  ForgeKind.gitlab => site.replace(
    path: '/-/user_settings/personal_access_tokens',
    queryParameters: {'name': 'BaoCode', 'scopes': 'api'},
  ),
};

TextStyle _text({Color? color, double size = 13}) => TextStyle(
  fontSize: size,
  height: 18 / 13,
  color: color ?? themeColors['editorWidget.foreground'],
);

TextStyle _muted() =>
    _text(color: themeColors['descriptionForeground'], size: 12);

Future<T?> _show<T>(BuildContext context, Widget dialog) =>
    showGeneralDialog<T>(
      context: context,
      // Closed by its buttons, Escape or the close button: a click beside
      // it would lose what was typed.
      barrierDismissible: false,
      barrierLabel: context.l10n.commonDismiss,
      barrierColor: const Color(0x80000000),
      transitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => dialog,
    );

// --- With a token -------------------------------------------------------------

/// Signs in to a [kind] forge with a token the user makes (on its public
/// service or their own, the host typed); completes with the account, or
/// null when dismissed.
Future<ForgeAccount?> showForgeTokenDialog(
  BuildContext context,
  ForgeAccounts accounts,
  ForgeKind kind,
) => _show(context, ForgeTokenDialog(accounts: accounts, kind: kind));

class ForgeTokenDialog extends StatefulWidget {
  const ForgeTokenDialog({
    super.key,
    required this.accounts,
    required this.kind,
  });

  final ForgeAccounts accounts;
  final ForgeKind kind;

  @override
  State<ForgeTokenDialog> createState() => _ForgeTokenDialogState();
}

class _ForgeTokenDialogState extends State<ForgeTokenDialog> {
  late final _host = TextEditingController(text: widget.kind.publicHost);
  final _token = TextEditingController();
  var _signingIn = false;
  String? _error;

  @override
  void dispose() {
    _host.dispose();
    _token.dispose();
    super.dispose();
  }

  /// The server as typed: a host, or a whole address (`http://gitlab.corp:
  /// 8080`) for one served so.
  Uri get _site {
    final text = _host.text.trim();
    if (text.isEmpty) return Uri.https(widget.kind.publicHost, '');
    final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
    return uri == null || uri.host.isEmpty ? Uri.https(text, '') : uri;
  }

  String get _hostTyped => _site.authority;

  Future<void> _signIn() async {
    if (_signingIn || _token.text.trim().isEmpty) return;
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      final account = await widget.accounts.signInWithToken(
        widget.kind,
        _site.toString(),
        _token.text,
      );
      if (mounted) Navigator.pop(context, account);
    } on ForgeCertificateException catch (error) {
      if (!mounted) return;
      setState(() => _signingIn = false);
      // The server's certificate is a self-signed one or a private CA's:
      // the user says whether to trust this one, and only this one.
      final answer = await showIdeDialog(
        context,
        message: context.l10n.accountsCertificateTitle,
        detail: context.l10n.accountsCertificateDetail(
          error.host,
          error.issuer.isEmpty ? error.subject : error.issuer,
          error.sha256,
        ),
        buttons: [context.l10n.accountsCertificateTrust],
      );
      if (!mounted || answer != 0) return;
      widget.accounts.trustCertificate(error.host, error.sha256);
      await _signIn();
    } on ForgeException catch (error) {
      if (mounted) {
        setState(() {
          _signingIn = false;
          _error = error.unauthorized
              ? context.l10n.accountsTokenRefused
              : error.message;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _signingIn = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final kind = widget.kind;
    return ModelDialogFrame(
      title: l10n.accountsTokenTitle(kind.label),
      onSubmit: () => unawaited(_signIn()),
      actions: [
        IdeButton(
          label: l10n.accountsSignIn,
          spinning: _signingIn,
          onPressed: _signingIn ? null : () => unawaited(_signIn()),
        ),
        IdeButton(
          label: l10n.commonCancel,
          secondary: true,
          onPressed: () => Navigator.pop(context),
        ),
      ],
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.accountsHost, style: _muted()),
            const SizedBox(height: 4),
            IdeInputBox(
              controller: _host,
              semanticsLabel: l10n.accountsHost,
              placeholder: kind.publicHost,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Text(l10n.accountsToken, style: _muted()),
            const SizedBox(height: 4),
            IdeInputBox(
              controller: _token,
              semanticsLabel: l10n.accountsToken,
              obscureText: true,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => unawaited(_signIn()),
            ),
            const SizedBox(height: 8),
            Text(switch (kind) {
              ForgeKind.github => l10n.accountsTokenGitHubScopes,
              ForgeKind.gitlab => l10n.accountsTokenGitLabScopes,
            }, style: _muted()),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: IdeButton(
                label: l10n.accountsTokenCreate(_hostTyped),
                icon: Codicons.linkExternal,
                secondary: true,
                onPressed: () => unawaited(
                  openExternal('${forgeNewTokenPage(kind, _site)}'),
                ),
              ),
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 10),
              SelectableText(
                error,
                style: _text(color: themeColors['errorForeground']),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --- From the browser ---------------------------------------------------------

/// Signs in to [kind]'s public service from the browser: the code to enter
/// there, shown until it is entered (or refused, or expired); completes
/// with the account, or null when dismissed.
Future<ForgeAccount?> showForgeDeviceDialog(
  BuildContext context,
  ForgeAccounts accounts,
  ForgeKind kind,
) => _show(context, ForgeDeviceDialog(accounts: accounts, kind: kind));

class ForgeDeviceDialog extends StatefulWidget {
  const ForgeDeviceDialog({
    super.key,
    required this.accounts,
    required this.kind,
  });

  final ForgeAccounts accounts;
  final ForgeKind kind;

  @override
  State<ForgeDeviceDialog> createState() => _ForgeDeviceDialogState();
}

class _ForgeDeviceDialogState extends State<ForgeDeviceDialog> {
  ForgeDeviceCode? _code;
  String? _error;
  var _closed = false;
  var _copied = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _code = null;
      _error = null;
    });
    try {
      final code = await widget.accounts.startDeviceFlow(widget.kind);
      if (_closed) return;
      setState(() => _code = code);
      final account = await widget.accounts.finishDeviceFlow(
        code,
        cancelled: () => _closed,
      );
      if (!_closed && mounted) Navigator.pop(context, account);
    } on Object catch (error) {
      if (_closed || !mounted) return;
      setState(
        () => _error = error is ForgeException ? error.message : '$error',
      );
    }
  }

  Future<void> _open(ForgeDeviceCode code) async {
    await Clipboard.setData(ClipboardData(text: code.userCode));
    if (mounted) setState(() => _copied = true);
    await openExternal('${code.verificationUrl}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final code = _code;
    final error = _error;
    return ModelDialogFrame(
      title: l10n.accountsBrowserTitle(widget.kind.label),
      actions: [
        if (error != null)
          IdeButton(
            label: l10n.accountsRetry,
            onPressed: () => unawaited(_run()),
          )
        else if (code != null)
          IdeButton(
            label: _copied ? l10n.accountsOpenAgain : l10n.accountsCopyAndOpen,
            icon: Codicons.linkExternal,
            onPressed: () => unawaited(_open(code)),
          ),
        IdeButton(
          label: l10n.commonCancel,
          secondary: true,
          onPressed: () => Navigator.pop(context),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (code != null) ...[
            Text(
              l10n.accountsBrowserDetail(code.verificationUrl.host),
              style: _text(),
            ),
            const SizedBox(height: 10),
            SelectableText(
              code.userCode,
              style: _text(size: 22)
                  .copyWith(fontWeight: FontWeight.w600, letterSpacing: 2),
            ),
          ],
          if (error == null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                IdeSpinning(
                  Icon(
                    Codicons.loading,
                    size: 14,
                    color: themeColors['descriptionForeground'],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    code == null
                        ? l10n.accountsBrowserStarting
                        : l10n.accountsBrowserWaiting,
                    style: _muted(),
                  ),
                ),
              ],
            ),
          ] else
            SelectableText(
              error,
              style: _text(color: themeColors['errorForeground']),
            ),
        ],
      ),
    );
  }
}
