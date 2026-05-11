import 'dart:convert';

import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/get_paid/shared/bullnym/bullnym_client.dart';
import 'package:bb_mobile/features/get_paid/shared/bullnym/bullnym_errors.dart';
import 'package:bb_mobile/features/get_paid/shared/bullnym/bullpay_signing.dart';
import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockHttpAdapter extends Mock implements HttpClientAdapter {}

class _Captured {
  final List<RequestOptions> requests = [];
}

({Dio dio, _Captured captured}) _stubDio(
  List<Map<String, dynamic>> responses, {
  List<int>? statuses,
}) {
  final captured = _Captured();
  final adapter = _MockHttpAdapter();
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://bullpay.test',
      validateStatus: (status) => status != null && status < 600,
    ),
  )..httpClientAdapter = adapter;
  var index = 0;

  when(() => adapter.fetch(any(), any(), any())).thenAnswer((inv) async {
    final opts = inv.positionalArguments[0] as RequestOptions;
    captured.requests.add(opts);
    final body = responses[index];
    final status = statuses == null ? 200 : statuses[index];
    index += 1;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        'content-type': ['application/json'],
      },
    );
  });

  return (dio: dio, captured: captured);
}

void main() {
  const timestamp = 1710000000;

  late NostrKeychainHandle handle;

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: ''));
  });

  setUp(() {
    handle = NostrKeychainHandle.fromSecretKeyHex('01' * 32);
  });

  test(
    'posts signed register requests using ct_descriptor as payload',
    () async {
      final stub = _stubDio([
        {
          'nym': 'alice',
          'lightning_address': 'alice@bullpay.ca',
          'nip05': 'alice@bullpay.ca',
          'quota': {'used': 1, 'cap': 5, 'remaining': 4},
        },
      ]);
      final client = BullnymClient(dio: stub.dio);

      final response = await client.register(
        handle: handle,
        nym: 'alice',
        ctDescriptor: 'ct-desc',
        timestampSecs: timestamp,
      );

      expect(response.nym, 'alice');
      final request = stub.captured.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/register');
      expect(request.data, {
        'nym': 'alice',
        'ct_descriptor': 'ct-desc',
        'npub': handle.publicKeyHex,
        'signature': isA<String>().having((s) => s.length, 'length', 128),
        'timestamp': timestamp,
      });
      _expectSignatureValid(
        handle: handle,
        signatureHex:
            (request.data as Map<String, dynamic>)['signature'] as String,
        action: bullpayActionRegister,
        nymOrEmpty: 'alice',
        payloadFields: ['ct-desc'],
        timestampSecs: timestamp,
      );
    },
  );

  test('deletes registration with a signed delete action', () async {
    final stub = _stubDio([
      {
        'quota': {'used': 1, 'cap': 5, 'remaining': 4},
      },
    ]);
    final client = BullnymClient(dio: stub.dio);

    final response = await client.deleteRegistration(
      handle: handle,
      nym: 'alice',
      timestampSecs: timestamp,
    );

    expect(response.quota.remaining, 4);
    final request = stub.captured.requests.single;
    expect(request.method, 'DELETE');
    expect(request.path, '/register');
    expect((request.data as Map<String, dynamic>)['nym'], 'alice');
    expect(
      (request.data as Map<String, dynamic>).containsKey('purge'),
      isFalse,
    );
    _expectSignatureValid(
      handle: handle,
      signatureHex:
          (request.data as Map<String, dynamic>)['signature'] as String,
      action: bullpayActionDelete,
      nymOrEmpty: 'alice',
      payloadFields: const [],
      timestampSecs: timestamp,
    );
  });

  test('parses backend lookup response shape', () async {
    final stub = _stubDio([
      {
        'nym': 'alice',
        'active': false,
        'quota': {'used': 2, 'cap': 5, 'remaining': 3},
        'previous_nyms': [
          {'nym': 'alice', 'created_at': '2026-05-10T12:00:00Z'},
        ],
      },
    ]);
    final client = BullnymClient(dio: stub.dio);

    final response = await client.lookupRegistration(npubHex: 'aa' * 32);

    expect(response.active, isFalse);
    expect(response.quota.used, 2);
    expect(response.previousNyms.single.nym, 'alice');
    final request = stub.captured.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/register/lookup');
    expect(request.queryParameters['npub'], 'aa' * 32);
  });

  test('throws backend error envelopes even on HTTP 200', () async {
    final stub = _stubDio([
      {'status': 'ERROR', 'code': 'NymTaken', 'reason': 'nym taken'},
    ]);
    final client = BullnymClient(dio: stub.dio);

    await expectLater(
      client.lookupRegistration(npubHex: 'aa' * 32),
      throwsA(
        isA<BullnymException>()
            .having((e) => e.code, 'code', 'NymTaken')
            .having((e) => e.reason, 'reason', 'nym taken'),
      ),
    );
  });
}

void _expectSignatureValid({
  required NostrKeychainHandle handle,
  required String signatureHex,
  required String action,
  required String nymOrEmpty,
  required List<String> payloadFields,
  required int timestampSecs,
}) {
  final message = buildBullpaySchnorrMessage(
    action: action,
    npubHex: handle.publicKeyHex,
    nymOrEmpty: nymOrEmpty,
    payloadFields: payloadFields,
    timestampSecs: timestampSecs,
  );
  final digest = sha256.convert(message).bytes;
  final pub = ECPublic.fromHex('02${handle.publicKeyHex}');
  expect(
    pub.verifyBip340Signature(
      digest: digest,
      signature: hex.decode(signatureHex),
      tweak: false,
    ),
    isTrue,
  );
}
