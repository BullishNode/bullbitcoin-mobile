import 'dart:convert';

import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/storage/data/datasources/key_value_storage/key_value_storage_datasource.dart';
import 'package:bb_mobile/features/btcpay/application/ports/btcpay_connection_store.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_connection.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_wallet.dart';
import 'package:bb_mobile/features/btcpay/domain/samrock_pairing_request.dart';

class BtcpayConnectionDatasource implements BtcpayConnectionStore {
  static const _connectionKeyPrefix = 'btcpay_connection';

  final KeyValueStorageDatasource<String> _storage;

  const BtcpayConnectionDatasource({required this._storage});

  @override
  Future<BtcpayConnection?> getConnection(Environment environment) async {
    final value = await _storage.getValue(_connectionKey(environment));
    if (value == null || value.trim().isEmpty) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;

    final serverUrl = decoded['serverUrl'];
    final storeId = decoded['storeId'];
    final storedEnvironment = decoded['environment'];
    final status = decoded['status'];
    final pairedAt = decoded['pairedAt'];
    final updatedAt = decoded['updatedAt'];
    final capabilities = decoded['capabilities'];
    final walletNetworks = decoded['walletNetworks'];
    final walletIds = decoded['walletIds'];
    if (serverUrl is! String ||
        storeId is! String ||
        storedEnvironment is! String ||
        status is! String ||
        updatedAt is! String ||
        capabilities is! List ||
        walletNetworks is! List) {
      return null;
    }
    if (storedEnvironment != environment.name) return null;

    final parsedStatus = _statusFromValue(status);
    final parsedPairedAt = pairedAt is String
        ? DateTime.tryParse(pairedAt)
        : null;
    final parsedUpdatedAt = DateTime.tryParse(updatedAt);
    if (parsedStatus == null || parsedUpdatedAt == null) return null;
    if (parsedStatus == BtcpayConnectionStatus.paired &&
        parsedPairedAt == null) {
      return null;
    }

    final parsedCapabilities = capabilities
        .whereType<String>()
        .map(SamRockSetupCapability.tryParse)
        .whereType<SamRockSetupCapability>()
        .toList();
    final parsedWalletNetworks = walletNetworks
        .whereType<String>()
        .map(_walletNetworkFromValue)
        .whereType<BtcpayWalletNetwork>()
        .toList();
    if (parsedWalletNetworks.isEmpty) return null;
    final parsedWalletIds = <BtcpayWalletNetwork, String>{};
    if (walletIds is Map) {
      for (final entry in walletIds.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || value is! String || value.trim().isEmpty) {
          continue;
        }
        final network = _walletNetworkFromValue(key);
        if (network != null) parsedWalletIds[network] = value;
      }
    }

    return BtcpayConnection(
      environment: environment,
      serverUrl: serverUrl,
      storeId: storeId,
      capabilities: parsedCapabilities,
      walletNetworks: parsedWalletNetworks,
      walletIds: parsedWalletIds,
      status: parsedStatus,
      pairedAt: parsedPairedAt,
      updatedAt: parsedUpdatedAt,
      lastError: decoded['lastError'] is String
          ? decoded['lastError'] as String
          : null,
    );
  }

  @override
  Future<void> saveConnection(BtcpayConnection connection) {
    return _storage.saveValue(
      key: _connectionKey(connection.environment),
      value: jsonEncode({
        'environment': connection.environment.name,
        'serverUrl': connection.serverUrl,
        'storeId': connection.storeId,
        'status': _statusValue(connection.status),
        'capabilities': connection.capabilities.map((c) => c.value).toList(),
        'walletNetworks': connection.walletNetworks
            .map(_walletNetworkValue)
            .toList(),
        'walletIds': connection.walletIds.map(
          (network, walletId) =>
              MapEntry(_walletNetworkValue(network), walletId),
        ),
        'pairedAt': connection.pairedAt?.toIso8601String(),
        'updatedAt': connection.updatedAt.toIso8601String(),
        'lastError': connection.lastError,
      }),
    );
  }

  String _connectionKey(Environment environment) {
    return '${_connectionKeyPrefix}_${environment.name}';
  }

  BtcpayConnectionStatus? _statusFromValue(String value) {
    return switch (value) {
      'paired' => BtcpayConnectionStatus.paired,
      'uncertain' => BtcpayConnectionStatus.uncertain,
      _ => null,
    };
  }

  String _statusValue(BtcpayConnectionStatus status) {
    return switch (status) {
      BtcpayConnectionStatus.paired => 'paired',
      BtcpayConnectionStatus.uncertain => 'uncertain',
    };
  }

  BtcpayWalletNetwork? _walletNetworkFromValue(String value) {
    return switch (value) {
      'bitcoin' => BtcpayWalletNetwork.bitcoin,
      'liquid' => BtcpayWalletNetwork.liquid,
      _ => null,
    };
  }

  String _walletNetworkValue(BtcpayWalletNetwork network) {
    return switch (network) {
      BtcpayWalletNetwork.bitcoin => 'bitcoin',
      BtcpayWalletNetwork.liquid => 'liquid',
    };
  }
}
