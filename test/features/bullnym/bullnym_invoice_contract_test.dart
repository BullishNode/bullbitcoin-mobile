import 'dart:convert';
import 'dart:typed_data';

import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/bullnym/data/bullnym_http_client.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_invoice_actions.dart';
import 'package:bb_mobile/features/bullnym/domain/bullpay_signing.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockHttpAdapter extends Mock implements HttpClientAdapter {}

class _Captured {
  final List<RequestOptions> requests = [];
}

({Dio dio, _Captured captured}) _stubDio(
  List<Object?> responses, {
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
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        'content-type': ['application/json'],
      },
    );
  });

  return (dio: dio, captured: captured);
}

// Independent hand-built oracle of the signed byte layout — derived from the
// server's documented `bullpay-la-v2` wire format
// (`src/auth.rs::build_la_v2_message` + `src/invoice.rs` field builders), NOT
// from the production `buildBullpaySchnorrMessage`.
List<int> _oracleMessageBytes({
  required String action,
  required String npubHex,
  required String nymOrEmpty,
  required List<String> payloadFields,
  required int timestampSecs,
}) {
  final bytes = <int>[];
  void addField(String value) {
    bytes.addAll(utf8.encode(value));
    bytes.add(0);
  }

  addField('bullpay-la-v2');
  addField(action);
  addField(npubHex);
  addField(nymOrEmpty);
  for (final field in payloadFields) {
    addField(field);
  }
  bytes.addAll(utf8.encode(timestampSecs.toString()));
  return bytes;
}

Map<String, dynamic> _statusView({String status = 'unpaid'}) {
  return {
    'status': status,
    'pricing_mode': 'sat',
    'settlement_status': 'none',
    'amount_sat': 25000,
    'fiat_amount_minor': null,
    'fiat_currency': null,
    'remaining_amount_sat': 25000,
    'payment_tolerance_sat': 0,
    'rate_minor_per_btc': null,
    'rate_locks_until_unix': 1710000000,
    'expires_at_unix': 1710086400,
    'paid_via': null,
    'paid_at_unix': null,
    'paid_amount_sat': null,
    'lightning_pr': null,
    'liquid_address': 'lq1qtest',
    'bitcoin_address': null,
    'bitcoin_direct_observations': [],
    'bitcoin_chain_address': null,
    'bitcoin_chain_bip21': null,
    'accept_btc': false,
    'accept_ln': true,
    'accept_liquid': true,
    // A future server field the older binary must ignore (tolerant reader).
    'some_unknown_future_field': 'ignored',
  };
}

Map<String, dynamic> _listItemView({String? nymOwner, bool paid = false}) {
  return {
    'id': 'inv-1',
    'nym_owner': nymOwner,
    'origin': 'wallet',
    'status': paid ? 'paid' : 'unpaid',
    'pricing_mode': 'sat',
    'settlement_status': 'none',
    'amount_sat': 25000,
    'remaining_amount_sat': paid ? 0 : 25000,
    'fiat_amount_minor': null,
    'fiat_currency': null,
    'public_description': 'Consulting',
    'recipient_name': 'Acme',
    'invoice_number': 'INV-042',
    'accept_btc': false,
    'accept_ln': true,
    'accept_liquid': true,
    'bitcoin_address': null,
    'liquid_address': 'lq1qtest',
    'created_at_unix': 1710000000,
    'expires_at_unix': 1710086400,
    'paid_via': paid ? 'liquid' : null,
    'paid_at_unix': paid ? 1710001000 : null,
    'paid_amount_sat': paid ? 25000 : null,
    'extra_unknown_key': true,
  };
}

BullnymCreateInvoiceFields _lnLiquidFields() {
  return const BullnymCreateInvoiceFields(
    amountSat: 25000,
    acceptBtc: false,
    acceptLn: true,
    acceptLiquid: true,
    liquidAddress: 'lq1qtest',
    liquidBlindingKeyHex: 'ab12cd',
    expiresAtUnix: 1710086400,
  );
}

void main() {
  const timestamp = 1710000000;
  late NostrKeychainHandle handle;
  late BullnymAuthSigner signer;

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: ''));
  });

  setUp(() {
    handle = _bullnymAuthHandle();
    signer = _signerFromHandle(handle);
  });

  group('T-INV-SIGN invoice-create byte layout', () {
    test('action constant is the deployed wire name', () {
      expect(bullpayActionInvoiceCreate, 'invoice-create');
    });

    test(
      'pins the unlinked 13-field layout: all fields present, empties as "", '
      'booleans true/false, nym slot empty',
      () {
        // Fiat-denominated, LN+Liquid, no BTC — so amount_sat is empty, fiat
        // fields present, bitcoin_address empty. Hand-derived oracle.
        final fields = const BullnymCreateInvoiceFields(
          fiatAmountMinor: 1050,
          fiatCurrency: 'CAD',
          publicDescription: 'Consulting',
          recipientName: 'Acme',
          invoiceNumber: 'INV-042',
          acceptBtc: false,
          acceptLn: true,
          acceptLiquid: true,
          liquidAddress: 'lq1qtest',
          liquidBlindingKeyHex: 'ab12cd',
          expiresAtUnix: 1710086400,
        );
        final oracle = _oracleMessageBytes(
          action: 'invoice-create',
          npubHex: 'npub',
          nymOrEmpty: '',
          payloadFields: const [
            '', // amount_sat empty (fiat-denominated)
            '1050', // fiat_amount_minor
            'CAD', // fiat_currency
            'Consulting', // public_description
            'Acme', // recipient_name
            'INV-042', // invoice_number
            'false', // accept_btc
            'true', // accept_ln
            'true', // accept_liquid
            '', // bitcoin_address empty (no BTC rail)
            'lq1qtest', // liquid_address
            'ab12cd', // liquid_blinding_key_hex
            '1710086400', // expires_at_unix
          ],
          timestampSecs: timestamp,
        );

        expect(
          buildBullpaySchnorrMessage(
            action: bullpayActionInvoiceCreate,
            npubHex: 'npub',
            nymOrEmpty: '',
            payloadFields: buildInvoiceCreatePayloadFields(fields),
            timestampSecs: timestamp,
          ),
          oracle,
        );
        expect(buildInvoiceCreatePayloadFields(fields).length, 13);
      },
    );

    test('sat-denominated omitted-optionals still emit all 13 fields', () {
      final fields = const BullnymCreateInvoiceFields(
        amountSat: 25000,
        acceptBtc: true,
        acceptLn: false,
        acceptLiquid: false,
        bitcoinAddress: 'bc1qtest',
        expiresAtUnix: 1710086400,
      );
      expect(buildInvoiceCreatePayloadFields(fields), const [
        '25000',
        '', // fiat_amount_minor
        '', // fiat_currency
        '', // public_description
        '', // recipient_name
        '', // invoice_number
        'true', // accept_btc
        'false', // accept_ln
        'false', // accept_liquid
        'bc1qtest',
        '', // liquid_address
        '', // liquid_blinding_key_hex
        '1710086400',
      ]);
    });

    test('linked variant signs the nym in the nym slot', () {
      final oracle = _oracleMessageBytes(
        action: 'invoice-create',
        npubHex: 'npub',
        nymOrEmpty: 'alice',
        payloadFields: buildInvoiceCreatePayloadFields(_lnLiquidFields()),
        timestampSecs: timestamp,
      );
      expect(
        buildBullpaySchnorrMessage(
          action: bullpayActionInvoiceCreate,
          npubHex: 'npub',
          nymOrEmpty: 'alice',
          payloadFields: buildInvoiceCreatePayloadFields(_lnLiquidFields()),
          timestampSecs: timestamp,
        ),
        oracle,
      );
    });
  });

  group('T-INV-SIGN invoice-cancel byte layout', () {
    test('pins the cancel layout: [invoice_id] only, nym slot empty', () {
      expect(bullpayActionInvoiceCancel, 'invoice-cancel');
      final oracle = _oracleMessageBytes(
        action: 'invoice-cancel',
        npubHex: 'npub',
        nymOrEmpty: '',
        payloadFields: const ['inv-1'],
        timestampSecs: timestamp,
      );
      expect(
        buildBullpaySchnorrMessage(
          action: bullpayActionInvoiceCancel,
          npubHex: 'npub',
          nymOrEmpty: '',
          payloadFields: buildInvoiceCancelPayloadFields('inv-1'),
          timestampSecs: timestamp,
        ),
        oracle,
      );
    });
  });

  group('T-INV-SIGN invoice-list byte layout', () {
    test('pins the list layout: [page,pageSize,status], nym ALWAYS empty', () {
      expect(bullpayActionInvoiceList, 'invoice-list');
      final oracle = _oracleMessageBytes(
        action: 'invoice-list',
        npubHex: 'npub',
        nymOrEmpty: '',
        payloadFields: const ['1', '100', ''],
        timestampSecs: timestamp,
      );
      expect(
        buildBullpaySchnorrMessage(
          action: bullpayActionInvoiceList,
          npubHex: 'npub',
          nymOrEmpty: '',
          payloadFields: buildInvoiceListPayloadFields(page: 1, pageSize: 100),
          timestampSecs: timestamp,
        ),
        oracle,
      );
    });

    test('status filter fills the third field', () {
      expect(
        buildInvoiceListPayloadFields(page: 2, pageSize: 50, status: 'paid'),
        const ['2', '50', 'paid'],
      );
    });
  });

  group('T-INV-DTO parse round-trips', () {
    test('status shape parses and ignores unknown keys (tolerant reader)', () {
      final client = BullnymHttpClient.withDio(
        _stubDio([_statusView(status: 'paid')]).dio,
      );
      expect(
        client.getInvoiceStatus(invoiceId: 'inv-1'),
        completion(
          isA<BullnymInvoiceStatus>()
              .having((s) => s.status, 'status', 'paid')
              .having((s) => s.liquidAddress, 'liquidAddress', 'lq1qtest')
              .having((s) => s.acceptLiquid, 'acceptLiquid', true),
        ),
      );
    });

    test('list shape parses pageSize rename, null nym_owner and paid_* '
        'optionals', () async {
      final stub = _stubDio([
        {
          'invoices': [_listItemView(), _listItemView(paid: true)],
          'page': 1,
          'pageSize': 100,
          'has_more': false,
        },
      ]);
      final client = BullnymHttpClient.withDio(stub.dio, nowSecs: () => timestamp);
      final result = await client.listInvoices(
        signer: signer,
        page: 1,
        pageSize: 100,
      );
      expect(result.pageSize, 100);
      expect(result.hasMore, isFalse);
      expect(result.invoices.first.nymOwner, isNull);
      expect(result.invoices.first.paidAtUnix, isNull);
      expect(result.invoices.last.status, 'paid');
      expect(result.invoices.last.paidVia, 'liquid');
    });
  });

  group('T-INV-CLIENT create', () {
    test('POSTs the unlinked body and signs the exact 13-field layout',
        () async {
      final stub = _stubDio([
        {'invoice_id': 'inv-1', 'share_url': 'https://bullpay.ca/invoice/inv-1'},
      ]);
      final client = BullnymHttpClient.withDio(
        stub.dio,
        nowSecs: () => timestamp,
      );

      final response = await client.createInvoice(
        signer: signer,
        fields: _lnLiquidFields(),
      );

      expect(response.invoiceId, 'inv-1');
      expect(response.shareUrl, 'https://bullpay.ca/invoice/inv-1');

      final request = stub.captured.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/api/v1/invoices');
      final body = request.data as Map<String, dynamic>;
      expect(body['npub'], handle.publicKeyHex);
      expect(body['accept_ln'], true);
      expect(body['accept_liquid'], true);
      expect(body['accept_btc'], false);
      expect(body['liquid_address'], 'lq1qtest');
      expect(body['liquid_blinding_key_hex'], 'ab12cd');

      _expectSignatureValid(
        handle: handle,
        signatureHex: body['signature'] as String,
        action: bullpayActionInvoiceCreate,
        nymOrEmpty: '',
        payloadFields: buildInvoiceCreatePayloadFields(_lnLiquidFields()),
        timestampSecs: timestamp,
      );
    });

    test('maps the InvalidAmount envelope to a typed rejection', () {
      final stub = _stubDio([
        {
          'status': 'ERROR',
          'code': 'InvalidAmount',
          'reason': 'amount must be exactly one of sat or fiat',
        },
      ]);
      final client = BullnymHttpClient.withDio(
        stub.dio,
        nowSecs: () => timestamp,
      );
      expect(
        () => client.createInvoice(signer: signer, fields: _lnLiquidFields()),
        throwsA(
          isA<BullnymException>().having((e) => e.code, 'code', 'InvalidAmount'),
        ),
      );
    });
  });

  group('T-INV-CLIENT cancel', () {
    test('DELETEs the id path with npub+ts+sig and signs [id]', () async {
      final stub = _stubDio([
        {'invoice_id': 'inv-1', 'status': 'cancelled'},
      ]);
      final client = BullnymHttpClient.withDio(
        stub.dio,
        nowSecs: () => timestamp,
      );

      final response = await client.cancelInvoice(
        signer: signer,
        invoiceId: 'inv-1',
      );
      expect(response.status, 'cancelled');

      final request = stub.captured.requests.single;
      expect(request.method, 'DELETE');
      expect(request.path, '/api/v1/invoices/inv-1');
      final body = request.data as Map<String, dynamic>;
      expect(body.keys.toSet(), {'npub', 'timestamp', 'signature'});

      _expectSignatureValid(
        handle: handle,
        signatureHex: body['signature'] as String,
        action: bullpayActionInvoiceCancel,
        nymOrEmpty: '',
        payloadFields: buildInvoiceCancelPayloadFields('inv-1'),
        timestampSecs: timestamp,
      );
    });
  });

  group('T-INV-CLIENT list', () {
    test('GETs /api/v1/invoices with signed query and empty-nym signature',
        () async {
      final stub = _stubDio([
        {'invoices': [], 'page': 1, 'pageSize': 100, 'has_more': false},
      ]);
      final client = BullnymHttpClient.withDio(
        stub.dio,
        nowSecs: () => timestamp,
      );

      await client.listInvoices(signer: signer, page: 1, pageSize: 100);

      final request = stub.captured.requests.single;
      expect(request.method, 'GET');
      expect(request.path, '/api/v1/invoices');
      expect(request.queryParameters['npub'], handle.publicKeyHex);
      expect(request.queryParameters['pageSize'], 100);
      expect(request.queryParameters.containsKey('status'), isFalse);

      _expectSignatureValid(
        handle: handle,
        signatureHex: request.queryParameters['signature'] as String,
        action: bullpayActionInvoiceList,
        nymOrEmpty: '',
        payloadFields: buildInvoiceListPayloadFields(page: 1, pageSize: 100),
        timestampSecs: timestamp,
      );
    });
  });

  group('T-INV-CLIENT status is unsigned', () {
    test('GETs /api/v1/invoices/:id/status with no signature', () async {
      final stub = _stubDio([_statusView()]);
      final client = BullnymHttpClient.withDio(stub.dio);

      await client.getInvoiceStatus(invoiceId: 'inv-1');

      final request = stub.captured.requests.single;
      expect(request.method, 'GET');
      expect(request.path, '/api/v1/invoices/inv-1/status');
      expect(request.queryParameters.containsKey('signature'), isFalse);
      expect(request.queryParameters.containsKey('npub'), isFalse);
    });
  });

  group('T-RECOVER-SIGN invoice-recover byte layout', () {
    test('pins the recover layout: [invoice_id, btc_address], nym in nym slot',
        () {
      expect(bullpayActionInvoiceRecover, 'invoice-recover');
      final oracle = _oracleMessageBytes(
        action: 'invoice-recover',
        npubHex: 'npub',
        nymOrEmpty: 'alice',
        payloadFields: const ['inv-1', 'bc1qexample'],
        timestampSecs: timestamp,
      );
      expect(
        buildBullpaySchnorrMessage(
          action: bullpayActionInvoiceRecover,
          npubHex: 'npub',
          // UNLIKE list/recovery-list, recover signs the NON-EMPTY path nym.
          nymOrEmpty: 'alice',
          payloadFields: buildInvoiceRecoverPayloadFields(
            invoiceId: 'inv-1',
            btcAddress: 'bc1qexample',
          ),
          timestampSecs: timestamp,
        ),
        oracle,
      );
    });
  });

  group('T-RECOVER-SIGN invoice-recovery-list byte layout', () {
    test('pins the recovery-list layout: ZERO fields, nym slot EMPTY', () {
      expect(bullpayActionInvoiceRecoveryList, 'invoice-recovery-list');
      // Tripwire: adding a param is a wire-breaking change (mirrors the
      // server's recovery_list_payload_field_order unit test).
      expect(buildInvoiceRecoveryListPayloadFields(), const <String>[]);
      final oracle = _oracleMessageBytes(
        action: 'invoice-recovery-list',
        npubHex: 'npub',
        nymOrEmpty: '',
        payloadFields: const [],
        timestampSecs: timestamp,
      );
      // The empty-nym field still emits its trailing NUL, then the timestamp
      // appends with no trailing NUL:
      // `bullpay-la-v2\0invoice-recovery-list\0<npub>\0\0<timestamp>`.
      expect(
        buildBullpaySchnorrMessage(
          action: bullpayActionInvoiceRecoveryList,
          npubHex: 'npub',
          nymOrEmpty: '',
          payloadFields: buildInvoiceRecoveryListPayloadFields(),
          timestampSecs: timestamp,
        ),
        oracle,
      );
    });
  });

  group('T-RECOVER-DTO recoverable-list parse round-trips', () {
    Map<String, dynamic> recoverableView({
      String recoveryStatus = 'refund_due',
      String? refundAddress,
      String? refundTxid,
      String lockupAddress = 'bc1qlockup',
    }) {
      return {
        'invoice_id': 'inv-1',
        'nym': 'alice',
        'recovery_status': recoveryStatus,
        'user_lock_amount_sat': 105000,
        'server_lock_amount_sat': 100000,
        'lockup_address': lockupAddress,
        'refund_address': refundAddress,
        'refund_txid': refundTxid,
        'swap_created_at_unix': 1767000000,
        'swap_updated_at_unix': 1767003600,
        'invoice': {
          'status': 'expired',
          'amount_sat': 100000,
          'fiat_amount_minor': 5000,
          'fiat_currency': 'CAD',
          'public_description': 'Order 123',
          'invoice_number': 'INV-42',
          'created_at_unix': 1766990000,
          'unknown_nested_key': 'ignored',
        },
        'unknown_top_key': true,
      };
    }

    test('flattens invoice context, one row per swap, tolerant of unknown keys',
        () async {
      final stub = _stubDio([
        {
          'recovery_enabled': true,
          'count': 2,
          'has_more': false,
          'items': [
            recoverableView(lockupAddress: 'bc1qlockA'),
            recoverableView(
              recoveryStatus: 'refunded',
              refundAddress: 'bc1qdest',
              refundTxid: 'tx-1',
              lockupAddress: 'bc1qlockB',
            ),
          ],
        },
      ]);
      final client = BullnymHttpClient.withDio(stub.dio, nowSecs: () => timestamp);
      final result = await client.listRecoverableChainSwaps(signer: signer);

      expect(result.recoveryEnabled, isTrue);
      expect(result.count, 2);
      expect(result.hasMore, isFalse);
      expect(result.items, hasLength(2));
      final first = result.items.first;
      expect(first.invoiceId, 'inv-1');
      expect(first.nym, 'alice');
      expect(first.recoveryStatus, 'refund_due');
      expect(first.userLockAmountSat, 105000);
      expect(first.serverLockAmountSat, 100000);
      expect(first.lockupAddress, 'bc1qlockA');
      expect(first.refundAddress, isNull);
      expect(first.refundTxid, isNull);
      expect(first.invoiceStatus, 'expired');
      expect(first.invoiceAmountSat, 100000);
      expect(first.fiatCurrency, 'CAD');
      expect(first.publicDescription, 'Order 123');
      final second = result.items.last;
      expect(second.recoveryStatus, 'refunded');
      expect(second.refundAddress, 'bc1qdest');
      expect(second.refundTxid, 'tx-1');
      expect(second.lockupAddress, 'bc1qlockB');
    });

    test('empty recoverable set parses to zero items', () async {
      final stub = _stubDio([
        {'recovery_enabled': false, 'count': 0, 'has_more': false, 'items': []},
      ]);
      final client = BullnymHttpClient.withDio(stub.dio, nowSecs: () => timestamp);
      final result = await client.listRecoverableChainSwaps(signer: signer);
      expect(result.recoveryEnabled, isFalse);
      expect(result.items, isEmpty);
      expect(result.count, 0);
    });
  });

  group('T-RECOVER-CLIENT recover', () {
    test('POSTs the per-nym recover path, signs [invoice_id, btc_address]',
        () async {
      final stub = _stubDio([
        {'status': 'recovered', 'txid': 'txid-abc'},
      ]);
      final client = BullnymHttpClient.withDio(stub.dio, nowSecs: () => timestamp);

      final response = await client.recoverChainSwap(
        signer: signer,
        nym: 'alice',
        invoiceId: 'inv-1',
        btcAddress: 'bc1qexample',
      );
      expect(response.status, 'recovered');
      expect(response.txid, 'txid-abc');

      final request = stub.captured.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/api/v1/alice/invoices/inv-1/recover');
      final body = request.data as Map<String, dynamic>;
      expect(body.keys.toSet(), {
        'npub',
        'timestamp',
        'signature',
        'btc_address',
      });
      expect(body['btc_address'], 'bc1qexample');

      _expectSignatureValid(
        handle: handle,
        signatureHex: body['signature'] as String,
        action: bullpayActionInvoiceRecover,
        nymOrEmpty: 'alice',
        payloadFields: buildInvoiceRecoverPayloadFields(
          invoiceId: 'inv-1',
          btcAddress: 'bc1qexample',
        ),
        timestampSecs: timestamp,
      );
    });

    test('maps the RecoveryInProgress envelope to a typed rejection', () {
      final stub = _stubDio([
        {
          'status': 'ERROR',
          'code': 'RecoveryInProgress',
          'reason': 'recovery already in flight for invoice inv-1',
        },
      ]);
      final client = BullnymHttpClient.withDio(stub.dio, nowSecs: () => timestamp);
      expect(
        () => client.recoverChainSwap(
          signer: signer,
          nym: 'alice',
          invoiceId: 'inv-1',
          btcAddress: 'bc1qexample',
        ),
        throwsA(
          isA<BullnymException>()
              .having((e) => e.code, 'code', 'RecoveryInProgress'),
        ),
      );
    });
  });

  group('T-RECOVER-CLIENT recoverable list', () {
    test('GETs /api/v1/invoices/recoverable with npub+ts+sig, no page params',
        () async {
      final stub = _stubDio([
        {'recovery_enabled': true, 'count': 0, 'has_more': false, 'items': []},
      ]);
      final client = BullnymHttpClient.withDio(stub.dio, nowSecs: () => timestamp);

      await client.listRecoverableChainSwaps(signer: signer);

      final request = stub.captured.requests.single;
      expect(request.method, 'GET');
      expect(request.path, '/api/v1/invoices/recoverable');
      final query = request.queryParameters;
      expect(query.keys.toSet(), {'npub', 'timestamp', 'signature'});
      expect(query.containsKey('page'), isFalse);

      _expectSignatureValid(
        handle: handle,
        signatureHex: query['signature'] as String,
        action: bullpayActionInvoiceRecoveryList,
        nymOrEmpty: '',
        payloadFields: buildInvoiceRecoveryListPayloadFields(),
        timestampSecs: timestamp,
      );
    });
  });
}

NostrKeychainHandle _bullnymAuthHandle() {
  return NostrKeychainHandle.deriveFromBip85Path(
    xprvBase58: _zeroMnemonicXprv(),
    hardenedPath: "9000'/2'/1'",
  );
}

BullnymAuthSigner _signerFromHandle(NostrKeychainHandle handle) {
  return BullnymAuthSigner(
    npubHex: handle.publicKeyHex,
    signHashHex: handle.signHashHex,
  );
}

String _zeroMnemonicXprv() {
  final mnemonic = bip39.Mnemonic.fromSentence(
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    bip39.Language.english,
  );
  return bip32.Bip32Keys.fromSeed(Uint8List.fromList(mnemonic.seed)).toBase58();
}

void _expectSignatureValid({
  required NostrKeychainHandle handle,
  required String signatureHex,
  required String action,
  required String nymOrEmpty,
  required List<String> payloadFields,
  required int timestampSecs,
}) {
  final message = _oracleMessageBytes(
    action: action,
    npubHex: handle.publicKeyHex,
    nymOrEmpty: nymOrEmpty,
    payloadFields: payloadFields,
    timestampSecs: timestampSecs,
  );
  final digest = sha256.convert(message).bytes;
  final publicKey = ECPublic.fromHex('02${handle.publicKeyHex}');
  expect(
    publicKey.verifyBip340Signature(
      digest: digest,
      signature: hex.decode(signatureHex),
      tweak: false,
    ),
    isTrue,
  );
}
