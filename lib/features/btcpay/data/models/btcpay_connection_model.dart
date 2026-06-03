import 'dart:convert';

import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_connection.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_wallet.dart';
import 'package:bb_mobile/features/btcpay/domain/samrock_pairing_request.dart';

class BtcpayConnectionModel {
  final String environment;
  final String serverUrl;
  final String storeId;
  final String status;
  final List<String> capabilities;
  final List<String> walletNetworks;
  final Map<String, String> walletIds;
  final String? pairedAt;
  final String updatedAt;
  final String? lastError;

  const BtcpayConnectionModel({
    required this.environment,
    required this.serverUrl,
    required this.storeId,
    required this.status,
    required this.capabilities,
    required this.walletNetworks,
    this.walletIds = const {},
    required this.pairedAt,
    required this.updatedAt,
    this.lastError,
  });

  /// Decodes the persisted JSON string, or returns null when the stored
  /// value is not a structurally valid connection record.
  static BtcpayConnectionModel? tryDecode(String value) {
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;

    final environment = decoded['environment'];
    final serverUrl = decoded['serverUrl'];
    final storeId = decoded['storeId'];
    final status = decoded['status'];
    final pairedAt = decoded['pairedAt'];
    final updatedAt = decoded['updatedAt'];
    final capabilities = decoded['capabilities'];
    final walletNetworks = decoded['walletNetworks'];
    final walletIds = decoded['walletIds'];
    if (environment is! String ||
        serverUrl is! String ||
        storeId is! String ||
        status is! String ||
        updatedAt is! String ||
        capabilities is! List ||
        walletNetworks is! List) {
      return null;
    }

    final parsedWalletIds = <String, String>{};
    if (walletIds is Map) {
      for (final entry in walletIds.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || value is! String || value.trim().isEmpty) {
          continue;
        }
        parsedWalletIds[key] = value;
      }
    }

    return BtcpayConnectionModel(
      environment: environment,
      serverUrl: serverUrl,
      storeId: storeId,
      status: status,
      capabilities: capabilities.whereType<String>().toList(),
      walletNetworks: walletNetworks.whereType<String>().toList(),
      walletIds: parsedWalletIds,
      pairedAt: pairedAt is String ? pairedAt : null,
      updatedAt: updatedAt,
      lastError: decoded['lastError'] is String
          ? decoded['lastError'] as String
          : null,
    );
  }

  String encode() {
    return jsonEncode({
      'environment': environment,
      'serverUrl': serverUrl,
      'storeId': storeId,
      'status': status,
      'capabilities': capabilities,
      'walletNetworks': walletNetworks,
      'walletIds': walletIds,
      'pairedAt': pairedAt,
      'updatedAt': updatedAt,
      'lastError': lastError,
    });
  }

  factory BtcpayConnectionModel.fromEntity(BtcpayConnection connection) {
    return BtcpayConnectionModel(
      environment: connection.environment.name,
      serverUrl: connection.serverUrl,
      storeId: connection.storeId,
      status: _statusValue(connection.status),
      capabilities: connection.capabilities.map((c) => c.value).toList(),
      walletNetworks: connection.walletNetworks
          .map(_walletNetworkValue)
          .toList(),
      walletIds: connection.walletIds.map(
        (network, walletId) => MapEntry(_walletNetworkValue(network), walletId),
      ),
      pairedAt: connection.pairedAt?.toIso8601String(),
      updatedAt: connection.updatedAt.toIso8601String(),
      lastError: connection.lastError,
    );
  }

  /// Maps the wire model to the domain entity, or returns null when the
  /// stored values are semantically invalid (unknown enum values, missing
  /// pairing timestamp for a paired connection, no recognized wallets).
  BtcpayConnection? toEntity() {
    final parsedEnvironment = _environmentFromValue(environment);
    final parsedStatus = _statusFromValue(status);
    final parsedPairedAt = pairedAt != null
        ? DateTime.tryParse(pairedAt!)
        : null;
    final parsedUpdatedAt = DateTime.tryParse(updatedAt);
    if (parsedEnvironment == null ||
        parsedStatus == null ||
        parsedUpdatedAt == null) {
      return null;
    }
    if (parsedStatus == BtcpayConnectionStatus.paired &&
        parsedPairedAt == null) {
      return null;
    }

    final parsedCapabilities = capabilities
        .map(SamRockSetupCapability.tryParse)
        .whereType<SamRockSetupCapability>()
        .toList();
    final parsedWalletNetworks = walletNetworks
        .map(_walletNetworkFromValue)
        .whereType<BtcpayWalletNetwork>()
        .toList();
    if (parsedWalletNetworks.isEmpty) return null;

    final parsedWalletIds = <BtcpayWalletNetwork, String>{};
    for (final entry in walletIds.entries) {
      final network = _walletNetworkFromValue(entry.key);
      if (network != null) parsedWalletIds[network] = entry.value;
    }

    return BtcpayConnection(
      environment: parsedEnvironment,
      serverUrl: serverUrl,
      storeId: storeId,
      capabilities: parsedCapabilities,
      walletNetworks: parsedWalletNetworks,
      walletIds: parsedWalletIds,
      status: parsedStatus,
      pairedAt: parsedPairedAt,
      updatedAt: parsedUpdatedAt,
      lastError: lastError,
    );
  }

  static Environment? _environmentFromValue(String value) {
    for (final environment in Environment.values) {
      if (environment.name == value) return environment;
    }
    return null;
  }

  static BtcpayConnectionStatus? _statusFromValue(String value) {
    return switch (value) {
      'paired' => BtcpayConnectionStatus.paired,
      'uncertain' => BtcpayConnectionStatus.uncertain,
      _ => null,
    };
  }

  static String _statusValue(BtcpayConnectionStatus status) {
    return switch (status) {
      BtcpayConnectionStatus.paired => 'paired',
      BtcpayConnectionStatus.uncertain => 'uncertain',
    };
  }

  static BtcpayWalletNetwork? _walletNetworkFromValue(String value) {
    return switch (value) {
      'bitcoin' => BtcpayWalletNetwork.bitcoin,
      'liquid' => BtcpayWalletNetwork.liquid,
      _ => null,
    };
  }

  static String _walletNetworkValue(BtcpayWalletNetwork network) {
    return switch (network) {
      BtcpayWalletNetwork.bitcoin => 'bitcoin',
      BtcpayWalletNetwork.liquid => 'liquid',
    };
  }
}
