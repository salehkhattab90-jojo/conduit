import 'package:conduit/core/deployment/deployment_providers.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/widgets/sign_out_options_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _locked = DeploymentPolicy.locked(
  LockedServer(
    id: 'locked-server',
    name: 'Example',
    urls: ['https://chat.example.test'],
  ),
);

void main() {
  testWidgets('a locked build signs out keeping its server, without asking', (
    tester,
  ) async {
    bool? result;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [deploymentPolicyProvider.overrideWithValue(_locked)],
        child: MaterialApp(
          localizationsDelegates: conduitLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showSignOutOptionsDialog(context);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sign-out-keep-server-details')), findsNothing);
    expect(find.text('Keep server details'), findsNothing);

    await tester.tap(find.byKey(const Key('sign-out-confirm')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
