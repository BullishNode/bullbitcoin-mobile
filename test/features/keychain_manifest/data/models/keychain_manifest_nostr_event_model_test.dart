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
  test('derives deterministic NIP-01 event ids and encodes signed events', () {
    const signedCodec = KeychainManifestNostrSignedEventCodec();
    final draft = KeychainManifestNostrEventDraft(
      authorPublicKeyHex:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      encryptedContent: KeychainManifestNostrCiphertext(_wellShapedCiphertext),
      createdAt: 123,
    );
    final eventId = keychainManifestNostrEventIdForDraft(draft);
    final signed = KeychainManifestNostrSignedEvent.fromDraft(
      draft: draft,
      signatureHex: _signatureHex,
    );

    // P17a: re-pinned after AD5b - the signed event content is now the bare
    // ciphertext blob (the ciphertext VO's value), so the NIP-01 event id is
    // recomputed over that content. Append-only golden.
    expect(
      eventId,
      '8924c440aec6da3657dba376305c10231cb0809384cd0c206877f6debc952b91',
    );
    expect(signed.signatureHex, _signatureHex);
    expect(signed.id, eventId);
    expect(signed.authorPublicKeyHex, draft.authorPublicKeyHex);
    expect(signed.tags, [
      ['d', keychainManifestNostrDTag],
    ]);
    expect(jsonDecode(signedCodec.serialize(signed)), [
      'EVENT',
      {
        'id': signed.id,
        'pubkey': draft.authorPublicKeyHex,
        'created_at': 123,
        'kind': keychainManifestNostrEventKind,
        'tags': [
          ['d', keychainManifestNostrDTag],
        ],
        'content': _wellShapedCiphertext,
        'sig': _signatureHex,
      },
    ]);
  });

  test('derives signed event ids internally and deep-freezes tags', () {
    final draft = KeychainManifestNostrEventDraft(
      authorPublicKeyHex:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      encryptedContent: KeychainManifestNostrCiphertext(_wellShapedCiphertext),
      createdAt: 123,
    );
    final signed = KeychainManifestNostrSignedEvent.fromDraft(
      draft: draft,
      signatureHex: _signatureHex,
    );

    expect(signed.id, keychainManifestNostrEventIdForDraft(draft));
    expect(() => signed.tags.add(['p', 'x']), throwsUnsupportedError);
    expect(() => signed.tags.single.add('x'), throwsUnsupportedError);
  });

  test('accepts relay events with extra signed metadata tags', () {
    const tags = [
      ['d', keychainManifestNostrDTag],
      ['client', 'bullbitcoin-mobile'],
    ];
    final eventId = keychainManifestNostrEventId(
      authorPublicKeyHex:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      createdAt: 123,
      kind: keychainManifestNostrEventKind,
      tags: tags,
      encryptedContent: _wellShapedCiphertext,
    );

    final signed = KeychainManifestNostrSignedEvent.fromRelay(
      id: eventId,
      authorPublicKeyHex:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      createdAt: 123,
      kind: keychainManifestNostrEventKind,
      tags: tags,
      encryptedContent: _wellShapedCiphertext,
      signatureHex: _signatureHex,
    );

    expect(signed.id, eventId);
    expect(signed.tags, tags);
  });

  test('rejects invalid signed event signatures', () {
    final draft = KeychainManifestNostrEventDraft(
      authorPublicKeyHex:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      encryptedContent: KeychainManifestNostrCiphertext(_wellShapedCiphertext),
      createdAt: 123,
    );

    expect(
      () => KeychainManifestNostrSignedEvent.fromDraft(
        draft: draft,
        signatureHex: 'bad-signature',
      ),
      throwsA(isA<KeychainManifestNostrEventException>()),
    );
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

const _signatureHex =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
