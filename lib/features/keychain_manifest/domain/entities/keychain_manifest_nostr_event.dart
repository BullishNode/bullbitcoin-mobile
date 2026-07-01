import 'package:bb_mobile/core/nostr/nostr_event_id.dart';
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
  static final _xOnlyPublicKeyPattern = RegExp(r'^[0-9a-fA-F]{64}$');

  final String authorPublicKeyHex;
  final KeychainManifestNostrCiphertext encryptedContent;
  final int createdAt;

  KeychainManifestNostrEventDraft({
    required String authorPublicKeyHex,
    required this.encryptedContent,
    required this.createdAt,
  }) : authorPublicKeyHex = authorPublicKeyHex.trim().toLowerCase() {
    if (!_xOnlyPublicKeyPattern.hasMatch(this.authorPublicKeyHex)) {
      throw KeychainManifestNostrEventException(
        'author public key must be a 32-byte x-only hex key',
      );
    }
    if (createdAt < 0) {
      throw KeychainManifestNostrEventException(
        'Nostr event timestamp must be non-negative',
      );
    }
  }

  int get kind => keychainManifestNostrEventKind;

  List<List<String>> get tags => const [
    ['d', keychainManifestNostrDTag],
  ];
}

class KeychainManifestNostrSignedEvent {
  static final _eventIdPattern = RegExp(r'^[0-9a-fA-F]{64}$');
  static final _xOnlyPublicKeyPattern = RegExp(r'^[0-9a-fA-F]{64}$');
  static final _signaturePattern = RegExp(r'^[0-9a-fA-F]{128}$');

  final String id;
  final String authorPublicKeyHex;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String encryptedContent;
  final String signatureHex;

  KeychainManifestNostrSignedEvent.fromDraft({
    required KeychainManifestNostrEventDraft draft,
    required String signatureHex,
  }) : this._(
         id: keychainManifestNostrEventIdForDraft(draft),
         authorPublicKeyHex: draft.authorPublicKeyHex,
         createdAt: draft.createdAt,
         kind: draft.kind,
         tags: draft.tags,
         encryptedContent: draft.encryptedContent.value,
         signatureHex: signatureHex,
       );

  factory KeychainManifestNostrSignedEvent.fromRelay({
    required String id,
    required String authorPublicKeyHex,
    required int createdAt,
    required int kind,
    required List<List<String>> tags,
    required String encryptedContent,
    required String signatureHex,
  }) {
    final event = KeychainManifestNostrSignedEvent._(
      id: id,
      authorPublicKeyHex: authorPublicKeyHex,
      createdAt: createdAt,
      kind: kind,
      tags: tags,
      encryptedContent: encryptedContent,
      signatureHex: signatureHex,
    );
    if (kind != keychainManifestNostrEventKind ||
        !tags.any(
          (tag) =>
              tag.length >= 2 &&
              tag[0] == 'd' &&
              tag[1] == keychainManifestNostrDTag,
        )) {
      throw KeychainManifestNostrEventException(
        'Nostr event is not a keychain manifest snapshot',
      );
    }
    final draft = KeychainManifestNostrEventDraft(
      authorPublicKeyHex: event.authorPublicKeyHex,
      encryptedContent: KeychainManifestNostrCiphertext(event.encryptedContent),
      createdAt: event.createdAt,
    );
    final expectedId = keychainManifestNostrEventId(
      authorPublicKeyHex: draft.authorPublicKeyHex,
      createdAt: draft.createdAt,
      kind: event.kind,
      tags: event.tags,
      encryptedContent: draft.encryptedContent.value,
    );
    if (event.id != expectedId) {
      throw KeychainManifestNostrEventException(
        'Nostr event id does not match keychain manifest payload',
      );
    }
    return event;
  }

  KeychainManifestNostrSignedEvent._({
    required String id,
    required String authorPublicKeyHex,
    required this.createdAt,
    required this.kind,
    required List<List<String>> tags,
    required this.encryptedContent,
    required String signatureHex,
  }) : id = id.trim().toLowerCase(),
       authorPublicKeyHex = authorPublicKeyHex.trim().toLowerCase(),
       tags = List<List<String>>.unmodifiable(
         tags.map(List<String>.unmodifiable),
       ),
       signatureHex = signatureHex.trim().toLowerCase() {
    if (!_eventIdPattern.hasMatch(this.id)) {
      throw KeychainManifestNostrEventException(
        'Nostr event id must be a 32-byte hex value',
      );
    }
    if (!_xOnlyPublicKeyPattern.hasMatch(this.authorPublicKeyHex)) {
      throw KeychainManifestNostrEventException(
        'Nostr event author must be a 32-byte x-only hex key',
      );
    }
    if (createdAt < 0) {
      throw KeychainManifestNostrEventException(
        'Nostr event timestamp must be non-negative',
      );
    }
    if (encryptedContent.trim().isEmpty) {
      throw KeychainManifestNostrEventException(
        'encrypted Nostr event content is required',
      );
    }
    if (!_signaturePattern.hasMatch(this.signatureHex)) {
      throw KeychainManifestNostrEventException(
        'Nostr event signature must be a 64-byte hex value',
      );
    }
  }
}

String keychainManifestNostrEventIdForDraft(
  KeychainManifestNostrEventDraft draft,
) {
  return keychainManifestNostrEventId(
    authorPublicKeyHex: draft.authorPublicKeyHex,
    createdAt: draft.createdAt,
    kind: draft.kind,
    tags: draft.tags,
    encryptedContent: draft.encryptedContent.value,
  );
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
