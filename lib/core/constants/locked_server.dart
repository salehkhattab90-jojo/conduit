/// Hardcoded OpenWebUI server this build is locked to.
///
/// FADI customer branch — points the client at Furqaan AI's hosted OpenWebUI
/// instance. Override these constants when forking for a new customer.
const String kLockedServerUrl = 'https://fadi.furqaan.ai';

/// Stable identifier for the locked server config.
///
/// Using a fixed id (instead of a generated UUID) keeps a single, idempotent
/// row in storage across launches and reinstalls of the active-server
/// pointer.
const String kLockedServerId = 'locked-server';

/// Display name shown in any UI that surfaces the server (e.g. profile).
const String kLockedServerName = 'fadi.furqaan.ai';

/// Brand tagline shown on the sign-in screen instead of the server URL.
const String kBrandTagline = 'FADI (Furqaan AI Data & Intelligence)';
