import 'package:bb_mobile/core/nostr/nostr_event_id.dart';
import 'package:bb_mobile/core/nostr/nostr_signed_event.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_file.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_ciphertext.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';

const int keychainManifestNostrEventKind = 30078;
const String keychainManifestNostrDTag = 'manifest';
const String keychainManifestNostrSnapshotContentType =
    'bullbitcoin.keychain_manifest.v1';

class KeychainManifestNostrSnapshot {
  static const currentVersion = 1;

  final int version;
  final String contentType;
  final KeychainManifestFile manifestFile;

  KeychainManifestNostrSnapshot({
    this.version = currentVersion,
    this.contentType = keychainManifestNostrSnapshotContentType,
    required this.manifestFile,
  }) {
    if (version != currentVersion) {
      throw KeychainManifestNostrEventException(
        'unsupported keychain manifest Nostr snapshot version',
      );
    }
    if (contentType != keychainManifestNostrSnapshotContentType) {
      throw KeychainManifestNostrEventException(
        'unsupported keychain manifest Nostr snapshot content type',
      );
    }
  }
}

class KeychainManifestNostrEventDraft {
  final NostrEventDraft _event;
  final KeychainManifestNostrCiphertext encryptedContent;

  factory KeychainManifestNostrEventDraft({
    required String authorPublicKeyHex,
    required KeychainManifestNostrCiphertext encryptedContent,
    required int createdAt,
  }) {
    try {
      return KeychainManifestNostrEventDraft._(
        NostrEventDraft(
          authorPublicKeyHex: authorPublicKeyHex,
          createdAt: createdAt,
          kind: keychainManifestNostrEventKind,
          tags: const [
            ['d', keychainManifestNostrDTag],
          ],
          content: encryptedContent.value,
        ),
        encryptedContent: encryptedContent,
      );
    } on NostrEventException catch (e) {
      throw KeychainManifestNostrEventException(
        'invalid keychain manifest Nostr event draft',
        cause: e,
      );
    }
  }

  const KeychainManifestNostrEventDraft._(
    this._event, {
    required this.encryptedContent,
  });

  String get authorPublicKeyHex => _event.authorPublicKeyHex;

  int get createdAt => _event.createdAt;

  int get kind => _event.kind;

  List<List<String>> get tags => _event.tags;
}

class KeychainManifestNostrSignedEvent {
  final NostrSignedEvent _event;

  factory KeychainManifestNostrSignedEvent.fromDraft({
    required KeychainManifestNostrEventDraft draft,
    required String signatureHex,
  }) {
    try {
      return KeychainManifestNostrSignedEvent._(
        NostrSignedEvent.fromDraft(
          draft: draft._event,
          signatureHex: signatureHex,
        ),
      );
    } on NostrEventException catch (e) {
      throw KeychainManifestNostrEventException(
        'invalid signed keychain manifest Nostr event',
        cause: e,
      );
    }
  }

  factory KeychainManifestNostrSignedEvent.fromRelay({
    required String id,
    required String authorPublicKeyHex,
    required int createdAt,
    required int kind,
    required List<List<String>> tags,
    required String encryptedContent,
    required String signatureHex,
  }) {
    try {
      final ciphertext = KeychainManifestNostrCiphertext(encryptedContent);
      final event = NostrSignedEvent.fromRelayFields(
        id: id,
        authorPublicKeyHex: authorPublicKeyHex,
        createdAt: createdAt,
        kind: kind,
        tags: tags,
        content: ciphertext.value,
        signatureHex: signatureHex,
      );
      return KeychainManifestNostrSignedEvent.fromVerifiedEvent(event);
    } on KeychainManifestException {
      rethrow;
    } on NostrEventException catch (e) {
      throw KeychainManifestNostrEventException(
        'invalid signed keychain manifest Nostr event',
        cause: e,
      );
    }
  }

  factory KeychainManifestNostrSignedEvent.fromVerifiedEvent(
    NostrSignedEvent event,
  ) {
    if (event.kind != keychainManifestNostrEventKind ||
        !event.tags.any(
          (tag) =>
              tag.length >= 2 &&
              tag[0] == 'd' &&
              tag[1] == keychainManifestNostrDTag,
        )) {
      throw KeychainManifestNostrEventException(
        'Nostr event is not a keychain manifest snapshot',
      );
    }
    KeychainManifestNostrCiphertext(event.content);
    return KeychainManifestNostrSignedEvent._(event);
  }

  const KeychainManifestNostrSignedEvent._(this._event);

  String get id => _event.id;

  String get authorPublicKeyHex => _event.authorPublicKeyHex;

  int get createdAt => _event.createdAt;

  int get kind => _event.kind;

  List<List<String>> get tags => _event.tags;

  String get encryptedContent => _event.content;

  String get signatureHex => _event.signatureHex;

  NostrSignedEvent toNostrSignedEvent() => _event;
}

String keychainManifestNostrEventIdForDraft(
  KeychainManifestNostrEventDraft draft,
) {
  return draft._event.id;
}

String keychainManifestNostrEventId({
  required String authorPublicKeyHex,
  required int createdAt,
  required int kind,
  required List<List<String>> tags,
  required String encryptedContent,
}) {
  return nostrEventId(
    pubkey: authorPublicKeyHex,
    createdAt: createdAt,
    kind: kind,
    tags: tags,
    content: encryptedContent,
  );
}
