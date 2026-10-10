/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/authentication/browser/authenticationUsageService.ts.
//
// Deviations: app-wide (the storage is the app's JsonStateStore); the cache
// of extensions that use authentication is filled by each workspace's
// AuthenticationService as its providers register
// ([addExtensionsOfAccounts]) instead of by listening to one service.

import 'dart:convert';

import '../json_state_store.dart';

/// `IAccountUsage`: when an extension last used an account.
typedef AccountUsage = ({
  String extensionId,
  String extensionName,
  int lastUsed,
  List<String>? scopes,
});

final class AuthenticationUsageService {
  AuthenticationUsageService(
    this._store, {
    Object? trustedExtensionAuthAccess,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    // Extensions trusted by product.json use authentication.
    switch (trustedExtensionAuthAccess) {
      case final List<Object?> ids:
        _extensionsUsingAuth.addAll(ids.map((id) => '$id'));
      case final Map<Object?, Object?> byProvider:
        for (final ids in byProvider.values) {
          if (ids is List) _extensionsUsingAuth.addAll(ids.map((id) => '$id'));
        }
    }
  }

  final JsonStateStore _store;
  final DateTime Function() _now;
  final _extensionsUsingAuth = <String>{};

  /// Whether [extensionId] has used an account (`extensionUsesAuth`).
  bool extensionUsesAuth(String extensionId) =>
      _extensionsUsingAuth.contains(extensionId);

  List<AccountUsage> readAccountUsages(String providerId, String accountName) {
    final stored = _store.get('$providerId-$accountName-usages');
    if (stored == null) return [];
    try {
      final json = jsonDecode(stored);
      if (json is! List) return [];
      return [
        for (final usage in json)
          if (usage is Map)
            (
              extensionId: '${usage['extensionId']}',
              extensionName: '${usage['extensionName']}',
              lastUsed: (usage['lastUsed'] as num?)?.toInt() ?? 0,
              scopes: switch (usage['scopes']) {
                final List<Object?> scopes => [for (final s in scopes) '$s'],
                _ => null,
              },
            ),
      ];
    } on FormatException {
      return [];
    }
  }

  void removeAccountUsage(String providerId, String accountName) =>
      _store.remove('$providerId-$accountName-usages');

  void addAccountUsage(
    String providerId,
    String accountName,
    List<String>? scopes,
    String extensionId,
    String extensionName,
  ) {
    final usages = readAccountUsages(providerId, accountName);
    final usage = (
      extensionId: extensionId,
      extensionName: extensionName,
      lastUsed: _now().millisecondsSinceEpoch,
      scopes: scopes,
    );
    final index = usages.indexWhere((u) => u.extensionId == extensionId);
    if (index > -1) {
      usages[index] = usage;
    } else {
      usages.add(usage);
    }
    _store.set(
      '$providerId-$accountName-usages',
      jsonEncode([
        for (final u in usages)
          {
            'extensionId': u.extensionId,
            'extensionName': u.extensionName,
            'scopes': ?u.scopes,
            'lastUsed': u.lastUsed,
          },
      ]),
    );
    _extensionsUsingAuth.add(extensionId);
  }

  /// `_addExtensionsToCache`: the extensions that used [accountNames] of
  /// [providerId].
  void addExtensionsOfAccounts(String providerId, Iterable<String> accountNames) {
    for (final account in accountNames) {
      for (final usage in readAccountUsages(providerId, account)) {
        _extensionsUsingAuth.add(usage.extensionId);
      }
    }
  }
}
