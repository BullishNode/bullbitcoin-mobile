import 'dart:convert';

import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/bullnym/data/bullnym_http_client.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_lightning_address_usecase.dart';
import 'package:bb_mobile/features/nostr_identity/domain/derive_nostr_identity_handle_usecase.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockHttpAdapter extends Mock implements HttpClientAdapter {}

const _masterXprv =
    'xprv9s21ZrQH143K2LBWUUQRFXhucrQqBpKdRRxNVq2zBqsx8HVqFk2uYo8kmbaLLHRdqtQpUm98uKfu3vca1LqdGhUtyoFnCNkfmXRyPXLjbKb';
const _timestamp = 1784044800;

void main() {
  setUpAll(() => registerFallbackValue(RequestOptions(path: '')));

  test(
    'current client emits the canonical signed registration contract',
    () async {
      final authNpubHex = NostrKeychainHandle.deriveFromBip85Path(
        xprvBase58: _masterXprv,
        hardenedPath: "128002'/101'/1'",
      ).publicKeyHex;
      final verificationNpubHex = NostrKeychainHandle.deriveFromBip85Path(
        xprvBase58: _masterXprv,
        hardenedPath: "128002'/102'/1'",
      ).publicKeyHex;
      final requests = <RequestOptions>[];
      final adapter = _MockHttpAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://bullpay.test'))
        ..httpClientAdapter = adapter;
      when(() => adapter.fetch(any(), any(), any())).thenAnswer((
        invocation,
      ) async {
        requests.add(invocation.positionalArguments.first as RequestOptions);
        return ResponseBody.fromString(
          jsonEncode({
            'nym': 'merchant',
            'lightning_address': 'merchant@pay2.bull-wallet.com',
          }),
          200,
          headers: {
            'content-type': ['application/json'],
          },
        );
      });
      const nostrIdentity = NostrIdentityFacade(
        DeriveNostrIdentityHandleUsecase(Bip85RegistryFacade()),
      );
      final bullnym = BullnymFacade(
        client: BullnymHttpClient.withDio(dio),
        nowSecs: () => _timestamp,
      );

      final registration =
          await RegisterLightningAddressUsecase(bullnym, nostrIdentity).execute(
            xprvBase58: _masterXprv,
            nym: 'merchant',
            ctDescriptor: 'ct(test-descriptor)',
          );

      expect(registration.nym, 'merchant');
      expect(registration.lightningAddress, 'merchant@pay2.bull-wallet.com');
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/register');
      final data = request.data as Map<String, dynamic>;
      expect(data, {
        'nym': 'merchant',
        'ct_descriptor': 'ct(test-descriptor)',
        'verification_npub': verificationNpubHex,
        'npub': authNpubHex,
        'signature': isA<String>().having(
          (value) => value.length,
          'length',
          128,
        ),
        'timestamp': _timestamp,
      });
      expect(jsonEncode(data), isNot(contains('xprv')));

      final digest = sha256
          .convert(_registrationMessage(authNpubHex, verificationNpubHex))
          .bytes;
      final signatureHex = data['signature'] as String;
      expect(
        ECPublic.fromHex('02$authNpubHex').verifyBip340Signature(
          digest: digest,
          signature: hex.decode(signatureHex),
          tweak: false,
        ),
        isTrue,
      );
    },
  );
}

List<int> _registrationMessage(String authNpubHex, String verificationNpubHex) {
  final bytes = <int>[];
  for (final field in [
    'bullpay-la-v2',
    'register',
    authNpubHex,
    'merchant',
    'ct(test-descriptor)',
    verificationNpubHex,
  ]) {
    bytes
      ..addAll(utf8.encode(field))
      ..add(0);
  }
  return bytes..addAll(utf8.encode(_timestamp.toString()));
}
