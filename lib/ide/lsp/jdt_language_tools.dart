import 'lsp_protocol.dart';
import 'lsp_server_definition.dart';

/// Whether [server] runs Eclipse JDT LS, including catalog variants and
/// custom launchers installed by Mason.
bool isJdtLanguageServer(LspServerDefinition server) {
  if (server.id.split('#').first == 'jdtls' || server.masonPackage == 'jdtls') {
    return true;
  }
  var command = server.command.split(RegExp(r'[/\\]')).last.toLowerCase();
  for (final suffix in const ['.cmd', '.exe', '.bat', '.js']) {
    if (command.endsWith(suffix)) {
      command = command.substring(0, command.length - suffix.length);
      break;
    }
  }
  return command == 'jdtls';
}

/// Enables JDT LS's virtual class-file contents without replacing the
/// user's other initialization options. Other servers are unchanged.
JsonMap? jdtInitializationOptions(LspServerDefinition server) {
  final options = server.initializationOptions;
  if (!isJdtLanguageServer(server)) return options;
  final extended = options?['extendedClientCapabilities'];
  return {
    ...?options,
    'extendedClientCapabilities': {
      if (extended is Map) ...extended.cast<String, Object?>(),
      'classFileContentsSupport': true,
    },
  };
}
