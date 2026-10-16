import 'package:flutter/foundation.dart' show visibleForTesting;

import 'deployment.dart';
import 'deployment_config.dart';

DeploymentConfig? _override;

/// The deployment the running code acts on: [kDeployment], this build's own,
/// unless a test pinned another with [debugDeploymentOverride].
///
/// Code reads the deployment here rather than [kDeployment] so the test suite
/// behaves the same on every branch: `test/flutter_test_config.dart` pins the
/// stock deployment, so a customer branch whose `deployment.dart` locks the
/// app still runs upstream's tests against upstream's behaviour.
DeploymentConfig get activeDeployment => _override ?? kDeployment;

/// Pins [activeDeployment] for tests; null returns to [kDeployment].
@visibleForTesting
set debugDeploymentOverride(DeploymentConfig? value) => _override = value;
