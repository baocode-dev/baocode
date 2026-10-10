import 'package:bao_exthost/bao_exthost.dart';

/// The remote authority we give the VS Code server's management channel.
///
/// The server turns the paths of its machine into
/// `vscode-remote://<authority>/<path>` on the way out, and back on the way
/// in. The extension host is told no authority, so its URIs are plain
/// `file:` URIs of the server's machine: [fromServer] and [toServer]
/// translate between the two.
const serverAuthority = 'baocode';

/// `vscode-remote://baocode/p` → `file:///p`, anywhere inside [value]
/// (marshalled URIs, as `{$mid: 1, scheme, …}` maps).
Object? fromServer(Object? value) {
  if (value is Map) {
    if (value[r'$mid'] == uriMarshalledId &&
        value['scheme'] == 'vscode-remote' &&
        value['authority'] == serverAuthority) {
      return <String, Object?>{
        for (final e in value.entries)
          if (!const {
            'external',
            'fsPath',
            '_sep',
            'authority',
          }.contains(e.key))
            e.key as String: e.value,
        'scheme': 'file',
      };
    }
    return <String, Object?>{
      for (final e in value.entries) e.key as String: fromServer(e.value),
    };
  }
  if (value is List) return [for (final e in value) fromServer(e)];
  return value;
}

/// `file:///p` → `vscode-remote://baocode/p`, anywhere inside [value]: what
/// a channel returns untransformed (`extensions.install` and
/// `installFromLocation` answer with the server's own `file:` URIs) as the
/// server takes it back.
Object? asSentByServer(Object? value) {
  if (value is Map) {
    if (value[r'$mid'] == uriMarshalledId && value['scheme'] == 'file') {
      return <String, Object?>{
        for (final e in value.entries)
          if (!const {'external', 'fsPath', '_sep'}.contains(e.key))
            e.key as String: e.value,
        'scheme': 'vscode-remote',
        'authority': serverAuthority,
      };
    }
    return <String, Object?>{
      for (final e in value.entries) e.key as String: asSentByServer(e.value),
    };
  }
  if (value is List) return [for (final e in value) asSentByServer(e)];
  return value;
}

/// A server-side path as the server's channels take it.
VsUri toServer(VsUri uri) => uri.scheme == 'file'
    ? uri.replace(scheme: 'vscode-remote', authority: serverAuthority)
    : uri;
