// Open WebUI 0.12 ends a user's socket sessions itself on password, MFA, role
// and group changes (`io server disconnect`), which Socket.IO does not recover
// from on its own, and announces access changes with `access:updated`.
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/ports/app_lifecycle.dart';
import 'package:conduit_core/services/socket_service.dart';
import 'package:conduit_core/testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:test/test.dart';

const _serverConfig = ServerConfig(
  id: 'test-server',
  name: 'Test Server',
  url: 'https://example.test',
);

class _RecordingSocketFactory {
  final List<io.Socket> sockets = <io.Socket>[];

  io.Socket create(
    String base,
    io.OptionBuilder builder,
    ServerConfig serverConfig,
  ) {
    final socket = io.io(
      'http://localhost:${19500 + sockets.length}',
      <String, dynamic>{
        'autoConnect': false,
        'forceNew': true,
        'reconnection': false,
      },
    );
    sockets.add(socket);
    return socket;
  }
}

void _connected(io.Socket socket) {
  socket.connected = true;
  socket.emitReserved('connect');
}

void _serverDisconnect(io.Socket socket) {
  socket.connected = false;
  socket.emitReserved('disconnect', 'io server disconnect');
}

void main() {
  test('backs off from half a second, doubling, to at most 30 s', () {
    expect(
      [
        for (var attempt = 0; attempt < 8; attempt++)
          SocketService.serverDisconnectReconnectDelay(attempt).inMilliseconds,
      ],
      [500, 1000, 2000, 4000, 8000, 16000, 30000, 30000],
    );
  });

  test('reconnects after the server ends the session', () {
    fakeAsync((async) {
      final factory = _RecordingSocketFactory();
      final service = SocketService(
        serverConfig: _serverConfig,
        socketFactory: factory.create,
      );
      service.connect();
      async.flushMicrotasks();
      _connected(factory.sockets.single);

      _serverDisconnect(factory.sockets.single);
      async.elapse(const Duration(milliseconds: 499));
      expect(factory.sockets, hasLength(1));
      async.elapse(const Duration(milliseconds: 2));
      async.flushMicrotasks();
      expect(factory.sockets, hasLength(2));
      expect(service.socket, same(factory.sockets.last));

      service.dispose();
    });
  });

  test('a disconnect the client caused is left to Socket.IO', () {
    fakeAsync((async) {
      final factory = _RecordingSocketFactory();
      final service = SocketService(
        serverConfig: _serverConfig,
        socketFactory: factory.create,
      );
      service.connect();
      async.flushMicrotasks();
      _connected(factory.sockets.single);

      factory.sockets.single
        ..connected = false
        ..emitReserved('disconnect', 'transport close');
      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();
      expect(factory.sockets, hasLength(1));

      service.dispose();
    });
  });

  test('a refused reconnection is retried with backoff, then given up', () {
    fakeAsync((async) {
      final factory = _RecordingSocketFactory();
      final service = SocketService(
        serverConfig: _serverConfig,
        socketFactory: factory.create,
      );
      service.connect();
      async.flushMicrotasks();
      _connected(factory.sockets.single);
      _serverDisconnect(factory.sockets.single);

      for (var attempt = 0; attempt < 6; attempt++) {
        async.elapse(SocketService.serverDisconnectReconnectDelay(attempt));
        async.flushMicrotasks();
        expect(factory.sockets, hasLength(attempt + 2));
        factory.sockets.last.emitReserved('connect_error', 'unauthorized');
      }
      async.elapse(const Duration(minutes: 5));
      async.flushMicrotasks();
      expect(factory.sockets, hasLength(7));

      service.dispose();
    });
  });

  test('a session that comes back resets the backoff', () {
    fakeAsync((async) {
      final factory = _RecordingSocketFactory();
      final service = SocketService(
        serverConfig: _serverConfig,
        socketFactory: factory.create,
      );
      service.connect();
      async.flushMicrotasks();
      _connected(factory.sockets.single);

      for (var round = 0; round < 3; round++) {
        _serverDisconnect(factory.sockets.last);
        async.elapse(const Duration(milliseconds: 501));
        async.flushMicrotasks();
        expect(factory.sockets, hasLength(round + 2));
        _connected(factory.sockets.last);
      }

      service.dispose();
    });
  });

  test('nothing is scheduled while the app is in the background', () {
    fakeAsync((async) {
      final lifecycle = FakeAppLifecycle();
      final factory = _RecordingSocketFactory();
      final service = SocketService(
        lifecycle: lifecycle,
        serverConfig: _serverConfig,
        socketFactory: factory.create,
      );
      service.connect();
      async.flushMicrotasks();
      _connected(factory.sockets.single);

      lifecycle.emit(AppLifecyclePhase.paused);
      async.flushMicrotasks();
      _serverDisconnect(factory.sockets.single);
      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();
      expect(factory.sockets, hasLength(1));

      service.dispose();
      lifecycle.dispose();
    });
  });

  test('an access change is announced once the session is back', () {
    fakeAsync((async) {
      final factory = _RecordingSocketFactory();
      final service = SocketService(
        serverConfig: _serverConfig,
        socketFactory: factory.create,
      );
      var announced = 0;
      service.onAccessUpdated.listen((_) => announced++);
      service.connect();
      async.flushMicrotasks();
      _connected(factory.sockets.single);
      async.flushMicrotasks();
      expect(announced, 0);

      factory.sockets.single.emitReserved(
        'access:updated',
        <String, dynamic>{},
      );
      _serverDisconnect(factory.sockets.single);
      async.flushMicrotasks();
      expect(announced, 0);

      async.elapse(const Duration(milliseconds: 501));
      async.flushMicrotasks();
      _connected(factory.sockets.last);
      async.flushMicrotasks();
      expect(announced, 1);

      // Later sessions announce nothing new.
      _serverDisconnect(factory.sockets.last);
      async.elapse(const Duration(milliseconds: 501));
      async.flushMicrotasks();
      _connected(factory.sockets.last);
      async.flushMicrotasks();
      expect(announced, 1);

      service.dispose();
    });
  });
}
