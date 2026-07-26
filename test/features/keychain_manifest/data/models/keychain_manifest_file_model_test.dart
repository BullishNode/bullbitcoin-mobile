import 'dart:convert';

import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_file_model.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_file.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = KeychainManifestFileCodec();

  Matcher throwsParseFailure(KeychainManifestFileParseFailureReason reason) {
    return throwsA(
      isA<KeychainManifestFileParseException>().having(
        (error) => error.reason,
        'reason',
        reason,
      ),
    );
  }

  group('round trip', () {
    test('encode(decode(payload)) reproduces the payload byte-exact', () {
      expect(codec.encode(codec.decode(_manifestPayload)), _manifestPayload);
    });

    test('empty payloads round-trip byte-exact', () {
      expect(
        codec.encode(codec.decode(_emptyManifestPayload)),
        _emptyManifestPayload,
      );
    });

    test('Nostr key descriptions round-trip byte-exact', () {
      expect(
        codec.encode(codec.decode(_describedNostrManifestPayload)),
        _describedNostrManifestPayload,
      );
      final materialization =
          codec
                  .decode(_describedNostrManifestPayload)
                  .entries
                  .single
                  .materializations
                  .single
              as KeychainManifestFileNostrKeyMaterialization;
      expect(materialization.description, 'Long-form notes and replies');
    });

    test('a payload written before descriptions existed parses to null', () {
      final manifestFile = codec.decode(_legacyNostrManifestPayload);
      final materialization =
          manifestFile.entries.single.materializations.single
              as KeychainManifestFileNostrKeyMaterialization;

      expect(materialization.purpose, 'Personal identity');
      expect(materialization.description, isNull);
    });

    test('an absent description re-encodes without the key', () {
      // The wallet-backup envelope rejects a manifest section that is not
      // byte-identical to its canonical encoding, so a backup written before
      // the field existed must not gain a "description":null on re-encode.
      expect(
        codec.encode(codec.decode(_legacyNostrManifestPayload)),
        _legacyNostrManifestPayload,
      );
    });

    test('an explicit null description parses as absent', () {
      final payload = _legacyNostrManifestPayload.replaceFirst(
        '"purpose":"Personal identity"',
        '"purpose":"Personal identity","description":null',
      );

      final materialization =
          codec.decode(payload).entries.single.materializations.single
              as KeychainManifestFileNostrKeyMaterialization;

      expect(materialization.description, isNull);
    });

    test('encode restores canonical entry and materialization order', () {
      final json = jsonDecode(_manifestPayload) as Map<String, Object?>;
      final entries = (json['entries']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final first = Map<String, Object?>.from(entries.single);
      final firstMaterializations =
          (first['materializations']! as List<Object?>)
              .cast<Map<String, Object?>>();
      first['materializations'] = firstMaterializations.reversed.toList();

      final second = Map<String, Object?>.from(first)
        ..['entryId'] = "fedcba98:39'/0'/12'/101'"
        ..['bip85DerivationPath'] = "39'/0'/12'/101'"
        ..['bip85Index'] = 101
        ..['materializations'] = [
          Map<String, Object?>.from(firstMaterializations.first)
            ..['walletId'] = 'btc-wallet-2',
        ];
      json
        ..['entryCount'] = 2
        ..['materializationCount'] = 3
        ..['entries'] = [second, first];

      final canonicalized = codec.encode(codec.decode(jsonEncode(json)));
      final canonicalJson = jsonDecode(canonicalized) as Map<String, Object?>;
      final canonicalEntries = (canonicalJson['entries']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final canonicalMaterializations =
          (canonicalEntries.first['materializations']! as List<Object?>)
              .cast<Map<String, Object?>>();

      expect(canonicalEntries.map((entry) => entry['bip85DerivationPath']), [
        "39'/0'/12'/100'",
        "39'/0'/12'/101'",
      ]);
      expect(
        canonicalMaterializations.map(
          (materialization) => materialization['network'],
        ),
        ['bitcoinMainnet', 'liquidMainnet'],
      );
    });
  });

  group('malformed payloads', () {
    test('rejects non-JSON payloads', () {
      expect(
        () => codec.decode('not a manifest'),
        throwsParseFailure(
          KeychainManifestFileParseFailureReason.malformedFile,
        ),
      );
    });

    test('rejects a top-level array', () {
      expect(
        () => codec.decode('[]'),
        throwsParseFailure(
          KeychainManifestFileParseFailureReason.malformedFile,
        ),
      );
    });

    test('rejects a top-level scalar', () {
      expect(
        () => codec.decode('1'),
        throwsParseFailure(
          KeychainManifestFileParseFailureReason.malformedFile,
        ),
      );
    });

    test('rejects a missing required field', () {
      final payload = _manifestPayload.replaceFirst('"generatedAt":20,', '');

      expect(
        () => codec.decode(payload),
        throwsParseFailure(
          KeychainManifestFileParseFailureReason.malformedFile,
        ),
      );
    });

    test('rejects a string where an integer is required', () {
      final payload = _manifestPayload.replaceFirst(
        '"generatedAt":20',
        '"generatedAt":"20"',
      );

      expect(
        () => codec.decode(payload),
        throwsParseFailure(
          KeychainManifestFileParseFailureReason.malformedFile,
        ),
      );
    });

    test('rejects a fractional number where an integer is required', () {
      final payload = _manifestPayload.replaceFirst(
        '"generatedAt":20',
        '"generatedAt":20.5',
      );

      expect(
        () => codec.decode(payload),
        throwsParseFailure(
          KeychainManifestFileParseFailureReason.malformedFile,
        ),
      );
    });

    test('rejects null for a required field', () {
      final payload = _manifestPayload.replaceFirst(
        '"parentFingerprint":"fedcba98"',
        '"parentFingerprint":null',
      );

      expect(
        () => codec.decode(payload),
        throwsParseFailure(
          KeychainManifestFileParseFailureReason.malformedFile,
        ),
      );
    });
  });

  group('inconsistent payloads', () {
    test('rejects negative timestamps', () {
      final payload = _manifestPayload.replaceFirst(
        '"generatedAt":20',
        '"generatedAt":-1',
      );

      expect(
        () => codec.decode(payload),
        throwsParseFailure(
          KeychainManifestFileParseFailureReason.invalidMetadata,
        ),
      );
    });

    test('rejects an entry id that mismatches the parent fingerprint', () {
      final payload = _manifestPayload.replaceFirst(
        '"entryId":"fedcba98:',
        '"entryId":"0123abcd:',
      );

      expect(
        () => codec.decode(payload),
        throwsParseFailure(
          KeychainManifestFileParseFailureReason.invalidMetadata,
        ),
      );
    });

    test('rejects a duplicate wallet id across entries', () {
      // Two self-consistent entries whose materializations claim the same
      // wallet id; local record uniqueness makes this file impossible.
      final secondEntry =
          '{"entryId":"fedcba98:39\'/0\'/12\'/101\'",'
          '"bip85DerivationPath":"39\'/0\'/12\'/101\'",'
          '"reservationId":"btcpay_wallet_seed","entryType":"walletSeed",'
          '"ownerFeature":"btcpay","bip85Application":39,"bip85Index":101,'
          '"createdAt":10,"updatedAt":10,"materializations":[{"type":"wallet",'
          '"walletId":"btc-wallet","childSeedFingerprint":"0123abcd",'
          '"network":"bitcoinMainnet","scriptType":"bip84",'
          '"createdAt":10,"updatedAt":10}]}';
      final payload = _manifestPayload
          .replaceFirst(']}]}', ']},$secondEntry]}')
          .replaceFirst('"entryCount":1', '"entryCount":2')
          .replaceFirst('"materializationCount":2', '"materializationCount":3');

      expect(
        () => codec.decode(payload),
        throwsParseFailure(
          KeychainManifestFileParseFailureReason.invalidMetadata,
        ),
      );
    });
  });

  group('forward compatibility', () {
    // Unknown fields are tolerated on read by design: a v1 reader accepts
    // payloads carrying additional fields from a newer writer and validates
    // only the specified v1 fields.
    test('tolerates unknown top-level fields', () {
      final payload = _manifestPayload.replaceFirst(
        '{"version":1,',
        '{"version":1,"futureField":true,',
      );

      expect(codec.decode(payload).entries, hasLength(1));
    });

    test('tolerates unknown entry and materialization fields', () {
      final payload = _manifestPayload
          .replaceFirst(
            '"bip85DerivationPath"',
            '"futureEntryField":"x","bip85DerivationPath"',
          )
          .replaceFirst(
            '"walletId":"btc-wallet"',
            '"futureMaterializationField":7,"walletId":"btc-wallet"',
          );

      final manifestFile = codec.decode(payload);

      expect(manifestFile.entries.single.materializations, hasLength(2));
    });
  });
}

/// A v1 manifest holding one user Nostr key, as written before the optional
/// description field existed.
final _legacyNostrManifestPayload =
    '{"version":1,"parentFingerprint":"fedcba98","generatedAt":20,'
    '"inventoryUpdatedAt":12,"entryCount":1,"materializationCount":1,'
    '"entries":[{"entryId":"fedcba98:128002\'/1\'/1\'",'
    '"bip85DerivationPath":"128002\'/1\'/1\'",'
    '"reservationId":"nostr_user_key","entryType":"userGenerated",'
    '"ownerFeature":"nostr","bip85Application":128002,"bip85Index":1,'
    '"createdAt":10,"updatedAt":12,"materializations":[{"type":"nostrKey",'
    '"publicKeyHex":"${'ab' * 32}","keyKind":"userGenerated",'
    '"purpose":"Personal identity","createdAt":10,"updatedAt":12}]}]}';

/// The same manifest with a description present.
final _describedNostrManifestPayload =
    '{"version":1,"parentFingerprint":"fedcba98","generatedAt":20,'
    '"inventoryUpdatedAt":12,"entryCount":1,"materializationCount":1,'
    '"entries":[{"entryId":"fedcba98:128002\'/1\'/1\'",'
    '"bip85DerivationPath":"128002\'/1\'/1\'",'
    '"reservationId":"nostr_user_key","entryType":"userGenerated",'
    '"ownerFeature":"nostr","bip85Application":128002,"bip85Index":1,'
    '"createdAt":10,"updatedAt":12,"materializations":[{"type":"nostrKey",'
    '"publicKeyHex":"${'ab' * 32}","keyKind":"userGenerated",'
    '"purpose":"Personal identity",'
    '"description":"Long-form notes and replies",'
    '"createdAt":10,"updatedAt":12}]}]}';

const _emptyManifestPayload =
    '{"version":1,"parentFingerprint":"fedcba98","generatedAt":20,'
    '"inventoryUpdatedAt":0,"entryCount":0,"materializationCount":0,'
    '"entries":[]}';

const _manifestPayload =
    '{"version":1,"parentFingerprint":"fedcba98","generatedAt":20,'
    '"inventoryUpdatedAt":12,"entryCount":1,"materializationCount":2,'
    '"entries":[{"entryId":"fedcba98:39\'/0\'/12\'/100\'",'
    '"bip85DerivationPath":"39\'/0\'/12\'/100\'",'
    '"reservationId":"btcpay_wallet_seed","entryType":"walletSeed",'
    '"ownerFeature":"btcpay","bip85Application":39,"bip85Index":100,'
    '"createdAt":10,"updatedAt":12,"materializations":[{"type":"wallet",'
    '"walletId":"btc-wallet","childSeedFingerprint":"0123abcd",'
    '"network":"bitcoinMainnet","scriptType":"bip84",'
    '"createdAt":10,"updatedAt":10},{"type":"wallet",'
    '"walletId":"lbtc-wallet","childSeedFingerprint":"0123abcd",'
    '"network":"liquidMainnet","scriptType":"bip84",'
    '"createdAt":11,"updatedAt":11}]}]}';
