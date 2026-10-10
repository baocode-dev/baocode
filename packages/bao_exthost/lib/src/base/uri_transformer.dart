/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The URIs of a remote extension host, as they cross its connection.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/base/common/uriIpc.ts (`IURITransformer`, `URITransformer`,
// `transformIncomingURIs`) and src/vs/base/common/uriTransformer.ts
// (`createURITransformer`).
//
// Upstream, the remote extension host transforms them: its own files are
// `file:` URIs, the window's `vscode-remote://<authority>/…`, and the
// window's local files `vscode-local:`. The app's side of a remote
// project's host uses the same transformer (see rpc_protocol.dart): its
// `file:` URIs are the remote host's paths, as the project's are, and
// this machine's files `vscode-local:`.

import 'uri.dart';

/// `IURITransformer`, over marshalled URIs (`{$mid: 1, scheme, …}`).
abstract interface class UriTransformer {
  Map<String, Object?> transformIncoming(Map<String, Object?> uri);
  Map<String, Object?> transformOutgoing(Map<String, Object?> uri);
  String transformOutgoingScheme(String scheme);
}

/// `createURITransformer(remoteAuthority)`.
UriTransformer createUriTransformer(String remoteAuthority) =>
    _RemoteUriTransformer(remoteAuthority);

final class _RemoteUriTransformer implements UriTransformer {
  _RemoteUriTransformer(this.remoteAuthority);

  final String remoteAuthority;

  /// `URITransformer`: the same map when unchanged, else
  /// `toJSON(URI.from(result))`.
  static Map<String, Object?> _with(
    Map<String, Object?> uri,
    String scheme, {
    String authority = '',
  }) => VsUri.from({
    'scheme': scheme,
    'authority': authority,
    'path': uri['path'],
    'query': uri['query'],
    'fragment': uri['fragment'],
  }).toJson();

  @override
  Map<String, Object?> transformIncoming(Map<String, Object?> uri) =>
      switch (uri['scheme']) {
        'vscode-remote' => _with(uri, 'file'),
        'file' => _with(uri, 'vscode-local'),
        _ => uri,
      };

  @override
  Map<String, Object?> transformOutgoing(Map<String, Object?> uri) =>
      switch (uri['scheme']) {
        'file' => _with(uri, 'vscode-remote', authority: remoteAuthority),
        'vscode-local' => _with(uri, 'file'),
        _ => uri,
      };

  @override
  String transformOutgoingScheme(String scheme) => switch (scheme) {
    'file' => 'vscode-remote',
    'vscode-local' => 'file',
    _ => scheme,
  };
}

bool _isUri(Map<Object?, Object?> value) => value[r'$mid'] == uriMarshalledId;

/// `transformIncomingURIs`: [value] (decoded JSON) with each marshalled
/// URI in it transformed; the same object when there is none.
Object? transformIncomingUris(Object? value, UriTransformer transformer) =>
    _walk(value, (uri) => transformer.transformIncoming(uri), 0);

/// What the replacer upstream stringifies with does to a value: each
/// marshalled URI in [value] (decoded JSON) transformed for the other side.
Object? transformOutgoingUris(Object? value, UriTransformer transformer) =>
    _walk(value, (uri) => transformer.transformOutgoing(uri), 0);

Object? _walk(
  Object? value,
  Map<String, Object?> Function(Map<String, Object?> uri) transform,
  int depth,
) {
  if (depth > 200) return value;
  if (value is Map) {
    if (_isUri(value)) return transform(value.cast<String, Object?>());
    Map<String, Object?>? changed;
    for (final MapEntry(:key, value: entry) in value.entries) {
      final walked = _walk(entry, transform, depth + 1);
      if (!identical(walked, entry)) {
        changed ??= {
          for (final e in value.entries) e.key as String: e.value,
        };
        changed[key as String] = walked;
      }
    }
    return changed ?? value;
  }
  if (value is List) {
    List<Object?>? changed;
    for (var i = 0; i < value.length; i++) {
      final walked = _walk(value[i], transform, depth + 1);
      if (!identical(walked, value[i])) {
        (changed ??= [...value])[i] = walked;
      }
    }
    return changed ?? value;
  }
  return value;
}
