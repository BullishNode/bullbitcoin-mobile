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

  test('does not mutate caller-supplied Dio options', () {
    bool customValidateStatus(int? status) => status == 418;
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://bullpay.test',
        connectTimeout: const Duration(milliseconds: 123),
        receiveTimeout: const Duration(milliseconds: 456),
        validateStatus: customValidateStatus,
      ),
    );

    final client = BullnymClient(dio: dio);

    expect(client, isA<BullnymClient>());
    expect(dio.options.baseUrl, 'https://bullpay.test');
    expect(dio.options.connectTimeout, const Duration(milliseconds: 123));
    expect(dio.options.receiveTimeout, const Duration(milliseconds: 456));
    expect(identical(dio.options.validateStatus, customValidateStatus), isTrue);
    expect(dio.options.validateStatus(418), isTrue);
    expect(dio.options.validateStatus(200), isFalse);
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

  test('parses donation page response shape', () async {
    final stub = _stubDio([
      _donationPageJson(
        website: 'https://alice.example',
        avatarSha256: 'aa' * 32,
      ),
    ]);
    final client = BullnymClient(dio: stub.dio);

    final response = await client.getPaymentPage(nym: 'alice');

    expect(response.nym, 'alice');
    expect(response.displayCurrency, 'CAD');
    expect(response.website, 'https://alice.example');
    expect(response.avatarSha256, 'aa' * 32);
    expect(response.isArchived, isFalse);
    final request = stub.captured.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/donation-page/alice');
  });

  test('parses server-supported currencies with precision', () async {
    final stub = _stubDio([
      {
        'currencies': [
          {'code': 'CAD', 'precision': 2},
          {'code': 'COP', 'precision': 0},
        ],
      },
    ]);
    final client = BullnymClient(dio: stub.dio);

    final response = await client.getSupportedCurrencies();

    expect(response.currencies.map((currency) => currency.code), [
      'CAD',
      'COP',
    ]);
    expect(response.currencies.last.precision, 0);
    final request = stub.captured.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/api/v1/supported-currencies');
  });

  test('rejects supported currencies response without currencies', () async {
    final stub = _stubDio([{}]);
    final client = BullnymClient(dio: stub.dio);

    await expectLater(
      client.getSupportedCurrencies(),
      throwsA(isA<TypeError>()),
    );
  });

  test(
    'puts signed donation page save requests in backend field order',
    () async {
      final stub = _stubDio([_donationPageJson()]);
      final client = BullnymClient(dio: stub.dio);

      final response = await client.savePaymentPage(
        handle: handle,
        nym: 'alice',
        header: "Alice's Coffee",
        description: 'Buy me a coffee',
        displayCurrency: 'CAD',
        website: 'https://alice.example',
        twitter: 'alice',
        instagram: 'alice_ig',
        enabled: true,
        timestampSecs: timestamp,
      );

      expect(response.publicUrl, 'https://bullpay.ca/alice');
      final request = stub.captured.requests.single;
      expect(request.method, 'PUT');
      expect(request.path, '/donation-page');
      expect(request.data, {
        'nym': 'alice',
        'header': "Alice's Coffee",
        'description': 'Buy me a coffee',
        'display_currency': 'CAD',
        'website': 'https://alice.example',
        'twitter': 'alice',
        'instagram': 'alice_ig',
        'enabled': true,
        'npub': handle.publicKeyHex,
        'signature': isA<String>().having((s) => s.length, 'length', 128),
        'timestamp': timestamp,
      });
      final payloadFields = [
        "Alice's Coffee",
        'Buy me a coffee',
        'CAD',
        'https://alice.example',
        'alice',
        'alice_ig',
        '1',
      ];
      _expectMessageBytes(
        action: bullpayActionDonationPageSave,
        npubHex: handle.publicKeyHex,
        nymOrEmpty: 'alice',
        payloadFields: payloadFields,
        timestampSecs: timestamp,
      );
      _expectSignatureValid(
        handle: handle,
        signatureHex:
            (request.data as Map<String, dynamic>)['signature'] as String,
        action: bullpayActionDonationPageSave,
        nymOrEmpty: 'alice',
        payloadFields: payloadFields,
        timestampSecs: timestamp,
      );
    },
  );

  test('signs absent donation page optional fields as empty strings', () async {
    final stub = _stubDio([_donationPageJson()]);
    final client = BullnymClient(dio: stub.dio);

    await client.savePaymentPage(
      handle: handle,
      nym: 'alice',
      header: 'Alice',
      description: 'Tips welcome',
      displayCurrency: 'USD',
      enabled: false,
      timestampSecs: timestamp,
    );

    final request = stub.captured.requests.single;
    expect((request.data as Map<String, dynamic>)['website'], '');
    expect((request.data as Map<String, dynamic>)['twitter'], '');
    expect((request.data as Map<String, dynamic>)['instagram'], '');
    _expectSignatureValid(
      handle: handle,
      signatureHex:
          (request.data as Map<String, dynamic>)['signature'] as String,
      action: bullpayActionDonationPageSave,
      nymOrEmpty: 'alice',
      payloadFields: ['Alice', 'Tips welcome', 'USD', '', '', '', '0'],
      timestampSecs: timestamp,
    );
  });

  test('archives donation page with signed archive action only', () async {
    final stub = _stubDio([_donationPageJson(isArchived: true)]);
    final client = BullnymClient(dio: stub.dio);

    final response = await client.archivePaymentPage(
      handle: handle,
      nym: 'alice',
      timestampSecs: timestamp,
    );

    expect(response.isArchived, isTrue);
    final request = stub.captured.requests.single;
    expect(request.method, 'DELETE');
    expect(request.path, '/donation-page');
    expect((request.data as Map<String, dynamic>)['nym'], 'alice');
    _expectMessageBytes(
      action: bullpayActionDonationPageArchive,
      npubHex: handle.publicKeyHex,
      nymOrEmpty: 'alice',
      payloadFields: const [],
      timestampSecs: timestamp,
    );
    _expectSignatureValid(
      handle: handle,
      signatureHex:
          (request.data as Map<String, dynamic>)['signature'] as String,
      action: bullpayActionDonationPageArchive,
      nymOrEmpty: 'alice',
      payloadFields: const [],
      timestampSecs: timestamp,
    );
  });

  test(
    'posts signed linked invoice create requests in backend field order',
    () async {
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        1710604800 * 1000,
        isUtc: true,
      );
      final stub = _stubDio([
        {
          'invoice_id': '00000000-0000-0000-0000-000000000001',
          'share_url':
              'https://bullpay.ca/alice/i/00000000-0000-0000-0000-000000000001',
        },
      ]);
      final client = BullnymClient(dio: stub.dio);

      final response = await client.createInvoice(
        handle: handle,
        nym: 'alice',
        amountSat: 5000,
        fiatAmountMinor: null,
        fiatCurrency: null,
        publicDescription: 'coffee',
        recipientName: 'Alice',
        invoiceNumber: 'INV-1',
        acceptBtc: false,
        acceptLn: true,
        acceptLiquid: true,
        bitcoinAddress: null,
        liquidAddress: 'lq1qq...',
        liquidBlindingKeyHex: '11' * 32,
        expiresAt: expiresAt,
        timestampSecs: timestamp,
      );

      expect(response.invoiceId, '00000000-0000-0000-0000-000000000001');
      final request = stub.captured.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/api/v1/alice/invoices');
      expect(request.data, {
        'npub': handle.publicKeyHex,
        'amount_sat': 5000,
        'public_description': 'coffee',
        'recipient_name': 'Alice',
        'invoice_number': 'INV-1',
        'accept_btc': false,
        'accept_ln': true,
        'accept_liquid': true,
        'liquid_address': 'lq1qq...',
        'liquid_blinding_key_hex': '11' * 32,
        'expires_at_unix': 1710604800,
        'signature': isA<String>().having((s) => s.length, 'length', 128),
        'timestamp': timestamp,
      });
      final payloadFields = [
        '5000',
        '',
        '',
        'coffee',
        'Alice',
        'INV-1',
        'false',
        'true',
        'true',
        '',
        'lq1qq...',
        '11' * 32,
        '1710604800',
      ];
      _expectMessageBytes(
        action: bullpayActionInvoiceCreate,
        npubHex: handle.publicKeyHex,
        nymOrEmpty: 'alice',
        payloadFields: payloadFields,
        timestampSecs: timestamp,
      );
      _expectSignatureValid(
        handle: handle,
        signatureHex:
            (request.data as Map<String, dynamic>)['signature'] as String,
        action: bullpayActionInvoiceCreate,
        nymOrEmpty: 'alice',
        payloadFields: payloadFields,
        timestampSecs: timestamp,
      );
    },
  );

  test(
    'signs Lightning-only invoice creation with empty blinding key field',
    () async {
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        1710604800 * 1000,
        isUtc: true,
      );
      final stub = _stubDio([
        {
          'invoice_id': '00000000-0000-0000-0000-000000000001',
          'share_url':
              'https://bullpay.ca/alice/i/00000000-0000-0000-0000-000000000001',
        },
      ]);
      final client = BullnymClient(dio: stub.dio);

      await client.createInvoice(
        handle: handle,
        nym: 'alice',
        amountSat: 5000,
        fiatAmountMinor: null,
        fiatCurrency: null,
        publicDescription: 'coffee',
        recipientName: 'Alice',
        invoiceNumber: 'INV-1',
        acceptBtc: false,
        acceptLn: true,
        acceptLiquid: false,
        bitcoinAddress: null,
        liquidAddress: 'lq1qq...',
        liquidBlindingKeyHex: null,
        expiresAt: expiresAt,
        timestampSecs: timestamp,
      );

      final request = stub.captured.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/api/v1/alice/invoices');
      expect(request.data, isNot(contains('liquid_blinding_key_hex')));
      final payloadFields = [
        '5000',
        '',
        '',
        'coffee',
        'Alice',
        'INV-1',
        'false',
        'true',
        'false',
        '',
        'lq1qq...',
        '',
        '1710604800',
      ];
      _expectMessageBytes(
        action: bullpayActionInvoiceCreate,
        npubHex: handle.publicKeyHex,
        nymOrEmpty: 'alice',
        payloadFields: payloadFields,
        timestampSecs: timestamp,
      );
      _expectSignatureValid(
        handle: handle,
        signatureHex:
            (request.data as Map<String, dynamic>)['signature'] as String,
        action: bullpayActionInvoiceCreate,
        nymOrEmpty: 'alice',
        payloadFields: payloadFields,
        timestampSecs: timestamp,
      );
    },
  );

  test(
    'deletes signed unlinked invoices with invoice id payload only',
    () async {
      final stub = _stubDio([
        {
          'invoice_id': '00000000-0000-0000-0000-000000000001',
          'status': 'cancelled',
        },
      ]);
      final client = BullnymClient(dio: stub.dio);

      final response = await client.cancelInvoice(
        handle: handle,
        invoiceId: '00000000-0000-0000-0000-000000000001',
        nym: null,
        timestampSecs: timestamp,
      );

      expect(response.status, 'cancelled');
      final request = stub.captured.requests.single;
      expect(request.method, 'DELETE');
      expect(
        request.path,
        '/api/v1/invoices/00000000-0000-0000-0000-000000000001',
      );
      _expectSignatureValid(
        handle: handle,
        signatureHex:
            (request.data as Map<String, dynamic>)['signature'] as String,
        action: bullpayActionInvoiceCancel,
        nymOrEmpty: '',
        payloadFields: ['00000000-0000-0000-0000-000000000001'],
        timestampSecs: timestamp,
      );
    },
  );

  test('gets signed invoice list with approved query contract', () async {
    final stub = _stubDio([
      {
        'invoices': [_invoiceListJson()],
        'page': 2,
        'pageSize': 25,
        'has_more': true,
      },
    ]);
    final client = BullnymClient(dio: stub.dio);

    final response = await client.listInvoices(
      handle: handle,
      page: 2,
      pageSize: 25,
      status: 'unpaid',
      timestampSecs: timestamp,
    );

    expect(response.invoices.single.status, 'unpaid');
    expect(response.page, 2);
    expect(response.pageSize, 25);
    expect(response.hasMore, isTrue);
    final request = stub.captured.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/api/v1/invoices');
    expect(request.queryParameters['npub'], handle.publicKeyHex);
    expect(request.queryParameters['page'], 2);
    expect(request.queryParameters['pageSize'], 25);
    expect(request.queryParameters['status'], 'unpaid');
    _expectSignatureValid(
      handle: handle,
      signatureHex: request.queryParameters['signature'] as String,
      action: bullpayActionInvoiceList,
      nymOrEmpty: '',
      payloadFields: ['2', '25', 'unpaid'],
      timestampSecs: timestamp,
    );
  });

  test('rejects invoice list page values outside backend bounds', () async {
    final client = BullnymClient(dio: _stubDio([]).dio);

    await expectLater(
      client.listInvoices(handle: handle, page: 0, pageSize: 25),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      client.listInvoices(handle: handle, page: 1001, pageSize: 25),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      client.listInvoices(handle: handle, page: 1, pageSize: 0),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      client.listInvoices(handle: handle, page: 1, pageSize: 101),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('parses invoice status response shape', () async {
    final stub = _stubDio([
      {
        'status': 'in_progress',
        'pricing_mode': 'fixed_sats',
        'settlement_status': 'none',
        'amount_sat': 1000,
        'fiat_amount_minor': null,
        'fiat_currency': null,
        'remaining_amount_sat': 1000,
        'payment_tolerance_sat': 1,
        'rate_minor_per_btc': null,
        'rate_locks_until_unix': 1710000900,
        'expires_at_unix': 1710604800,
        'paid_via': null,
        'paid_at_unix': null,
        'paid_amount_sat': null,
        'lightning_pr': 'lnbc...',
        'liquid_address': 'lq1qq...',
        'bitcoin_address': 'bc1q...',
        'bitcoin_chain_address': 'bc1qchain...',
        'bitcoin_chain_bip21': 'bitcoin:bc1qchain...?amount=0.00001000',
        'accept_btc': true,
        'accept_ln': true,
        'accept_liquid': true,
      },
    ]);
    final client = BullnymClient(dio: stub.dio);

    final response = await client.getInvoiceStatus(
      invoiceId: '00000000-0000-0000-0000-000000000001',
    );

    expect(response.status, 'in_progress');
    expect(response.lightningPr, 'lnbc...');
    expect(response.bitcoinChainAddress, 'bc1qchain...');
    expect(
      response.bitcoinChainBip21,
      'bitcoin:bc1qchain...?amount=0.00001000',
    );
    final request = stub.captured.requests.single;
    expect(request.method, 'GET');
    expect(
      request.path,
      '/api/v1/invoices/00000000-0000-0000-0000-000000000001/status',
    );
  });

  test('throws donation page backend errors with response status', () async {
    final stub = _stubDio(
      [
        {'status': 'ERROR', 'code': 'DonationPageNotFound', 'reason': 'alice'},
      ],
      statuses: [404],
    );
    final client = BullnymClient(dio: stub.dio);

    await expectLater(
      client.getPaymentPage(nym: 'alice'),
      throwsA(
        isA<BullnymException>()
            .having((e) => e.code, 'code', 'DonationPageNotFound')
            .having((e) => e.reason, 'reason', 'alice')
            .having((e) => e.statusCode, 'statusCode', 404),
      ),
    );
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

Map<String, dynamic> _invoiceListJson() {
  return {
    'id': '00000000-0000-0000-0000-000000000001',
    'nym_owner': 'alice',
    'origin': 'wallet',
    'status': 'unpaid',
    'amount_sat': 1000,
    'remaining_amount_sat': 1000,
    'fiat_amount_minor': null,
    'fiat_currency': null,
    'public_description': 'Coffee',
    'recipient_name': 'Alice',
    'invoice_number': 'INV-1',
    'accept_btc': true,
    'accept_ln': true,
    'accept_liquid': true,
    'bitcoin_address': 'bc1q...',
    'liquid_address': 'lq1qq...',
    'created_at_unix': 1710000000,
    'expires_at_unix': 1710604800,
    'paid_via': null,
    'paid_at_unix': null,
    'paid_amount_sat': null,
  };
}

Map<String, dynamic> _donationPageJson({
  String? website,
  String? twitter,
  String? instagram,
  bool isArchived = false,
  String? avatarSha256,
  String? ogSha256,
}) {
  return {
    'nym': 'alice',
    'header': "Alice's Coffee",
    'description': 'Buy me a coffee',
    'display_currency': 'CAD',
    'website': website,
    'twitter': twitter,
    'instagram': instagram,
    'enabled': true,
    'is_archived': isArchived,
    'avatar_sha256': avatarSha256,
    'og_sha256': ogSha256,
    'public_url': 'https://bullpay.ca/alice',
  };
}

void _expectMessageBytes({
  required String action,
  required String npubHex,
  required String nymOrEmpty,
  required List<String> payloadFields,
  required int timestampSecs,
}) {
  final expected = <int>[];
  void addField(String value) {
    expected.addAll(utf8.encode(value));
    expected.add(0);
  }

  addField(bullpayWireDomain);
  addField(action);
  addField(npubHex);
  addField(nymOrEmpty);
  for (final field in payloadFields) {
    addField(field);
  }
  expected.addAll(utf8.encode(timestampSecs.toString()));

  expect(
    buildBullpaySchnorrMessage(
      action: action,
      npubHex: npubHex,
      nymOrEmpty: nymOrEmpty,
      payloadFields: payloadFields,
      timestampSecs: timestampSecs,
    ),
    expected,
  );
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
