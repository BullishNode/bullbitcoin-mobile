import 'dart:convert';
import 'dart:typed_data';

import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_nostr_event_model.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_file.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_ciphertext.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:flutter_test/flutter_test.dart';

/// A base64 blob just long enough to pass the ciphertext length gate.
final _wellShapedCiphertext = base64.encode(
  Uint8List(KeychainManifestNostrCiphertext.minimumByteLength),
);

void main() {
  const codec = KeychainManifestNostrSnapshotCodec();

  test('encodes keychain manifest snapshots deterministically', () {
    final payload = codec.encode(
      KeychainManifestNostrSnapshot(manifestFile: _manifestFile()),
    );

    expect(payload, _nostrSnapshotPayload);
  });

  test(
    'decodes keychain manifest snapshots through the manifest file codec',
    () {
      final snapshot = codec.decode(_nostrSnapshotPayload);

      expect(snapshot.version, KeychainManifestNostrSnapshot.currentVersion);
      expect(snapshot.contentType, keychainManifestNostrSnapshotContentType);
      expect(snapshot.manifestFile.parentFingerprint, 'fedcba98');
      expect(
        snapshot.manifestFile.entries.single.reservationId,
        'btcpay_wallet_seed',
      );
      expect(
        snapshot.manifestFile.entries.single.materializations.single.walletId,
        'btc-wallet',
      );
    },
  );

  test('rejects unsupported snapshot versions', () {
    final payload = _nostrSnapshotPayload.replaceFirst(
      '"version":1',
      '"version":2',
    );

    expect(
      () => codec.decode(payload),
      throwsA(isA<KeychainManifestNostrEventException>()),
    );
  });

  test('rejects unsupported snapshot content types', () {
    final payload = _nostrSnapshotPayload.replaceFirst(
      keychainManifestNostrSnapshotContentType,
      'other.content',
    );

    expect(
      () => codec.decode(payload),
      throwsA(isA<KeychainManifestNostrEventException>()),
    );
  });

  test('propagates invalid nested manifest file errors unchanged', () {
    // I13: the inner manifest-file parse error is already a sealed-family
    // exception, so the codec must let it propagate rather than re-wrap a
    // sealed error into a standalone one and hide its meaning.
    final payload = _nostrSnapshotPayload.replaceFirst(
      '"manifestFile":{"version":1',
      '"manifestFile":{"version":2',
    );

    expect(
      () => codec.decode(payload),
      throwsA(isA<KeychainManifestUnsupportedVersionException>()),
    );
  });

  test('keeps event public tags limited to the addressable manifest tag', () {
    final event = KeychainManifestNostrEventDraft(
      authorPublicKeyHex:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      encryptedContent: KeychainManifestNostrCiphertext(_wellShapedCiphertext),
      createdAt: 123,
    );

    expect(event.kind, keychainManifestNostrEventKind);
    expect(event.tags, [
      ['d', keychainManifestNostrDTag],
    ]);
    expect(
      event.tags.expand((tag) => tag),
      isNot(contains(keychainManifestNostrSnapshotContentType)),
    );
    expect(event.encryptedContent.value, _wellShapedCiphertext);
  });

  test('validates event author and timestamp', () {
    expect(
      () => KeychainManifestNostrEventDraft(
        authorPublicKeyHex: 'not-a-key',
        encryptedContent: KeychainManifestNostrCiphertext(
          _wellShapedCiphertext,
        ),
        createdAt: 123,
      ),
      throwsA(isA<KeychainManifestNostrEventException>()),
    );
    expect(
      () => KeychainManifestNostrEventDraft(
        authorPublicKeyHex:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        encryptedContent: KeychainManifestNostrCiphertext(
          _wellShapedCiphertext,
        ),
        createdAt: -1,
      ),
      throwsA(isA<KeychainManifestNostrEventException>()),
    );
  });

  group('KeychainManifestNostrCiphertext', () {
    test('accepts a well-shaped ciphertext blob', () {
      final ciphertext = KeychainManifestNostrCiphertext(_wellShapedCiphertext);

      expect(ciphertext.value, _wellShapedCiphertext);
    });

    test('rejects the plaintext snapshot codec output', () {
      // AD-5: the exact plaintext the snapshot codec produces must never pass
      // as ciphertext - it is JSON, not base64.
      final plaintextSnapshot = codec.encode(
        KeychainManifestNostrSnapshot(manifestFile: _manifestFile()),
      );

      expect(
        () => KeychainManifestNostrCiphertext(plaintextSnapshot),
        throwsA(isA<KeychainManifestNostrEventException>()),
      );
    });

    test('rejects arbitrary JSON', () {
      expect(
        () => KeychainManifestNostrCiphertext('{"foo":"bar"}'),
        throwsA(isA<KeychainManifestNostrEventException>()),
      );
    });

    test('rejects blank content', () {
      expect(
        () => KeychainManifestNostrCiphertext('   '),
        throwsA(isA<KeychainManifestNostrEventException>()),
      );
    });

    test('rejects a base64 blob shorter than a ciphertext', () {
      final tooShort = base64.encode(Uint8List(32));

      expect(
        () => KeychainManifestNostrCiphertext(tooShort),
        throwsA(isA<KeychainManifestNostrEventException>()),
      );
    });
  });
}

KeychainManifestFile _manifestFile() {
  return KeychainManifestFile(
    parentFingerprint: 'fedcba98',
    generatedAt: 20,
    entries: [
      KeychainManifestFileEntry(
        parentFingerprint: 'fedcba98',
        bip85DerivationPath: "39'/0'/12'/100'",
        reservationId: 'btcpay_wallet_seed',
        entryType: 'walletSeed',
        ownerFeature: 'btcpay',
        bip85Application: 39,
        bip85Index: 100,
        createdAt: 10,
        updatedAt: 10,
        materializations: [
          KeychainManifestFileWalletMaterialization(
            walletId: 'btc-wallet',
            entryId: "fedcba98:39'/0'/12'/100'",
            childSeedFingerprint: '0123abcd',
            network: 'bitcoinMainnet',
            scriptType: 'bip84',
            createdAt: 10,
            updatedAt: 10,
          ),
        ],
      ),
    ],
  );
}

const _nostrSnapshotPayload =
    '{"version":1,"contentType":"bullbitcoin.keychain_manifest.v1",'
    '"manifestFile":{"version":1,"parentFingerprint":"fedcba98",'
    '"generatedAt":20,"inventoryUpdatedAt":10,"entryCount":1,'
    '"materializationCount":1,"entries":[{"entryId":'
    '"fedcba98:39\'/0\'/12\'/100\'","bip85DerivationPath":"39\'/0\'/12\'/100\'",'
    '"reservationId":"btcpay_wallet_seed","entryType":"walletSeed",'
    '"ownerFeature":"btcpay","bip85Application":39,"bip85Index":100,'
    '"createdAt":10,"updatedAt":10,"materializations":[{"type":"wallet",'
    '"walletId":"btc-wallet","childSeedFingerprint":"0123abcd",'
    '"network":"bitcoinMainnet","scriptType":"bip84",'
    '"createdAt":10,"updatedAt":10}]}]}}';
