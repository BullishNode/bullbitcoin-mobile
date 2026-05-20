import 'dart:convert';

import 'package:bb_mobile/features/wallet_manifest/domain/bip85_derivation_path.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_account.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_network.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_root_fingerprint.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_snapshot.dart';

class Bip139WalletManifestCodec {
  const Bip139WalletManifestCodec();

  String encode(WalletManifestSnapshot snapshot) {
    return jsonEncode(toJson(snapshot));
  }

  WalletManifestSnapshot decode(String encoded, {int? fallbackCreatedAt}) {
    final Object? json;
    try {
      json = jsonDecode(encoded);
    } on FormatException {
      throw const WalletManifestCodecException('manifest must be valid JSON');
    }
    if (json is! Map<String, dynamic>) {
      throw const WalletManifestCodecException(
        'manifest must be a JSON object',
      );
    }
    return fromJson(json, fallbackCreatedAt: fallbackCreatedAt);
  }

  Map<String, dynamic> toJson(WalletManifestSnapshot snapshot) {
    return {
      'version': 1,
      'bip': 139,
      'created_at': snapshot.createdAt,
      'accounts': snapshot.accounts.map(_accountToJson).toList(),
    };
  }

  WalletManifestSnapshot fromJson(
    Map<String, dynamic> json, {
    int? fallbackCreatedAt,
  }) {
    if (json['bip'] != 139) {
      throw const WalletManifestCodecException('manifest bip must be 139');
    }
    final version = _optionalInt(json['version']);
    if (version != 1) {
      throw const WalletManifestCodecException('manifest version must be 1');
    }
    final createdAt = _optionalInt(json['created_at']) ?? fallbackCreatedAt;
    if (createdAt == null) {
      throw const WalletManifestCodecException(
        'manifest created_at must be an integer',
      );
    }

    final accountsJson = json['accounts'];
    if (accountsJson is! List) {
      throw const WalletManifestCodecException(
        'manifest accounts must be a list',
      );
    }

    final accounts = <WalletManifestAccount>[];
    for (final accountJson in accountsJson) {
      if (accountJson is! Map<String, dynamic>) {
        throw const WalletManifestCodecException(
          'manifest account must be a JSON object',
        );
      }
      final account = _accountFromJson(
        accountJson,
        manifestCreatedAt: createdAt,
      );
      accounts.add(account);
    }

    return WalletManifestSnapshot(
      createdAt: createdAt,
      accounts: accounts,
    ).collapseDuplicates();
  }

  Map<String, dynamic> _accountToJson(WalletManifestAccount account) {
    final keyObject = {
      'key': account.rootFingerprint,
      'key_type': 'internal',
      'bip85_derivation_path': account.bip85DerivationPath.value,
    };

    return {
      if (account.name != null) 'name': account.name,
      'type': 'bip_380',
      'network': account.network.value,
      if (account.descriptor != null) 'descriptor': account.descriptor,
      if (account.changeDescriptor != null)
        'change_descriptor': account.changeDescriptor,
      if (account.timestamp != null) 'timestamp': account.timestamp,
      'keys': {account.rootFingerprint: keyObject},
      'proprietary': {
        'bullbitcoin': {
          'wallet_type': account.walletType.value,
          'bip85_index': account.bip85Index,
        },
      },
    };
  }

  WalletManifestAccount _accountFromJson(
    Map<String, dynamic> json, {
    required int manifestCreatedAt,
  }) {
    final networkValue = json['network'];
    if (networkValue is! String) {
      throw const WalletManifestCodecException(
        'manifest account network must be a string',
      );
    }
    final network = WalletManifestNetwork.tryParse(networkValue);
    if (network == null) {
      throw const WalletManifestCodecException(
        'manifest account network is unsupported',
      );
    }

    final keyEntry = _singleRestorableKeyEntry(json['keys']);
    if (keyEntry == null) {
      throw const WalletManifestCodecException(
        'manifest account must contain exactly one restorable BIP85 key',
      );
    }

    final keyFingerprint = keyEntry.key;
    final keyJson = keyEntry.value;
    final keyValue = keyJson['key'];
    final rootFingerprint =
        WalletManifestRootFingerprint.tryNormalize(
          keyValue is String ? keyValue : null,
        ) ??
        WalletManifestRootFingerprint.tryNormalize(keyFingerprint);
    if (rootFingerprint == null) {
      throw const WalletManifestCodecException(
        'manifest account root fingerprint is invalid',
      );
    }
    final path = keyEntry.path;
    final timestampOrInvalid = _accountTimestampOrNull(json, manifestCreatedAt);
    if (timestampOrInvalid == _invalidTimestamp) {
      throw const WalletManifestCodecException(
        'manifest account timestamp is invalid',
      );
    }
    final timestamp = timestampOrInvalid as int?;

    return WalletManifestAccount(
      rootFingerprint: rootFingerprint,
      bip85DerivationPath: path,
      network: network,
      name: _optionalString(json['name']),
      descriptor: _optionalString(json['descriptor']),
      changeDescriptor: _optionalString(json['change_descriptor']),
      timestamp: timestamp,
    );
  }

  _RestorableKeyEntry? _singleRestorableKeyEntry(Object? keysJson) {
    if (keysJson is! Map<String, dynamic>) return null;
    final entries = <_RestorableKeyEntry>[];
    for (final entry in keysJson.entries) {
      if (entry.value is Map<String, dynamic>) {
        final keyJson = entry.value as Map<String, dynamic>;
        final pathValue = keyJson['bip85_derivation_path'];
        if (pathValue is! String) continue;
        final path = Bip85DerivationPath.tryParse(pathValue);
        if (path == null) continue;
        entries.add(
          _RestorableKeyEntry(key: entry.key, value: keyJson, path: path),
        );
      }
    }
    if (entries.length != 1) return null;
    return entries.single;
  }

  int? _optionalInt(Object? value) {
    if (value is int) return value;
    return null;
  }

  Object? _accountTimestampOrNull(
    Map<String, dynamic> json,
    int manifestCreatedAt,
  ) {
    if (!json.containsKey('timestamp')) {
      return null;
    }
    final timestamp = _optionalInt(json['timestamp']);
    if (timestamp == null) {
      return _invalidTimestamp;
    }
    if (timestamp < 0 || timestamp > manifestCreatedAt) {
      return _invalidTimestamp;
    }
    return timestamp;
  }

  String? _optionalString(Object? value) => value is String ? value : null;
}

const _invalidTimestamp = Object();

class WalletManifestCodecException implements Exception {
  final String message;

  const WalletManifestCodecException(this.message);

  @override
  String toString() => 'WalletManifestCodecException: $message';
}

class _RestorableKeyEntry {
  final String key;
  final Map<String, dynamic> value;
  final Bip85DerivationPath path;

  const _RestorableKeyEntry({
    required this.key,
    required this.value,
    required this.path,
  });
}
