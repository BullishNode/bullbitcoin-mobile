import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_wallet.dart';
import 'package:bb_mobile/features/btcpay/domain/samrock_pairing_request.dart';

enum BtcpayConnectionStatus { paired, uncertain }

class BtcpayConnection {
  final Environment environment;
  final String serverUrl;
  final String storeId;
  final List<SamRockSetupCapability> capabilities;
  final List<BtcpayWalletNetwork> walletNetworks;
  final BtcpayConnectionStatus status;
  final DateTime? pairedAt;
  final DateTime updatedAt;
  final String? lastError;

  const BtcpayConnection({
    required this.environment,
    required this.serverUrl,
    required this.storeId,
    required this.capabilities,
    required this.walletNetworks,
    required this.status,
    required this.pairedAt,
    required this.updatedAt,
    this.lastError,
  });

  bool get isPaired => status == BtcpayConnectionStatus.paired;
  bool get isUncertain => status == BtcpayConnectionStatus.uncertain;
  bool get supportsBitcoinChain =>
      capabilities.contains(SamRockSetupCapability.bitcoinChain);
  bool get supportsLiquidChain =>
      capabilities.contains(SamRockSetupCapability.liquidChain);
  bool get supportsLightning =>
      capabilities.contains(SamRockSetupCapability.bitcoinLightning);

  factory BtcpayConnection.fromPairing({
    required Environment environment,
    required SamRockPairingRequest request,
    required List<BtcpayWalletNetwork> walletNetworks,
    required BtcpayConnectionStatus status,
    required DateTime updatedAt,
    DateTime? pairedAt,
    String? lastError,
  }) {
    return BtcpayConnection(
      environment: environment,
      serverUrl: btcpayServerUrlFor(request),
      storeId: request.storeId,
      capabilities: request.setup.toList()
        ..sort((a, b) => a.value.compareTo(b.value)),
      walletNetworks: walletNetworks,
      status: status,
      pairedAt: pairedAt,
      updatedAt: updatedAt,
      lastError: lastError,
    );
  }

  BtcpayConnection copyWith({
    BtcpayConnectionStatus? status,
    DateTime? pairedAt,
    DateTime? updatedAt,
    String? lastError,
    bool clearLastError = false,
  }) {
    return BtcpayConnection(
      environment: environment,
      serverUrl: serverUrl,
      storeId: storeId,
      capabilities: capabilities,
      walletNetworks: walletNetworks,
      status: status ?? this.status,
      pairedAt: pairedAt ?? this.pairedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastError: clearLastError ? null : lastError ?? this.lastError,
    );
  }
}

String btcpayServerUrlFor(SamRockPairingRequest request) {
  final uri = request.protocolUri;
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port';
}
