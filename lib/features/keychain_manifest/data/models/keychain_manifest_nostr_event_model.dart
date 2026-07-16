import 'dart:convert';

import 'package:bb_mobile/core/nostr/nostr_signed_event.dart';
import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_file_model.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:nostr/nostr.dart' as nostr;

class KeychainManifestNostrSnapshotCodec {
  static const _manifestFileKey = 'manifestFile';

  final KeychainManifestFileCodec manifestFileCodec;

  const KeychainManifestNostrSnapshotCodec({
    this.manifestFileCodec = const KeychainManifestFileCodec(),
  });

  String encode(KeychainManifestNostrSnapshot snapshot) {
    final manifestJson = jsonDecode(
      manifestFileCodec.encode(snapshot.manifestFile),
    );
    return jsonEncode({
      'version': snapshot.version,
      'contentType': snapshot.contentType,
      _manifestFileKey: manifestJson,
    });
  }

  KeychainManifestNostrSnapshot decode(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, Object?>) {
        throw KeychainManifestNostrEventException(
          'keychain manifest Nostr snapshot must be a JSON object',
        );
      }
      final version = _int(decoded, 'version');
      final contentType = _string(decoded, 'contentType');
      final manifestFileJson = _map(
        decoded[_manifestFileKey],
        _manifestFileKey,
      );
      final manifestFile = manifestFileCodec.decode(
        jsonEncode(manifestFileJson),
      );
      return KeychainManifestNostrSnapshot(
        version: version,
        contentType: contentType,
        manifestFile: manifestFile,
      );
    } on KeychainManifestException {
      // Nostr-envelope shape errors and inner manifest-file parse errors are
      // both sealed-family exceptions now (I13); propagate them unchanged
      // instead of re-wrapping a sealed error into a standalone one.
      rethrow;
    } on FormatException catch (e) {
      throw KeychainManifestNostrEventException(
        'keychain manifest Nostr snapshot is malformed',
        cause: e,
      );
    } catch (e) {
      throw KeychainManifestNostrEventException(
        'keychain manifest Nostr snapshot is invalid',
        cause: e,
      );
    }
  }
}

class KeychainManifestNostrSignedEventCodec {
  final NostrSignedEventCodec codec;

  const KeychainManifestNostrSignedEventCodec({
    this.codec = const NostrSignedEventCodec(),
  });

  String serialize(KeychainManifestNostrSignedEvent event) =>
      codec.serialize(event.toNostrSignedEvent());

  KeychainManifestNostrSignedEvent fromNostrEvent(nostr.Event event) {
    try {
      return KeychainManifestNostrSignedEvent.fromVerifiedEvent(
        codec.fromNostrEvent(event),
      );
    } on KeychainManifestException {
      rethrow;
    } on NostrEventException catch (e) {
      throw KeychainManifestNostrEventException(
        'Nostr manifest event failed authenticity verification',
        cause: e,
      );
    }
  }
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw KeychainManifestNostrEventException(
    'keychain manifest Nostr snapshot field $key must be a string',
  );
}

int _int(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw KeychainManifestNostrEventException(
    'keychain manifest Nostr snapshot field $key must be an integer',
  );
}

Map<String, Object?> _map(Object? value, String description) {
  if (value is Map<String, Object?>) return value;
  throw KeychainManifestNostrEventException(
    'keychain manifest Nostr snapshot field $description must be an object',
  );
}
