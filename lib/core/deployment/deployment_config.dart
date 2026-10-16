import 'package:conduit_core/deployment/deployment_policy.dart';
import 'package:conduit_core/features/support/support_links.dart'
    show buyMeACoffeeUrl;
import 'package:flutter/foundation.dart' show TargetPlatform;

import '../../features/release_notes/data/release_links.dart'
    show appleAppStoreReviewUrl, googlePlayStoreUrl;

export 'package:conduit_core/deployment/deployment_policy.dart';

/// Links asking for a donation. A surface shows only the ones that are set.
final class DonationUrls {
  const DonationUrls({this.buyMeACoffee, this.githubSponsors});

  final String? buyMeACoffee;
  final String? githubSponsors;

  bool get isEmpty => buyMeACoffee == null && githubSponsors == null;
}

/// Store pages where a user can review the app.
final class StoreReviewUrls {
  const StoreReviewUrls({this.appleAppStore, this.googlePlay});

  final String? appleAppStore;
  final String? googlePlay;

  /// The review page for [platform]: the App Store on Apple platforms,
  /// Google Play elsewhere.
  String? forPlatform(TargetPlatform platform) => switch (platform) {
    TargetPlatform.iOS || TargetPlatform.macOS => appleAppStore,
    _ => googlePlay,
  };
}

/// The names and links a build shows as its own.
///
/// The stock values are upstream Conduit's, so a stock build looks exactly
/// like upstream. A surface with a link shows it only when the link is set.
/// The product name inside translated strings is rewritten separately, by
/// `tool/apply_brand_strings.dart`.
final class BrandConfig {
  const BrandConfig({
    required this.appName,
    this.tagline,
    required this.licenseAppName,
    required this.callkitAppName,
    this.githubUrl,
    this.donationUrls,
    this.storeReviewUrls,
    this.showReleaseNotes = true,
  });

  /// Upstream Conduit.
  const BrandConfig.stock()
    : appName = 'Conduit',
      tagline = null,
      licenseAppName = 'Conduit',
      callkitAppName = 'Conduit',
      githubUrl = 'https://github.com/cogwheel0/conduit',
      donationUrls = const DonationUrls(
        buyMeACoffee: buyMeACoffeeUrl,
        githubSponsors: 'https://github.com/sponsors/cogwheel0',
      ),
      storeReviewUrls = const StoreReviewUrls(
        appleAppStore: appleAppStoreReviewUrl,
        googlePlay: googlePlayStoreUrl,
      ),
      showReleaseNotes = true;

  /// The product name in untranslated text (App Intents replies, semantic
  /// labels).
  final String appName;

  /// Shown under the sign-in title in place of the server address; null
  /// keeps the address.
  final String? tagline;

  /// The name on the open-source licenses page.
  final String licenseAppName;

  /// The app name CallKit shows for a voice call.
  final String callkitAppName;

  /// The app's source repository, offered in About.
  final String? githubUrl;

  /// Donation links in Settings and in the release notes.
  final DonationUrls? donationUrls;

  /// Store review links in the release notes.
  final StoreReviewUrls? storeReviewUrls;

  /// Whether the bundled (upstream Conduit) release notes are shown: the
  /// banner after an update, the sheet, and the About row.
  final bool showReleaseNotes;

  /// [githubUrl] as shown under its row: host and path, no scheme.
  String? get githubLabel {
    final url = githubUrl;
    if (url == null) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    return '${uri.host}${uri.path}';
  }
}

/// One deployment of the app: what it may do and what it is called.
final class DeploymentConfig {
  const DeploymentConfig({required this.policy, required this.brand});

  /// Upstream Conduit, unlocked.
  const DeploymentConfig.stock()
    : policy = DeploymentPolicy.unlocked,
      brand = const BrandConfig.stock();

  final DeploymentPolicy policy;
  final BrandConfig brand;
}
