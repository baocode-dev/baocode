// The warning shown when the extensions' secrets go into the encrypted file
// (no system store answered): pass [showSecretsFallbackWarning] as
// `SecretBackend.forPlatform`'s `onFallback`.

import '../../../ide/ide_notifications.dart';
import '../../../l10n/l10n.dart';

/// Shows, as a warning in [notifications], that the extensions' secrets are
/// kept in an encrypted file.
void showSecretsFallbackWarning(
  IdeNotifications notifications,
  AppLocalizations l10n,
) => notifications.notify(
  IdeSeverity.warning,
  l10n.windowSecretsFallbackWarning,
  sticky: true,
);
