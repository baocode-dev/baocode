/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/authentication/browser/authenticationAccessService.ts.
//
// Deviations: the application storage is a JsonStateStore the app shares
// between its workspaces (VS Code's is shared between its windows).

import 'dart:async';
import 'dart:convert';

import '../extension_descriptions.dart';
import '../json_state_store.dart';
import 'authentication_types.dart';

/// Which extensions may use which accounts, for the whole app.
final class AuthenticationAccessService {
  AuthenticationAccessService(
    this._store, {
    this.trustedExtensionAuthAccess,
  });


  final JsonStateStore _store;

  /// product.json's `trustedExtensionAuthAccess`: a list of extension ids,
  /// or provider id → extension ids.
  final Object? trustedExtensionAuthAccess;

  final _onDidChangeExtensionSessionAccess =
      StreamController<({String providerId, String accountName})>.broadcast(
        sync: true,
      );

  Stream<({String providerId, String accountName})>
  get onDidChangeExtensionSessionAccess =>
      _onDidChangeExtensionSessionAccess.stream;

  /// The extension ids product.json trusts for [providerId].
  List<String> _trustedIds(String providerId) =>
      switch (trustedExtensionAuthAccess) {
        final List<Object?> ids => [for (final id in ids) '$id'],
        final Map<Object?, Object?> byProvider => switch (byProvider[providerId]) {
          final List<Object?> ids => [for (final id in ids) '$id'],
          _ => const [],
        },
        _ => const [],
      };

  /// Whether product.json trusts [extensionId] with [providerId]'s accounts.
  bool isTrusted(String providerId, String extensionId) => _trustedIds(
    providerId,
  ).map(extensionKey).contains(extensionKey(extensionId));

  /// True or false when the user chose (or product.json trusts it); null
  /// when they have not been asked.
  bool? isAccessAllowed(
    String providerId,
    String accountName,
    String extensionId,
  ) {
    if (isTrusted(providerId, extensionId)) return true;
    final key = extensionKey(extensionId);
    final allowList = readAllowedExtensions(providerId, accountName);
    final data = allowList.where((e) => e.id == key).firstOrNull;
    if (data == null) return null;
    // Inclusion alone meant allowed before `allowed` existed.
    return data.allowed ?? true;
  }

  List<AllowedExtension> readAllowedExtensions(
    String providerId,
    String accountName,
  ) {
    var trustedExtensions = <AllowedExtension>[];
    try {
      final source = _store.get('$providerId-$accountName');
      if (source != null) {
        final json = jsonDecode(source);
        if (json is List) {
          trustedExtensions = [
            for (final item in json)
              if (item is Map) AllowedExtension.fromJson(item),
          ];
        }
      }
    } on FormatException {
      // As upstream: a broken list is empty.
    }
    for (final extensionId in _trustedIds(providerId)) {
      final key = extensionKey(extensionId);
      final existing = trustedExtensions.where((e) => e.id == key).firstOrNull;
      if (existing == null) {
        trustedExtensions.add(
          AllowedExtension(
            id: key,
            name: extensionId,
            allowed: true,
            trusted: true,
          ),
        );
      } else {
        existing
          ..allowed = true
          ..trusted = true;
      }
    }
    return trustedExtensions;
  }

  void updateAllowedExtensions(
    String providerId,
    String accountName,
    List<AllowedExtension> extensions,
  ) {
    final allowList = readAllowedExtensions(providerId, accountName);
    for (final extension in extensions) {
      final key = extensionKey(extension.id);
      final index = allowList.indexWhere((e) => e.id == key);
      if (index == -1) {
        allowList.add(
          AllowedExtension(
            id: key,
            name: extension.name,
            allowed: extension.allowed,
            lastUsed: extension.lastUsed,
            trusted: extension.trusted,
          ),
        );
      } else {
        allowList[index].allowed = extension.allowed;
        if (extension.name.isNotEmpty &&
            extension.name != key &&
            allowList[index].name != extension.name) {
          allowList[index].name = extension.name;
        }
      }
    }
    // Trusted ones come from product.json only.
    final userManaged = allowList.where((e) => e.trusted != true).toList();
    _store.set(
      '$providerId-$accountName',
      jsonEncode([for (final e in userManaged) e.toJson()]),
    );
    _onDidChangeExtensionSessionAccess.add((
      providerId: providerId,
      accountName: accountName,
    ));
  }

  void removeAllowedExtensions(String providerId, String accountName) {
    _store.remove('$providerId-$accountName');
    _onDidChangeExtensionSessionAccess.add((
      providerId: providerId,
      accountName: accountName,
    ));
  }

  void dispose() => unawaited(_onDidChangeExtensionSessionAccess.close());
}
