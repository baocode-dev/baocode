/// The protocols that connect BaoCode to a VS Code server and its extension
/// host (ported from VS Code 1.135.0).
library;

export 'src/base/cancellation.dart';
export 'src/base/uri.dart';
export 'src/generated/ext_host_proxies.g.dart';
export 'src/generated/main_thread_shapes.g.dart';
export 'src/generated/protocol_methods.g.dart';
export 'src/generated/proxy_identifiers.g.dart';
export 'src/ipc/ipc.dart';
export 'src/net/message_passing.dart';
export 'src/net/persistent_protocol.dart';
export 'src/net/remote_connection.dart';
export 'src/net/socket.dart';
export 'src/parity.dart';
export 'src/rpc/rpc_args.dart';
export 'src/rpc/rpc_protocol.dart';
