import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:conduit/core/services/confirmation_coordinator.dart';

class _FakeContext extends Fake implements BuildContext {}

/// Let queued microtasks (Completer callbacks, the coordinator drain loop) run.
Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  final coordinator = ConfirmationCoordinator.instance;

  setUp(() {
    coordinator.resetForTest();
    // Non-null context so the fake presenter is reached (never actually used).
    coordinator.contextProvider = () => _FakeContext();
  });

  tearDown(() => coordinator.resetForTest());

  group('ConfirmationRequest', () {
    test('cancel resolves to false and is idempotent (first-writer-wins)',
        () async {
      final req = ConfirmationRequest(const {'title': 't'});
      expect(req.isResolved, isFalse);

      req.cancel();
      expect(req.isResolved, isTrue);
      expect(await req.future, isFalse);

      // A second cancel (e.g. teardown after a late tap) must not throw or flip.
      req.cancel();
      expect(await req.future, isFalse);
    });
  });

  group('ConfirmationCoordinator', () {
    test('resolves to the presenter result (true then false)', () async {
      coordinator.presenter = (ctx, req) async => true;
      expect(await coordinator.request(const {'title': 'Send?'}).future, isTrue);

      coordinator.presenter = (ctx, req) async => false;
      expect(await coordinator.request(const {'title': 'Send?'}).future, isFalse);
    });

    test('fail-closed with no navigator context; presenter is not called',
        () async {
      var called = false;
      coordinator.contextProvider = () => null;
      coordinator.presenter = (ctx, req) async {
        called = true;
        return true;
      };
      final req = coordinator.request(const {'title': 'x'});
      expect(await req.future, isFalse);
      expect(called, isFalse);
    });

    test('presents strictly one dialog at a time (serial, FIFO)', () async {
      var active = 0;
      var maxActive = 0;
      final gates = <Completer<bool>>[];
      coordinator.presenter = (ctx, req) async {
        active++;
        if (active > maxActive) maxActive = active;
        final gate = Completer<bool>();
        gates.add(gate);
        final result = await gate.future;
        active--;
        return result;
      };

      final a = coordinator.request(const {'id': 'a'});
      final b = coordinator.request(const {'id': 'b'});
      await _tick();
      expect(gates.length, 1, reason: 'only A is presenting');

      gates[0].complete(true);
      expect(await a.future, isTrue);
      await _tick();
      expect(gates.length, 2, reason: 'B presents only after A resolves');

      gates[1].complete(false);
      expect(await b.future, isFalse);
      expect(maxActive, 1, reason: 'never two dialogs at once');
    });

    test('skips a request cancelled while still queued (no ghost dialog)',
        () async {
      final presented = <String>[];
      final gateA = Completer<bool>();
      coordinator.presenter = (ctx, req) async {
        final id = req.data['id'] as String;
        presented.add(id);
        return id == 'a' ? gateA.future : true;
      };

      final a = coordinator.request(const {'id': 'a'});
      final b = coordinator.request(const {'id': 'b'});
      await _tick();
      expect(presented, ['a'], reason: 'A presenting, B queued');

      b.cancel(); // cancelled before it is ever shown
      expect(await b.future, isFalse);

      gateA.complete(true);
      expect(await a.future, isTrue);
      await _tick();
      expect(presented, ['a'], reason: 'B was never presented');
    });
  });

  group('ConfirmationMessageBody (inert renderer)', () {
    testWidgets('renders text but stays inert for an injection payload',
        (tester) async {
      const payload =
          '- **To:** attacker@evil.com\n'
          '> quoted body line\n'
          '```mermaid\ngraph TD;A-->B;\n```\n'
          '<script>alert(1)</script>\n'
          '![x](http://evil/beacon.png)\n'
          '[click me](http://evil)';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ConfirmationMessageBody(message: payload),
          ),
        ),
      );

      // Content is shown as literal, inert text.
      expect(find.textContaining('attacker@evil.com'), findsWidgets);
      expect(find.textContaining('quoted body line'), findsWidgets);
      // The image/link markup is shown verbatim, never activated.
      expect(find.textContaining('beacon.png'), findsWidgets);

      // No executable or interactive surfaces within the body subtree
      // (scoped so framework chrome can't cause a false positive).
      final body = find.byType(ConfirmationMessageBody);
      expect(find.descendant(of: body, matching: find.byType(Image)),
          findsNothing);
      expect(find.descendant(of: body, matching: find.byType(GestureDetector)),
          findsNothing);
      expect(find.descendant(of: body, matching: find.byType(InkWell)),
          findsNothing);
    });
  });
}
