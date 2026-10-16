import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'deployment.dart';
import 'deployment_config.dart';

export 'deployment_config.dart';

/// The names and links of this build ([kDeployment]). Widgets read it here
/// so a test can show another brand; code without a provider scope reads
/// `kDeployment.brand`. The policy is `deploymentPolicyProvider`, which
/// `main.dart` binds to `kDeployment.policy`.
final brandConfigProvider = Provider<BrandConfig>((ref) => kDeployment.brand);
