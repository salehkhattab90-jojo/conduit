import 'package:conduit_core/providers/backend_mode_providers.dart'
    show PreferredBackend;

import '../services/native_sheet_bridge.dart' show NativeSheetRoutes;
import '../utils/native_sheet_utils.dart';
import 'deployment_config.dart';

/// Whether [policy] closes the native Settings action [actionId].
///
/// The native sheet is built without the rows a deployment closes, so this
/// only meets a stale sheet or a row it does not know about; the router
/// still refuses the pages behind them. Sign-out is never closed.
bool deploymentClosesNativeAction(DeploymentPolicy policy, String actionId) {
  if (policy.isLocked && actionId == nativeConnectOpenWebUiActionId) {
    return true;
  }
  if (!policy.allowAccountManagement &&
      const {
        nativeAccountSwitchActionId,
        nativeAccountAddActionId,
        nativeAccountServerActionId,
        nativeHermesUseActionId,
        nativeDirectEditActionId,
      }.contains(actionId)) {
    return true;
  }
  if (!policy.allowsBackend(PreferredBackend.hermes) &&
      (actionId == NativeSheetRoutes.hermes ||
          actionId == nativeHermesUseActionId)) {
    return true;
  }
  if (!policy.allowsBackend(PreferredBackend.direct) &&
      (actionId == NativeSheetRoutes.directConnections ||
          actionId == nativeDirectEditActionId)) {
    return true;
  }
  return false;
}
