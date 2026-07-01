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

  String toJsonString() {
    return jsonEncode({
      'version': version,
      'contentType': contentType,
      'encryptedContent': encryptedContent,
    });
  }
}
