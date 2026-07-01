import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_nostr_event_model.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_file.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('wraps invalid nested manifest files as Nostr snapshot failures', () {
    final payload = _nostrSnapshotPayload.replaceFirst(
      '"manifestFile":{"version":1',
      '"manifestFile":{"version":2',
    );

    expect(
      () => codec.decode(payload),
      throwsA(
        isA<KeychainManifestNostrEventException>().having(
          (error) => error.cause,
          'cause',
          isA<KeychainManifestFileParseException>(),
        ),
      ),
    );
  });

  test('keeps event public tags limited to the addressable manifest tag', () {
    final event = KeychainManifestNostrEventDraft(
      authorPublicKeyHex:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      encryptedContent: 'encrypted-payload',
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
    expect(event.encryptedContent, 'encrypted-payload');
  });

  test('validates event author, content, and timestamp', () {
    expect(
      () => KeychainManifestNostrEventDraft(
        authorPublicKeyHex: 'not-a-key',
        encryptedContent: 'encrypted-payload',
        createdAt: 123,
      ),
      throwsA(isA<KeychainManifestNostrEventException>()),
    );
    expect(
      () => KeychainManifestNostrEventDraft(
        authorPublicKeyHex:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        encryptedContent: ' ',
        createdAt: 123,
      ),
      throwsA(isA<KeychainManifestNostrEventException>()),
    );
    expect(
      () => KeychainManifestNostrEventDraft(
        authorPublicKeyHex:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        encryptedContent: 'encrypted-payload',
        createdAt: -1,
      ),
      throwsA(isA<KeychainManifestNostrEventException>()),
    );
  });

  test('derives deterministic NIP-01 event ids and encodes signed events', () {
    const signedCodec = KeychainManifestNostrSignedEventCodec();
    final draft = KeychainManifestNostrEventDraft(
      authorPublicKeyHex:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      encryptedContent: 'encrypted-payload',
      createdAt: 123,
    );
    final eventId = keychainManifestNostrEventIdForDraft(draft);
    final signed = KeychainManifestNostrSignedEvent.fromDraft(
      draft: draft,
      signatureHex: _signatureHex,
    );

    expect(
      eventId,
      'c41a120630a0329803e227d2beea76c286ef40f28b25cfe51ad54c3da88c1ec9',
    );
    expect(signed.signatureHex, _signatureHex);
    expect(signed.id, eventId);
    expect(signed.authorPublicKeyHex, draft.authorPublicKeyHex);
    expect(signed.tags, [
      ['d', keychainManifestNostrDTag],
    ]);
    expect(signedCodec.encode(signed), {
      'id': signed.id,
      'pubkey': draft.authorPublicKeyHex,
      'created_at': 123,
      'kind': keychainManifestNostrEventKind,
      'tags': [
        ['d', keychainManifestNostrDTag],
      ],
      'content': 'encrypted-payload',
      'sig': _signatureHex,
    });
  });

  test('derives signed event ids internally and deep-freezes tags', () {
    final draft = KeychainManifestNostrEventDraft(
      authorPublicKeyHex:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      encryptedContent: 'encrypted-payload',
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

  test('rejects invalid signed event signatures', () {
    final draft = KeychainManifestNostrEventDraft(
      authorPublicKeyHex:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      encryptedContent: 'encrypted-payload',
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
    inventoryUpdatedAt: 10,
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
            walletPurpose: 'bitcoin',
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
    '"generatedAt":20,"inventoryUpdatedAt":10,"entries":[{"entryId":'
    '"fedcba98:39\'/0\'/12\'/100\'","bip85DerivationPath":"39\'/0\'/12\'/100\'",'
    '"reservationId":"btcpay_wallet_seed","entryType":"walletSeed",'
    '"ownerFeature":"btcpay","bip85Application":39,"bip85Index":100,'
    '"createdAt":10,"updatedAt":10,"materializations":[{"type":"wallet",'
    '"walletId":"btc-wallet","childSeedFingerprint":"0123abcd",'
    '"network":"bitcoinMainnet","walletPurpose":"bitcoin",'
    '"scriptType":"bip84","createdAt":10,"updatedAt":10}]}]}}';

const _signatureHex =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
