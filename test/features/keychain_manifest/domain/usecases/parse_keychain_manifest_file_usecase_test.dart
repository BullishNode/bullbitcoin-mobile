import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_file_model.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/parse_keychain_manifest_file_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const usecase = ParseKeychainManifestFileUsecase();
  const codec = KeychainManifestFileCodec();

  test('validates registered reservation metadata', () {
    final plan = usecase.execute(codec.decode(_manifestPayload));

    expect(plan.parentFingerprint, 'fedcba98');
    expect(plan.entries.single.reservationId, 'btcpay_wallet_seed');
    expect(plan.entries.single.bip85DerivationPath, "39'/0'/12'/100'");
    expect(plan.walletMaterializations, hasLength(2));
  });

  test('rejects unknown reservations', () {
    final payload = _manifestPayload.replaceFirst(
      'btcpay_wallet_seed',
      'unknown_wallet_seed',
    );

    expect(
      () => usecase.execute(codec.decode(payload)),
      throwsA(
        isA<KeychainManifestFileParseException>().having(
          (error) => error.reason,
          'reason',
          KeychainManifestFileParseFailureReason.unknownReservation,
        ),
      ),
    );
  });

  test('rejects reservation path mismatches', () {
    final payload = _manifestPayload.replaceFirst(
      "39'/0'/12'/100'",
      "39'/0'/12'/77'",
    );

    expect(
      () => usecase.execute(codec.decode(payload)),
      throwsA(
        isA<KeychainManifestFileParseException>().having(
          (error) => error.reason,
          'reason',
          KeychainManifestFileParseFailureReason.invalidMetadata,
        ),
      ),
    );
  });

  test('rejects reservation metadata mismatches', () {
    final payload = _manifestPayload.replaceFirst(
      '"bip85Index":100',
      '"bip85Index":101',
    );

    expect(
      () => usecase.execute(codec.decode(payload)),
      throwsA(
        isA<KeychainManifestFileParseException>().having(
          (error) => error.reason,
          'reason',
          KeychainManifestFileParseFailureReason.invalidMetadata,
        ),
      ),
    );
  });

  test('rejects non-wallet reservations in wallet manifest files', () {
    final payload = _manifestPayload
        .replaceFirst('btcpay_wallet_seed', 'nostr_wallet_manifest_key')
        .replaceFirst('walletSeed', 'nonWalletNostrKey')
        .replaceFirst('btcpay', 'nostr')
        .replaceFirst('39,"bip85Index":100', '9000,"bip85Index":1')
        .replaceFirst("39'/0'/12'/100'", "9000'/1'/1'")
        .replaceFirst("39'/0'/12'/100'", "9000'/1'/1'");

    expect(
      () => usecase.execute(codec.decode(payload)),
      throwsA(
        isA<KeychainManifestFileParseException>().having(
          (error) => error.reason,
          'reason',
          KeychainManifestFileParseFailureReason.invalidMetadata,
        ),
      ),
    );
  });

  test('parses Lightning Address wallet manifests after activation', () {
    final payload = _manifestPayloadForReservation(
      reservationId: 'lightning_address_wallet_seed',
      path: "39'/0'/12'/101'",
      ownerFeature: 'lightningAddress',
      bip85Application: 39,
      bip85Index: 101,
      materializations: _lightningAddressMaterialization,
    );

    final manifestFile = const KeychainManifestFileCodec().decode(payload);
    final plan = usecase.execute(manifestFile);

    expect(plan.entries.single.reservationId, 'lightning_address_wallet_seed');
    expect(plan.entries.single.ownerFeature, 'lightningAddress');
    expect(plan.entries.single.bip85DerivationPath, "39'/0'/12'/101'");
    expect(plan.entries.single.bip85Index, 101);
  });

  test('rejects Lightning Address manifests with Bitcoin wallets', () {
    final payload = _manifestPayloadForReservation(
      reservationId: 'lightning_address_wallet_seed',
      path: "39'/0'/12'/101'",
      ownerFeature: 'lightningAddress',
      bip85Application: 39,
      bip85Index: 101,
      materializations: _lightningAddressMaterialization.replaceFirst(
        'liquidMainnet',
        'bitcoinMainnet',
      ),
    );

    expect(
      () => usecase.execute(const KeychainManifestFileCodec().decode(payload)),
      throwsA(isA<KeychainManifestFileParseException>()),
    );
  });

  test('rejects Lightning Address manifests with the wrong purpose', () {
    final payload = _manifestPayloadForReservation(
      reservationId: 'lightning_address_wallet_seed',
      path: "39'/0'/12'/101'",
      ownerFeature: 'lightningAddress',
      bip85Application: 39,
      bip85Index: 101,
      materializations: _lightningAddressMaterialization.replaceFirst(
        'liquid',
        'bitcoin',
      ),
    );

    expect(
      () => usecase.execute(const KeychainManifestFileCodec().decode(payload)),
      throwsA(isA<KeychainManifestFileParseException>()),
    );
  });

  test('rejects Lightning Address manifests with the wrong script type', () {
    final payload = _manifestPayloadForReservation(
      reservationId: 'lightning_address_wallet_seed',
      path: "39'/0'/12'/101'",
      ownerFeature: 'lightningAddress',
      bip85Application: 39,
      bip85Index: 101,
      materializations: _lightningAddressMaterialization.replaceFirst(
        'bip84',
        'bip49',
      ),
    );

    expect(
      () => usecase.execute(const KeychainManifestFileCodec().decode(payload)),
      throwsA(isA<KeychainManifestFileParseException>()),
    );
  });

  test('rejects Lightning Address manifests with multiple wallets', () {
    final payload = _manifestPayloadForReservation(
      reservationId: 'lightning_address_wallet_seed',
      path: "39'/0'/12'/101'",
      ownerFeature: 'lightningAddress',
      bip85Application: 39,
      bip85Index: 101,
      materializations:
          '$_lightningAddressMaterialization,$_lightningAddressMaterialization',
    );

    expect(
      () => usecase.execute(codec.decode(payload)),
      throwsA(isA<KeychainManifestFileParseException>()),
    );
  });

  test('rejects Payment Page wallet manifests until activation', () {
    final payload = _manifestPayloadForReservation(
      reservationId: 'payment_page_wallet_seed',
      path: "39'/0'/12'/102'",
      ownerFeature: 'paymentPage',
      bip85Application: 39,
      bip85Index: 102,
      materializations: _lightningAddressMaterialization,
    );

    expect(
      () => usecase.execute(codec.decode(payload)),
      throwsA(isA<KeychainManifestFileParseException>()),
    );
  });

  test('rejects duplicate wallet materializations in the same entry', () {
    final duplicate =
        '{"type":"wallet","walletId":"btc-wallet",'
        '"childSeedFingerprint":"0123abcd","network":"bitcoinMainnet",'
        '"walletPurpose":"bitcoin","scriptType":"bip84",'
        '"createdAt":10,"updatedAt":10},';
    final payload = _manifestPayload.replaceFirst(
      '"materializations":[',
      '"materializations":[$duplicate',
    );

    expect(
      () => usecase.execute(codec.decode(payload)),
      throwsA(
        isA<KeychainManifestFileParseException>().having(
          (error) => error.reason,
          'reason',
          KeychainManifestFileParseFailureReason.duplicateWalletMaterialization,
        ),
      ),
    );
  });

  test('rejects duplicate entry ids', () {
    final duplicateEntry =
        '{"entryId":"fedcba98:39\'/0\'/12\'/100\'",'
        '"bip85DerivationPath":"39\'/0\'/12\'/100\'",'
        '"reservationId":"btcpay_wallet_seed","entryType":"walletSeed",'
        '"ownerFeature":"btcpay","bip85Application":39,"bip85Index":100,'
        '"createdAt":10,"updatedAt":12,"materializations":[{"type":"wallet",'
        '"walletId":"duplicate-wallet","childSeedFingerprint":"0123abcd",'
        '"network":"bitcoinMainnet","walletPurpose":"bitcoin",'
        '"scriptType":"bip84","createdAt":10,"updatedAt":10}]}';
    final payload = _manifestPayload.replaceFirst(
      ']}]}',
      ']},$duplicateEntry]}',
    );

    expect(
      () => usecase.execute(codec.decode(payload)),
      throwsA(
        isA<KeychainManifestFileParseException>().having(
          (error) => error.reason,
          'reason',
          KeychainManifestFileParseFailureReason.duplicateEntry,
        ),
      ),
    );
  });

  test('rejects stale inventory timestamps', () {
    final payload = _manifestPayload.replaceFirst(
      '"inventoryUpdatedAt":12',
      '"inventoryUpdatedAt":10',
    );

    expect(
      () => codec.decode(payload),
      throwsA(
        isA<KeychainManifestFileParseException>().having(
          (error) => error.reason,
          'reason',
          KeychainManifestFileParseFailureReason.invalidMetadata,
        ),
      ),
    );
  });
}

const _manifestPayload =
    '{"version":1,"parentFingerprint":"fedcba98","generatedAt":20,'
    '"inventoryUpdatedAt":12,"entries":[{"entryId":"fedcba98:39\'/0\'/12\'/100\'",'
    '"bip85DerivationPath":"39\'/0\'/12\'/100\'",'
    '"reservationId":"btcpay_wallet_seed","entryType":"walletSeed",'
    '"ownerFeature":"btcpay","bip85Application":39,"bip85Index":100,'
    '"createdAt":10,"updatedAt":12,"materializations":[{"type":"wallet",'
    '"walletId":"btc-wallet","childSeedFingerprint":"0123abcd",'
    '"network":"bitcoinMainnet","walletPurpose":"bitcoin",'
    '"scriptType":"bip84","createdAt":10,"updatedAt":10},{"type":"wallet",'
    '"walletId":"lbtc-wallet","childSeedFingerprint":"0123abcd",'
    '"network":"liquidMainnet","walletPurpose":"liquid",'
    '"scriptType":"bip84","createdAt":11,"updatedAt":11}]}]}';

const _lightningAddressMaterialization =
    '{"type":"wallet","walletId":"lightning-address-wallet",'
    '"childSeedFingerprint":"0123abcd","network":"liquidMainnet",'
    '"walletPurpose":"liquid","scriptType":"bip84",'
    '"createdAt":10,"updatedAt":10}';

String _manifestPayloadForReservation({
  required String reservationId,
  required String path,
  required String ownerFeature,
  required int bip85Application,
  required int bip85Index,
  String? materializations,
}) {
  final payload = _manifestPayload
      .replaceFirst("fedcba98:39'/0'/12'/100'", 'fedcba98:$path')
      .replaceFirst("39'/0'/12'/100'", path)
      .replaceFirst('btcpay_wallet_seed', reservationId)
      .replaceFirst('btcpay', ownerFeature)
      .replaceFirst(
        '"bip85Application":39',
        '"bip85Application":$bip85Application',
      )
      .replaceFirst('"bip85Index":100', '"bip85Index":$bip85Index');
  if (materializations == null) return payload;
  return payload.replaceFirst(
    RegExp(r'"materializations":\[[^\]]+\]'),
    '"materializations":[$materializations]',
  );
}
