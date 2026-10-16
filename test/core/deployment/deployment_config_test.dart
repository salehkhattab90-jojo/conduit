import 'package:checks/checks.dart';
import 'package:conduit/core/deployment/deployment.dart';
import 'package:conduit/core/deployment/deployment_providers.dart';
import 'package:conduit/core/deployment/native_sheet_deployment.dart';
import 'package:conduit/core/services/native_sheet_bridge.dart';
import 'package:conduit/core/utils/native_sheet_utils.dart';
import 'package:conduit/features/release_notes/data/release_links.dart';
import 'package:conduit/features/release_notes/release_notes_presenter.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit_core/features/support/support_links.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

final _l10n = lookupAppLocalizations(const Locale('en'));

const _locked = DeploymentPolicy.locked(
  LockedServer(
    id: 'locked-server',
    name: 'Example',
    urls: ['https://chat.example.test'],
  ),
);

/// A brand with no links of its own.
const _bare = BrandConfig(
  appName: 'Example',
  licenseAppName: 'Example',
  callkitAppName: 'Example',
  showReleaseNotes: false,
);

const _account = NativeProfileRootAccount(
  displayName: 'Ada',
  email: 'ada@example.com',
);

List<String> _ids(Iterable<NativeSheetSectionConfig> sections) => [
  for (final section in sections)
    for (final item in section.items) item.id,
];

void main() {
  group('the base build', () {
    test('ships the stock deployment', () {
      check(kDeployment.policy).identicalTo(DeploymentPolicy.unlocked);
      check(kDeployment.policy.isLocked).isFalse();
    });

    test("brands itself exactly as upstream Conduit", () {
      const brand = BrandConfig.stock();
      check(kDeployment.brand.appName).equals(brand.appName);
      check(brand.appName).equals('Conduit');
      check(brand.licenseAppName).equals('Conduit');
      check(brand.callkitAppName).equals('Conduit');
      check(brand.tagline).isNull();
      check(brand.showReleaseNotes).isTrue();
      check(brand.githubUrl).equals('https://github.com/cogwheel0/conduit');
      check(brand.githubLabel).equals('github.com/cogwheel0/conduit');
      check(brand.donationUrls?.buyMeACoffee).equals(buyMeACoffeeUrl);
      check(brand.donationUrls?.githubSponsors)
          .equals('https://github.com/sponsors/cogwheel0');
      for (final platform in TargetPlatform.values) {
        check(
          because: '$platform',
          brand.storeReviewUrls?.forPlatform(platform),
        ).equals(reviewUrlForPlatform(platform));
      }
    });
  });

  group('native Settings', () {
    test('stock keeps the account card, its sheet and the donations', () {
      final sections = buildNativeProfileRootSections(
        _l10n,
        account: _account,
        visibility: const NativeProfileRootVisibility(),
        card: (title: 'Ada', subtitle: null),
      );

      check(_ids(sections)).contains(nativeAccountsDetailId);
      check(_ids(sections)).contains(nativeAccountAddActionId);
      check(_ids(sections)).contains(nativeSignOutActionId);
      check(_ids(sections))
          .containsEqualInOrder(['buy-me-a-coffee', 'github-sponsors']);
      check(
        _ids([
          NativeSheetSectionConfig(
            items: buildNativeAboutItems(_l10n, appVersion: '1.0'),
          ),
        ]),
      ).containsEqualInOrder([NativeSheetRoutes.releaseNotesManual, 'github']);
    });

    test('a locked build names the account and nothing more', () {
      final sections = buildNativeProfileRootSections(
        _l10n,
        account: _account,
        visibility: const NativeProfileRootVisibility(),
        card: (title: 'Ada', subtitle: null),
        policy: _locked,
        brand: _bare,
      );
      final ids = _ids(sections);

      check(ids).not((it) => it.contains(nativeAccountsDetailId));
      check(ids).not((it) => it.contains(nativeAccountAddActionId));
      check(ids).contains(nativeAccountCardId);
      final card = sections
          .expand((section) => section.items)
          .singleWhere((item) => item.id == nativeAccountCardId);
      check(card.kind).equals(NativeSheetItemKind.info);
      // Sign out without the choice to forget the server.
      check(ids).not((it) => it.contains(nativeSignOutActionId));
      check(ids).contains(nativeAccountSignOutActionId);
      // No donation section without donation links.
      check(sections.map((section) => section.title))
          .not((it) => it.contains(_l10n.supportConduit));
    });

    test('a bare brand has no source or release notes rows', () {
      final ids = [
        for (final item in buildNativeAboutItems(
          _l10n,
          appVersion: '1.0',
          brand: _bare,
        ))
          item.id,
      ];
      check(ids).not((it) => it.contains('github'));
      check(ids).not((it) => it.contains(NativeSheetRoutes.releaseNotesManual));
      check(ids).contains(NativeSheetRoutes.openSourceLicenses);
      check(buildNativeSupportItems(_l10n, brand: _bare)).isEmpty();
    });

    test('a locked build lists no Hermes or Direct card', () {
      final stock = buildNativeAccountsDetail(
        _l10n,
        accounts: const [],
        hermesConnections: const [],
        hermesInUseId: null,
        directProfiles: const [],
      );
      final locked = buildNativeAccountsDetail(
        _l10n,
        accounts: const [],
        hermesConnections: const [],
        hermesInUseId: null,
        directProfiles: const [],
        policy: _locked,
      );

      check(_ids(stock.sections)).contains('accounts-hermes');
      check(_ids(stock.sections)).contains(NativeSheetRoutes.directConnections);
      check(_ids(locked.sections)).not((it) => it.contains('accounts-hermes'));
      check(_ids(locked.sections))
          .not((it) => it.contains(NativeSheetRoutes.directConnections));
      check(_ids(locked.sections)).contains('accounts-openwebui');
    });

    test('a locked build ignores the rows it does not offer', () {
      for (final actionId in [
        nativeConnectOpenWebUiActionId,
        nativeAccountSwitchActionId,
        nativeAccountAddActionId,
        nativeAccountServerActionId,
        nativeHermesUseActionId,
        nativeDirectEditActionId,
        NativeSheetRoutes.hermes,
        NativeSheetRoutes.directConnections,
      ]) {
        check(
          because: actionId,
          deploymentClosesNativeAction(_locked, actionId),
        ).isTrue();
        check(
          because: actionId,
          deploymentClosesNativeAction(DeploymentPolicy.unlocked, actionId),
        ).isFalse();
      }
      for (final actionId in [
        nativeAccountSignOutActionId,
        nativeSignOutActionId,
        NativeSheetRoutes.profile,
        NativeSheetRoutes.helpAbout,
      ]) {
        check(
          because: actionId,
          deploymentClosesNativeAction(_locked, actionId),
        ).isFalse();
      }
    });
  });

  group('release notes review', () {
    test('opens nothing for a brand without store pages', () async {
      final opened = <String>[];
      await requestReleaseNotesReview(
        platform: TargetPlatform.iOS,
        brand: _bare,
        launchReviewUrl: (url) async {
          opened.add(url);
          return true;
        },
      );
      check(opened).isEmpty();
    });
  });
}
