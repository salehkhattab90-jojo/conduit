import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:riverpod/riverpod.dart';

import 'package:conduit_core/providers/app_providers.dart'
    show settledActiveAccountIdProvider;
import 'package:conduit_core/utils/debug_logger.dart';

import '../../../platform/webview_cookie_helper.dart';

typedef EmailOriginStorageClearer = Future<void> Function(String origin);

/// Keeps one account's session out of the next account's Email page.
///
/// The Email WebView seeds `localStorage.token` on the web app's origin, which
/// is usually the Open WebUI server itself. Sign-out already purges all
/// WebView data (`WebViewCookieHelper.clearAllWebViewData`), but switching
/// accounts does not, so this remembers which account last seeded each origin
/// and clears that origin's web storage when another account takes it over --
/// before the next page loads ([prepare]) and on the switch itself.
final emailWebViewStorageProvider = Provider<EmailWebViewStorage>((ref) {
  final storage = EmailWebViewStorage();
  ref.listen<String?>(settledActiveAccountIdProvider, (previous, next) {
    if (previous != next) storage.releaseOriginsNotOwnedBy(next);
  });
  return storage;
});

class EmailWebViewStorage {
  EmailWebViewStorage({
    EmailOriginStorageClearer? clearOrigin,
    Future<T> Function<T>(Future<T> Function() operation)? serialize,
    Future<void> Function()? waitForPending,
  }) : _clearOrigin = clearOrigin ?? clearEmailOriginWebStorage,
       _serialize = serialize ?? WebViewCookieHelper.runSerializedDataOperation,
       _waitForPending =
           waitForPending ?? WebViewCookieHelper.waitForPendingDataOperations;

  final EmailOriginStorageClearer _clearOrigin;
  final Future<T> Function<T>(Future<T> Function() operation) _serialize;
  final Future<void> Function() _waitForPending;
  final Map<String, String> _ownerByOrigin = <String, String>{};

  /// Called before an Email WebView for [accountId] loads [origin]. Clears the
  /// origin's storage when another account seeded it, records the new owner,
  /// and waits for every queued WebView data operation (including a sign-out
  /// purge) so none of them can run under the new page.
  Future<void> prepare({
    required String accountId,
    required String origin,
  }) async {
    final owner = _ownerByOrigin[origin];
    _ownerByOrigin[origin] = accountId;
    if (owner != null && owner != accountId) _scheduleClear(origin);
    await _waitForPending();
  }

  /// Clears every origin seeded by an account other than [accountId].
  void releaseOriginsNotOwnedBy(String? accountId) {
    final stale = [
      for (final entry in _ownerByOrigin.entries)
        if (entry.value != accountId) entry.key,
    ];
    for (final origin in stale) {
      _ownerByOrigin.remove(origin);
      _scheduleClear(origin);
    }
  }

  void _scheduleClear(String origin) {
    unawaited(
      _serialize(() => _clearOrigin(origin)).catchError((Object error) {
        DebugLogger.warning(
          'email-webview-storage-clear-failed',
          scope: 'email/webview',
          data: {'errorType': error.runtimeType.toString()},
        );
      }),
    );
  }
}

final Set<WebsiteDataType> _appleStorageTypes = <WebsiteDataType>{
  WebsiteDataType.WKWebsiteDataTypeLocalStorage,
  WebsiteDataType.WKWebsiteDataTypeSessionStorage,
  WebsiteDataType.WKWebsiteDataTypeIndexedDBDatabases,
  WebsiteDataType.WKWebsiteDataTypeWebSQLDatabases,
};

/// Removes web storage (not cookies) for one origin. WebKit groups records by
/// registrable domain, so on iOS the domain's sibling hosts are cleared too.
Future<void> clearEmailOriginWebStorage(String origin) async {
  if (!isWebViewSupported) return;
  final manager = WebStorageManager.instance();
  if (Platform.isAndroid) {
    await manager.deleteOrigin(origin: origin);
    return;
  }
  if (Platform.isIOS) {
    final host = Uri.parse(origin).host.toLowerCase();
    final records = await manager.fetchDataRecords(
      dataTypes: _appleStorageTypes,
    );
    final matching = records.where((record) {
      final name = record.displayName?.toLowerCase();
      return name != null &&
          name.isNotEmpty &&
          (host == name || host.endsWith('.$name'));
    }).toList();
    if (matching.isEmpty) return;
    await manager.removeDataFor(
      dataTypes: _appleStorageTypes,
      dataRecords: matching,
    );
  }
}

@visibleForTesting
Map<String, String> debugEmailWebViewOwners(EmailWebViewStorage storage) =>
    Map.unmodifiable(storage._ownerByOrigin);
