import 'dart:convert';

import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_file.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

const int keychainManifestNostrEventKind = 30078;
const String keychainManifestNostrDTag = 'manifest';
const String keychainManifestNostrSnapshotContentType =
    'bullbitcoin.keychain_manifest.v1';

final class KeychainManifestNostrEventException implements Exception {
  final String message;
  final Object? cause;

  const KeychainManifestNostrEventException(this.message, {this.cause});

  @override
  String toString() => 'KeychainManifestNostrEventException: $message';
}

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
  final String encryptedContent;
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
    if (encryptedContent.trim().isEmpty) {
      throw KeychainManifestNostrEventException(
        'encrypted Nostr event content is required',
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
  }) : id = keychainManifestNostrEventIdForDraft(draft),
       authorPublicKeyHex = draft.authorPublicKeyHex,
       createdAt = draft.createdAt,
       kind = draft.kind,
       tags = List<List<String>>.unmodifiable(
         draft.tags.map(List<String>.unmodifiable),
       ),
       encryptedContent = draft.encryptedContent,
       signatureHex = signatureHex.trim().toLowerCase() {
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
  final serialized = jsonEncode([
    0,
    draft.authorPublicKeyHex,
    draft.createdAt,
    draft.kind,
    draft.tags,
    draft.encryptedContent,
  ]);
  return hex.encode(sha256.convert(utf8.encode(serialized)).bytes);
}
