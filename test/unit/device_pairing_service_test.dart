import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ani_dash/features/settings/data/device_pairing_service.dart';

void main() {
  group('DevicePairingService.parsePairingCode', () {
    test('accepts a valid manual code', () {
      expect(
        DevicePairingService.parsePairingCode('ABC_def-123'),
        'ABC_def-123',
      );
    });

    test('accepts official web and app links', () {
      expect(
        DevicePairingService.parsePairingCode(
          'https://anidashgo.vercel.app/connect?code=session_123',
        ),
        'session_123',
      );
      expect(
        DevicePairingService.parsePairingCode(
          'anidash://pair?code=session-456',
        ),
        'session-456',
      );
    });

    test('rejects foreign domains and malformed values', () {
      expect(
        DevicePairingService.parsePairingCode(
          'https://example.com/connect?code=session_123',
        ),
        isNull,
      );
      expect(DevicePairingService.parsePairingCode('short'), isNull);
      expect(DevicePairingService.parsePairingCode('bad code!'), isNull);
    });
  });

  test('inspect returns the browser identity for confirmation', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'anidashgo.vercel.app');
      expect(request.url.queryParameters['code'], 'session_123');
      return http.Response(
        '{"success":true,"session":{"expiresAt":"2026-11-26T12:05:00Z","device":{"name":"Chrome on PC","browser":"Chrome 142","os":"Windows 11","location":"Punjab, India"}}}',
        200,
      );
    });

    final inspection = await DevicePairingService(
      client: client,
    ).inspect('https://anidashgo.vercel.app/connect?code=session_123');

    expect(inspection.isSuccess, isTrue);
    expect(inspection.device?.name, 'Chrome on PC');
    expect(inspection.device?.browser, 'Chrome 142');
    expect(inspection.device?.operatingSystem, 'Windows 11');
  });

  test('denial explicitly rejects the pending website session', () async {
    late String requestBody;
    final client = MockClient((request) async {
      requestBody = request.body;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/device-pair/approve');
      return http.Response('{"success":true}', 200);
    });

    await DevicePairingService(client: client).deny('session_123');

    expect(requestBody, contains('"code":"session_123"'));
    expect(requestBody, contains('"approved":false'));
  });
}
