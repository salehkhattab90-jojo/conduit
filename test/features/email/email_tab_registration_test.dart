import 'package:conduit/features/navigation/widgets/sidebar_tab_registry.dart';
import 'package:conduit/l10n/app_localizations_en.dart';
import 'package:conduit_core/features/navigation/models/sidebar_navigation_model.dart';
import 'package:flutter_test/flutter_test.dart';

SidebarTabAvailability _availability({
  bool hermesOnly = false,
  bool hasOpenWebUi = true,
  bool emailEnabled = false,
}) => SidebarTabAvailability(
  hermesOnly: hermesOnly,
  hasOpenWebUi: hasOpenWebUi,
  hermesEnabled: false,
  notesEnabled: true,
  terminalEnabled: false,
  channelsEnabled: true,
  emailEnabled: emailEnabled,
);

void main() {
  group('Email sidebar tab', () {
    test('is shown only when the server offers Email', () {
      expect(
        visibleSidebarTabIds(_availability()),
        isNot(contains(SidebarTabId.email)),
      );
      expect(visibleSidebarTabIds(_availability(emailEnabled: true)), [
        SidebarTabId.chats,
        SidebarTabId.email,
        SidebarTabId.notes,
        SidebarTabId.channels,
      ]);
    });

    test('needs a signed-in Open WebUI account', () {
      expect(
        visibleSidebarTabIds(
          _availability(emailEnabled: true, hasOpenWebUi: false),
        ),
        isNot(contains(SidebarTabId.email)),
      );
      expect(
        visibleSidebarTabIds(
          _availability(emailEnabled: true, hermesOnly: true),
        ),
        isNot(contains(SidebarTabId.email)),
      );
    });

    test('has its own label and search hint', () {
      final l10n = AppLocalizationsEn();
      final descriptor = sidebarTabDescriptor(SidebarTabId.email);
      expect(descriptor.label(l10n), 'Email');
      expect(descriptor.searchHint(l10n), 'Search email...');
      expect(descriptor.sfSymbol, 'envelope');
      expect(descriptor.createAction, isNull);
    });

    test('is persisted by name', () {
      expect(SidebarTabId.values.byName('email'), SidebarTabId.email);
    });
  });
}
