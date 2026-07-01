import 'dart:convert';

import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_nostr_encryption.dart';

class KeychainManifestNostrEncryptedContentModel {
  final int version;
  final String contentType;
  final String encryptedContent;

  const KeychainManifestNostrEncryptedContentModel({
    required this.version,
    required this.contentType,
    required this.encryptedContent,
  });

  factory KeychainManifestNostrEncryptedContentModel.fromEntity(
    KeychainManifestNostrEncryptedContent entity,
  ) {
    return KeychainManifestNostrEncryptedContentModel(
      version: entity.version,
      contentType: entity.contentType,
      encryptedContent: entity.encryptedContent,
    );
  }

  factory KeychainManifestNostrEncryptedContentModel.fromJsonString(
    String payload,
  ) {
    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'encrypted manifest content must be an object',
      );
    }
    final version = decoded['version'];
    final contentType = decoded['contentType'];
    final encryptedContent = decoded['encryptedContent'];
    if (version is! int ||
        contentType is! String ||
        encryptedContent is! String) {
      throw const FormatException('encrypted manifest content is malformed');
    }
    return KeychainManifestNostrEncryptedContentModel(
      version: version,
      contentType: contentType,
      encryptedContent: encryptedContent,
    );
  }

  KeychainManifestNostrEncryptedContent toEntity() {
    return KeychainManifestNostrEncryptedContent(
      version: version,
      contentType: contentType,
      encryptedContent: encryptedContent,
    );
  }

  String toJsonString() {
    return jsonEncode({
      'version': version,
      'contentType': contentType,
      'encryptedContent': encryptedContent,
    });
  }
}
