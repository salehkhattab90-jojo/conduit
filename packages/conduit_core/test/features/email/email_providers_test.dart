import 'package:conduit_core/features/email/providers/email_providers.dart';
import 'package:conduit_core/models/backend_config.dart';
import 'package:conduit_core/providers/app_providers.dart'
    show SettledActiveAccountId, settledActiveAccountIdProvider;
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

/// Settles where the test says.
final class _Settled extends SettledActiveAccountId {
  @override
  String? build() => 'a';

  void settle(String? accountId) => state = accountId;
}

/// Hands the test a provider [Ref], as notification handlers have.
final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  group('BackendConfig.enableEmail', () {
    test('reads features.enable_email', () {
      expect(
        BackendConfig.fromJson({
          'features': {'enable_email': true},
        }).enableEmail,
        isTrue,
      );
      expect(
        BackendConfig.fromJson({
          'features': {'enable_email': false},
        }).enableEmail,
        isFalse,
      );
      expect(BackendConfig.fromJson({'features': {}}).enableEmail, isNull);
      expect(
        BackendConfig.fromJson({
          'features': {'enable_email': 'yes'},
        }).enableEmail,
        isNull,
      );
    });

    test('survives the local cache round trip and copyWith', () {
      final config = BackendConfig.fromJson({
        'features': {'enable_email': true},
      });
      expect(BackendConfig.fromJson(config.toJson()).enableEmail, isTrue);
      expect(config.copyWith(serverId: 's').enableEmail, isTrue);
      expect(config.copyWith(enableEmail: false).enableEmail, isFalse);
    });
  });

  group('emailFeatureEnabled', () {
    const on = BackendConfig(serverId: 'acct-a', enableEmail: true);

    test('only for a config fetched from that server that says true', () {
      expect(emailFeatureEnabled(config: on, serverId: 'acct-a'), isTrue);
      expect(emailFeatureEnabled(config: on, serverId: 'acct-b'), isFalse);
      expect(emailFeatureEnabled(config: null, serverId: 'acct-a'), isFalse);
      expect(
        emailFeatureEnabled(
          config: const BackendConfig(serverId: 'acct-a'),
          serverId: 'acct-a',
        ),
        isFalse,
      );
      expect(
        emailFeatureEnabled(
          config: const BackendConfig(serverId: 'acct-a', enableEmail: false),
          serverId: 'acct-a',
        ),
        isFalse,
      );
    });
  });

  group('email open request', () {
    late ProviderContainer container;
    late _Settled settled;

    setUp(() {
      settled = _Settled();
      container = ProviderContainer(
        overrides: [settledActiveAccountIdProvider.overrideWith(() => settled)],
      );
      // Keep both alive the way the shell and the tab do.
      container.listen(emailOpenRequestProvider, (_, _) {});
      container.listen(pendingEmailMessageProvider, (_, _) {});
    });

    tearDown(() => container.dispose());

    test('a tap with a message asks for the section and keeps the id', () {
      requestEmailOpen(container.read(_refProvider), ' msg-1 ');

      expect(container.read(emailOpenRequestProvider), isTrue);
      expect(container.read(pendingEmailMessageProvider), 'msg-1');

      container.read(emailOpenRequestProvider.notifier).consume();
      expect(container.read(emailOpenRequestProvider), isFalse);
      // The message waits for the web app independently of the shell.
      expect(container.read(pendingEmailMessageProvider), 'msg-1');

      container.read(pendingEmailMessageProvider.notifier).clear();
      expect(container.read(pendingEmailMessageProvider), isNull);
    });

    test('a tap without a message only opens the section', () {
      requestEmailOpen(container.read(_refProvider), '');

      expect(container.read(emailOpenRequestProvider), isTrue);
      expect(container.read(pendingEmailMessageProvider), isNull);
    });

    test('an account switch drops the previous account\'s request', () {
      requestEmailOpen(container.read(_refProvider), 'msg-1');

      settled.settle('b');

      expect(container.read(emailOpenRequestProvider), isFalse);
      expect(container.read(pendingEmailMessageProvider), isNull);
    });
  });
}
