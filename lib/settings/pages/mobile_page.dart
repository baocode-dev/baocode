import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ide/ide_button.dart';
import '../../l10n/l10n.dart';
import '../../link/link_host.dart';
import '../../link/qr_view.dart';
import '../../theme/codicons.dart';
import 'settings_widgets.dart';

/// Settings → Mobile: whether phones may connect, how this computer stands
/// with its relays (and relays of one's own), pairing one by QR code, and the
/// phones paired, each with its path while connected.
class MobileSettingsPage extends StatefulWidget {
  const MobileSettingsPage({super.key, required this.host});

  final LinkHost host;

  @override
  State<MobileSettingsPage> createState() => _MobileSettingsPageState();
}

class _MobileSettingsPageState extends State<MobileSettingsPage> {
  bool _copied = false;
  Timer? _copiedTimer;

  /// Ticks while a code shows, for it to say when it expired, and while
  /// phones are connected, for their round trips.
  Timer? _ticker;

  LinkHost get _host => widget.host;

  @override
  void initState() {
    super.initState();
    _host.addListener(_changed);
    unawaited(_host.refresh());
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_host.offer != null || _host.phones.any(_connected)) setState(() {});
    });
  }

  bool _connected(PairedPhone phone) => _host.isConnected(phone.id);

  @override
  void dispose() {
    _host.removeListener(_changed);
    _copiedTimer?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _copy(String link) {
    unawaited(Clipboard.setData(ClipboardData(text: link)));
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  /// A relay's URL as shown: its host.
  static String _relayName(String url) => Uri.tryParse(url)?.host ?? url;

  String _status(AppLocalizations l10n) {
    final host = _host;
    switch (host.status) {
      case LinkHostStatus.off:
        return l10n.mobileStatusOff;
      case LinkHostStatus.starting:
        return l10n.mobileStatusStarting;
      case LinkHostStatus.failed:
        return l10n.mobileStatusFailed(host.error ?? '');
      case LinkHostStatus.listening:
        final info = host.info;
        if (info?.denied case final reason?) {
          return l10n.mobileStatusDenied(reason);
        }
        final home = info?.home.where((s) => s.connected).firstOrNull;
        if (home == null) return l10n.mobileStatusNoRelay;
        return l10n.mobileStatusOnline(_relayName(home.url));
    }
  }

  static String _path(AppLocalizations l10n, LinkPath path) => [
    switch (path.kind) {
      LinkPathKind.lan => l10n.mobilePathLan,
      LinkPathKind.direct => l10n.mobilePathDirect,
      LinkPathKind.relay => l10n.mobilePathRelay,
      LinkPathKind.none => l10n.mobilePhoneConnected,
    },
    if (path.rtt case final rtt?) l10n.mobilePathRtt(rtt.inMilliseconds),
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final host = _host;
    final home = [
      for (final status in host.info?.home ?? const <LinkRelayStatus>[])
        if (status.connected) _relayName(status.url),
    ];
    return SettingsPage(
      title: l10n.settingsSectionMobile,
      description: l10n.mobileSettingsDescription,
      children: [
        SettingsCard(
          children: [
            SettingsSwitchRow(
              label: l10n.mobileAllow,
              description: l10n.mobileAllowDescription,
              value: host.enabled,
              onChanged: (value) => unawaited(host.setEnabled(value)),
            ),
            SettingsSwitchRow(
              label: l10n.mobileDiscoverable,
              description: l10n.mobileDiscoverableDescription,
              value: host.discoverable,
              onChanged: host.setDiscoverable,
            ),
            SettingsRow(label: l10n.mobileStatus, description: _status(l10n)),
            SettingsRow(
              label: l10n.mobileRelay,
              description: l10n.mobileRelayDescription,
              trailing: Text(
                home.isEmpty ? l10n.mobileRelayNone : home.join(', '),
                style: SettingsText.description,
              ),
            ),
            SettingsRow(
              label: l10n.mobileRelayCustom,
              description: l10n.mobileRelayCustomDescription,
              trailing: SettingsTextField(
                value: host.customRelays.join(', '),
                hint: 'https://relay.example.com',
                semanticLabel: l10n.mobileRelayCustom,
                onSubmitted: (text) =>
                    unawaited(host.setCustomRelays(text.split(','))),
              ),
            ),
          ],
        ),
        SettingsGroup(title: l10n.mobilePair, children: [_pairing(context)]),
        SettingsGroup(
          title: l10n.mobilePhones,
          children: [
            if (host.phones.isEmpty && host.legacyPhones.isEmpty)
              SettingsRow(label: l10n.mobilePhonesNone),
            for (final phone in host.phones)
              SettingsRow(
                label: phone.name.isEmpty ? phone.fingerprint : phone.name,
                description: [
                  if (phone.system.isNotEmpty) phone.system,
                  if (host.pathOf(phone.id) case final path?)
                    _path(l10n, path)
                  else if (host.isConnected(phone.id))
                    l10n.mobilePhoneConnected
                  else if (phone.lastSeen case final seen?)
                    l10n.mobilePhoneLastSeen(_time(seen)),
                ].join(' · '),
                trailing: IdeButton(
                  label: l10n.mobilePhoneRemove,
                  icon: Codicons.trash,
                  secondary: true,
                  onPressed: () => host.unpair(phone),
                ),
              ),
            for (final phone in host.legacyPhones)
              SettingsRow(
                label: phone.name.isEmpty ? phone.system : phone.name,
                description: [
                  if (phone.system.isNotEmpty && phone.name.isNotEmpty)
                    phone.system,
                  l10n.mobileLegacyPhone,
                ].join(' · '),
                trailing: SettingsButtons(
                  children: [
                    IdeButton(
                      label: l10n.mobileLegacyRepair,
                      icon: Codicons.deviceMobile,
                      onPressed: host.supported
                          ? () => unawaited(host.beginPairing())
                          : null,
                    ),
                    IdeButton(
                      label: l10n.mobilePhoneRemove,
                      icon: Codicons.trash,
                      secondary: true,
                      onPressed: () => host.forgetLegacy(phone),
                    ),
                  ],
                ),
              ),
            SettingsRow(
              label: l10n.mobileThisComputerKey,
              description: l10n.mobileThisComputerKeyDescription,
              below: [
                SelectableText(host.fingerprint, style: SettingsText.path),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// The pairing card's row: a button to show a code; the code; the
  /// safety code to compare once a phone scanned it; who was paired.
  Widget _pairing(BuildContext context) {
    final l10n = context.l10n;
    final host = _host;
    final offer = host.offer;
    final pending = host.pending;
    if (pending != null) {
      final name = pending.name.isEmpty ? pending.system : pending.name;
      if (pending.needsApproval) {
        // Found nearby, with no code scanned: allowed here, or not.
        return SettingsRow(
          label: l10n.mobilePairRequestTitle(name),
          description: l10n.mobilePairRequestBody,
          below: [
            Text(
              pending.code.join('  '),
              style: SettingsText.path.copyWith(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
            if (!pending.approved)
              SettingsButtons(
                children: [
                  IdeButton(
                    label: l10n.mobilePairAllow,
                    icon: Codicons.check,
                    onPressed: host.approvePending,
                  ),
                  IdeButton(
                    label: l10n.mobilePairMismatch,
                    secondary: true,
                    onPressed: host.rejectPending,
                  ),
                ],
              ),
          ],
        );
      }
      return SettingsRow(
        label: l10n.mobilePairVerifyTitle(name),
        description: l10n.mobilePairVerifyBody,
        below: [
          Text(
            pending.code.join('  '),
            style: SettingsText.path.copyWith(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
            ),
          ),
        ],
        trailing: IdeButton(
          label: l10n.mobilePairMismatch,
          secondary: true,
          onPressed: host.rejectPending,
        ),
      );
    }
    if (offer != null) {
      final expired = offer.expiredAt(DateTime.now());
      final link = offer.uri;
      return SettingsRow(
        label: l10n.mobilePair,
        description: expired
            ? l10n.mobilePairExpired
            : [
                l10n.mobilePairExpires(host.offerLifetime.inMinutes),
                if (host.advertised) l10n.mobilePairNearbyHint,
              ].join(' '),
        below: [
          if (!expired)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: QrView(data: link),
            ),
          SettingsButtons(
            children: [
              IdeButton(
                label: l10n.mobilePairNewCode,
                icon: Codicons.refresh,
                secondary: true,
                onPressed: () => unawaited(host.beginPairing()),
              ),
              if (!expired)
                IdeButton(
                  label: _copied
                      ? l10n.mobilePairCopied
                      : l10n.mobilePairCopyLink,
                  icon: _copied ? Codicons.check : Codicons.copy,
                  secondary: true,
                  onPressed: () => _copy(link),
                ),
              IdeButton(
                label: l10n.mobilePairCancel,
                secondary: true,
                onPressed: host.endPairing,
              ),
            ],
          ),
        ],
      );
    }
    final paired = host.justPaired;
    return SettingsRow(
      label: l10n.mobilePair,
      description: paired == null
          ? l10n.mobilePairDescription
          : l10n.mobilePaired(paired.name),
      trailing: IdeButton(
        label: l10n.mobilePairShow,
        icon: Codicons.deviceMobile,
        onPressed: host.supported ? () => unawaited(host.beginPairing()) : null,
      ),
    );
  }

  static String _time(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}
