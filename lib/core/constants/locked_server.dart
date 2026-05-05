/// Hardcoded OpenWebUI server this build is locked to.
///
/// Override these constants per customer branch. The values below are
/// deliberate placeholders so that an unforked saas-base build is obviously
/// unconfigured rather than silently pointing at someone else's server.
///
/// Customer branches replace [kLockedServerUrl], [kLockedServerName], and
/// [kBrandTagline] with their own brand values; everything else in the app
/// is wired through these constants so that swapping in a new customer is a
/// one-file change.
const String kLockedServerUrl = 'https://chat.example.com';

/// Stable identifier for the locked server config.
///
/// Using a fixed id (instead of a generated UUID) keeps a single, idempotent
/// row in storage across launches and reinstalls of the active-server
/// pointer. Safe to leave unchanged across customer branches.
const String kLockedServerId = 'locked-server';

/// Display name shown in any UI that surfaces the server (e.g. profile).
const String kLockedServerName = 'chat.example.com';

/// Brand tagline shown on the sign-in screen instead of the server URL.
/// Customer branches replace this with their product name / one-liner.
const String kBrandTagline = 'AI Assistant';
