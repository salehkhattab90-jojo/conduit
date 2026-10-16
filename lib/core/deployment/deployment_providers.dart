import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'active_deployment.dart';
import 'deployment_config.dart';

export 'deployment_config.dart';

/// The names and links of this build ([activeDeployment]). Widgets read it
/// here so a test can show another brand; code without a provider scope reads
/// `activeDeployment.brand`. The policy is `deploymentPolicyProvider`, which
/// `main.dart` binds to `activeDeployment.policy`.
final brandConfigProvider = Provider<BrandConfig>(
  (ref) => activeDeployment.brand,
);
