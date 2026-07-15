import 'dart:convert';

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
  const KeychainManifestNostrSignedEventCodec();

  String serialize(KeychainManifestNostrSignedEvent event) {
    return _toNostrEvent(event).serialize();
  }

  KeychainManifestNostrSignedEvent fromNostrEvent(nostr.Event event) {
    // Recovery authenticity boundary (P21a): re-verify the event explicitly
    // instead of trusting Event.deserialize's verify:true default, so a
    // transport-side perf tweak (verify:false "for faster deserialization")
    // can never silently disable authenticity. isValid() checks the NIP-01 id
    // and the BIP340 signature under the author key.
    if (!event.isValid()) {
      throw KeychainManifestNostrEventException(
        'Nostr manifest event failed authenticity verification',
      );
    }
    return KeychainManifestNostrSignedEvent.fromRelay(
      id: event.id,
      authorPublicKeyHex: event.pubkey,
      createdAt: event.createdAt,
      kind: event.kind,
      tags: event.tags,
      encryptedContent: event.content,
      signatureHex: event.sig,
    );
  }

  nostr.Event _toNostrEvent(KeychainManifestNostrSignedEvent event) {
    return nostr.Event(
      event.id,
      event.authorPublicKeyHex,
      event.createdAt,
      event.kind,
      event.tags,
      event.encryptedContent,
      event.signatureHex,
      verify: false,
    );
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
