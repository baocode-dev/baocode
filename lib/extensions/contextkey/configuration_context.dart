// `config.*` context keys over the workspace's settings.

import '../configuration/configuration_service.dart';
import 'context_key_service.dart';

/// [ContextKeyConfiguration] over a [ConfigurationService]: values from
/// `getValue`, changes from its `$acceptConfigurationChanged` events.
final class ConfigurationContextKeys implements ContextKeyConfiguration {
  ConfigurationContextKeys(this.configuration);

  final ConfigurationService configuration;

  @override
  Object? getValue(String key) => configuration.getValue(key);

  @override
  void Function() onDidChange(void Function(List<String>? keys) listener) {
    final subscription = configuration.changes.listen((event) {
      final keys = event.change['keys'];
      listener(keys is List ? [for (final k in keys) '$k'] : null);
    });
    return subscription.cancel;
  }
}
