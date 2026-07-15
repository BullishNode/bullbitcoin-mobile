import 'dart:convert';

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bullnym/data/bullnym_http_client.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_lnurl_comment_actions.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockHttpAdapter extends Mock implements HttpClientAdapter {}

class _Stub {
  final Dio dio;
  final List<RequestOptions> requests;

  const _Stub(this.dio, this.requests);
}

_Stub _stub(Object? response) {
  final requests = <RequestOptions>[];
  final adapter = _MockHttpAdapter();
  final dio = Dio(BaseOptions(baseUrl: 'https://bullpay.test'))
    ..httpClientAdapter = adapter;
  when(() => adapter.fetch(any(), any(), any())).thenAnswer((invocation) async {
    requests.add(invocation.positionalArguments.first as RequestOptions);
    return ResponseBody.fromString(
      jsonEncode(response),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  });
  return _Stub(dio, requests);
}

Map<String, dynamic> _row({
  String intentId = '4de539d7-b0f2-4d4a-a308-d0f31dc111b5',
  String comment = 'Coffee for Ana ☕',
  int amountMsat = 42000,
  int receivedAtUnix = 1784041200,
}) {
  return {
    'intent_id': intentId,
    'nym': 'merchant',
    'amount_msat': amountMsat,
    'comment': comment,
    'received_at_unix': receivedAtUnix,
  };
}

Map<String, dynamic> _page(List<Map<String, dynamic>> rows) {
  return {'comments': rows, 'page': 1, 'pageSize': 20, 'has_more': false};
}

void main() {
  const timestamp = 1784041300;
  final npub = '11' * 32;

  setUpAll(() => registerFallbackValue(RequestOptions(path: '')));

  test('pins the deployed action and signed pagination field order', () {
    expect(bullpayActionLnurlCommentHistory, 'lnurl-comment-history');
    expect(buildLnurlCommentHistoryPayloadFields(page: 2, pageSize: 50), [
      '2',
      '50',
    ]);
  });

  test(
    'GETs the private route, signs an empty nym, and preserves Unicode',
    () async {
      final stub = _stub(_page([_row()]));
      String? signedHash;
      final signer = BullnymAuthSigner(
        npubHex: npub,
        signHashHex: (hash) {
          signedHash = hash;
          return 'aa' * 64;
        },
      );
      final client = BullnymHttpClient.withDio(
        stub.dio,
        nowSecs: () => timestamp,
      );

      final result = await client.listLnurlCommentHistory(
        signer: signer,
        page: 1,
        pageSize: 20,
      );

      final history = _unwrap(result);
      expect(history.comments.single.comment, 'Coffee for Ana ☕');
      expect(history.comments.single.amountMsat, 42000);
      final request = stub.requests.single;
      expect(request.method, 'GET');
      expect(request.path, '/api/v1/lnurl/comments');
      expect(request.queryParameters, {
        'npub': npub,
        'timestamp': timestamp,
        'signature': 'aa' * 64,
        'page': 1,
        'pageSize': 20,
      });

      final message = _oracleMessage(
        action: 'lnurl-comment-history',
        npub: npub,
        fields: const ['1', '20'],
        timestamp: timestamp,
      );
      expect(signedHash, hex.encode(sha256.convert(message).bytes));
    },
  );

  test(
    'rejects pagination outside the signed server contract before I/O',
    () async {
      final stub = _stub(_page([]));
      final failure = _unwrapFailure(
        await BullnymHttpClient.withDio(stub.dio).listLnurlCommentHistory(
          signer: BullnymAuthSigner(
            npubHex: npub,
            signHashHex: (_) => 'aa' * 64,
          ),
          page: 0,
          pageSize: 101,
        ),
      );

      expect(failure.kind, BullnymFailureKind.invalidInput);
      expect(stub.requests, isEmpty);
    },
  );

  test(
    'fails closed on oversized, duplicated, or reordered private rows',
    () async {
      final oversizedGraphemes = _page([_row(comment: 'é' * 121)]);
      final oversizedBytes = _page([_row(comment: '👨‍👩‍👧‍👦' * 120)]);
      final duplicate = _page([_row(), _row(receivedAtUnix: 1784041100)]);
      final reordered = _page([
        _row(receivedAtUnix: 1784041100),
        _row(
          intentId: '5de539d7-b0f2-4d4a-a308-d0f31dc111b6',
          receivedAtUnix: 1784041200,
        ),
      ]);

      for (final response in [
        oversizedGraphemes,
        oversizedBytes,
        duplicate,
        reordered,
      ]) {
        final failure = _unwrapFailure(
          await BullnymHttpClient.withDio(
            _stub(response).dio,
          ).listLnurlCommentHistory(
            signer: BullnymAuthSigner(
              npubHex: npub,
              signHashHex: (_) => 'aa' * 64,
            ),
            page: 1,
            pageSize: 20,
          ),
        );
        expect(failure.kind, BullnymFailureKind.invalidServerResponse);
      }
    },
  );

  test(
    'fails closed when response pagination does not match signed request',
    () async {
      final response = _page([])..['page'] = 2;
      final failure = _unwrapFailure(
        await BullnymHttpClient.withDio(
          _stub(response).dio,
        ).listLnurlCommentHistory(
          signer: BullnymAuthSigner(
            npubHex: npub,
            signHashHex: (_) => 'aa' * 64,
          ),
          page: 1,
          pageSize: 20,
        ),
      );
      expect(failure.kind, BullnymFailureKind.invalidServerResponse);
    },
  );
}

List<int> _oracleMessage({
  required String action,
  required String npub,
  required List<String> fields,
  required int timestamp,
}) {
  final bytes = <int>[];
  for (final field in ['bullpay-la-v2', action, npub, '', ...fields]) {
    bytes
      ..addAll(utf8.encode(field))
      ..add(0);
  }
  return bytes..addAll(utf8.encode(timestamp.toString()));
}

T _unwrap<T>(Result<T, BullnymFailure> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final failure) => throw StateError(
    'Unexpected failure: ${failure.kind}',
  ),
};

BullnymFailure _unwrapFailure<T>(Result<T, BullnymFailure> result) =>
    switch (result) {
      Err(:final failure) => failure,
      Ok() => throw StateError('Expected failure'),
    };
