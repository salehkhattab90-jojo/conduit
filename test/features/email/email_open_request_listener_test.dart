import 'dart:async';

import 'package:conduit/features/email/services/email_webview_storage.dart';
import 'package:conduit/features/email/widgets/email_open_request_listener.dart';
import 'package:conduit/features/navigation/providers/sidebar_providers.dart';
import 'package:conduit/shared/widgets/sidebar_layout_contract.dart';
import 'package:conduit_core/features/email/providers/email_providers.dart';
import 'package:conduit_core/features/navigation/models/sidebar_navigation_model.dart';
import 'package:conduit_core/providers/app_providers.dart'
    show SettledActiveAccountId, settledActiveAccountIdProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../navigation/widgets/sidebar_page_test_support.dart'
    show SidebarTestTestSidebarActiveTab;

final class _SettledOnA extends SettledActiveAccountId {
  @override
  String? build() => 'a';
}

/// The tabs the server currently allows; Email appears once config loads.
final class _VisibleTabs extends Notifier<List<SidebarTabId>> {
  @override
  List<SidebarTabId> build() => const [SidebarTabId.chats];

  void show(List<SidebarTabId> tabs) => state = tabs;
}

final _visibleTabsProvider = NotifierProvider<_VisibleTabs, List<SidebarTabId>>(
  _VisibleTabs.new,
);

final class _Drawer implements SidebarDrawerController {
  @override
  bool isOpen = false;
  int opens = 0;

  @override
  void open({double velocity = 0.0}) {
    opens++;
    isOpen = true;
  }

  @override
  void close({double velocity = 0.0}) => isOpen = false;

  @override
  void toggle() => isOpen ? close() : open();
}

void main() {
  late SidebarTestTestSidebarActiveTab activeTab;
  late _Drawer drawer;

  Future<ProviderContainer> pump(WidgetTester tester) async {
    activeTab = SidebarTestTestSidebarActiveTab(SidebarTabId.chats);
    drawer = _Drawer();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settledActiveAccountIdProvider.overrideWith(_SettledOnA.new),
          sidebarActiveTabProvider.overrideWith(() => activeTab),
          sidebarNavigationSnapshotProvider.overrideWith(
            (ref) => SidebarNavigationSnapshot(
              tabs: ref.watch(_visibleTabsProvider),
              selectedTab: ref.watch(sidebarActiveTabProvider),
            ),
          ),
        ],
        child: MaterialApp(
          home: SidebarDrawerControllerScope(
            controller: drawer,
            child: const EmailOpenRequestListener(child: Text('content')),
          ),
        ),
      ),
    );
    return ProviderScope.containerOf(tester.element(find.text('content')));
  }

  testWidgets('a request selects the Email tab and opens the drawer', (
    tester,
  ) async {
    final container = await pump(tester);
    container.read(_visibleTabsProvider.notifier).show(const [
      SidebarTabId.chats,
      SidebarTabId.email,
    ]);
    await tester.pump();

    container.read(emailOpenRequestProvider.notifier).request();
    await tester.pump();
    await tester.pump();

    expect(activeTab.currentValue, SidebarTabId.email);
    expect(drawer.opens, 1);
    expect(container.read(emailOpenRequestProvider), isFalse);
  });

  testWidgets('a request waits until the Email tab exists', (tester) async {
    final container = await pump(tester);

    container.read(emailOpenRequestProvider.notifier).request();
    await tester.pump();
    await tester.pump();

    expect(activeTab.currentValue, SidebarTabId.chats);
    expect(drawer.opens, 0);
    expect(container.read(emailOpenRequestProvider), isTrue);

    container.read(_visibleTabsProvider.notifier).show(const [
      SidebarTabId.chats,
      SidebarTabId.email,
    ]);
    await tester.pump();
    await tester.pump();

    expect(activeTab.currentValue, SidebarTabId.email);
    expect(drawer.opens, 1);
    expect(container.read(emailOpenRequestProvider), isFalse);
  });

  testWidgets('an open drawer is left open', (tester) async {
    final container = await pump(tester);
    drawer.isOpen = true;
    container.read(_visibleTabsProvider.notifier).show(const [
      SidebarTabId.chats,
      SidebarTabId.email,
    ]);
    container.read(emailOpenRequestProvider.notifier).request();
    await tester.pump();
    await tester.pump();

    expect(activeTab.currentValue, SidebarTabId.email);
    expect(drawer.opens, 0);
  });

  group('EmailWebViewStorage', () {
    late List<String> cleared;
    late Completer<void> pending;
    late EmailWebViewStorage storage;

    setUp(() {
      cleared = [];
      pending = Completer<void>()..complete();
      storage = EmailWebViewStorage(
        clearOrigin: (origin) async => cleared.add(origin),
        serialize: <T>(Future<T> Function() operation) => operation(),
        waitForPending: () => pending.future,
      );
    });

    test('the same account reuses its storage', () async {
      await storage.prepare(accountId: 'a', origin: 'https://x.example');
      await storage.prepare(accountId: 'a', origin: 'https://x.example');
      expect(cleared, isEmpty);
    });

    test('another account clears the origin before its page loads', () async {
      await storage.prepare(accountId: 'a', origin: 'https://x.example');
      await storage.prepare(accountId: 'b', origin: 'https://x.example');
      expect(cleared, ['https://x.example']);
      expect(debugEmailWebViewOwners(storage), {'https://x.example': 'b'});
    });

    test('an account switch releases origins other accounts seeded', () async {
      await storage.prepare(accountId: 'a', origin: 'https://x.example');
      await storage.prepare(accountId: 'b', origin: 'https://y.example');

      storage.releaseOriginsNotOwnedBy('b');
      await Future<void>.delayed(Duration.zero);

      expect(cleared, ['https://x.example']);
      expect(debugEmailWebViewOwners(storage), {'https://y.example': 'b'});
    });

    test('prepare waits for queued WebView data operations', () async {
      pending = Completer<void>();
      var done = false;
      unawaited(
        storage
            .prepare(accountId: 'a', origin: 'https://x.example')
            .then((_) => done = true),
      );
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      pending.complete();
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
    });
  });
}
