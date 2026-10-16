// The deployment this build is made for: FADI (Furqaan AI Data & Intelligence),
// locked to its hosted Open WebUI. This file is the customer branch's override
// of the base's stock deployment; nothing else in lib/ names the customer.
import 'deployment_config.dart';

const kDeployment = DeploymentConfig(
  policy: DeploymentPolicy.locked(
    LockedServer(
      // Kept from the earlier fork so existing installs keep their session.
      id: 'locked-server',
      name: 'fadi.furqaan.ai',
      urls: ['https://fadi.furqaan.ai'],
    ),
    authModes: {DeploymentSignInMode.credentials, DeploymentSignInMode.sso},
    ssoProviders: ['google'],
  ),
  brand: BrandConfig(
    appName: 'FADI',
    tagline: 'FADI (Furqaan AI Data & Intelligence)',
    licenseAppName: 'FADI',
    callkitAppName: 'FADI',
    showReleaseNotes: false,
  ),
);
