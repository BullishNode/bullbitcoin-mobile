import 'package:bb_mobile/features/get_paid/btcpay/application/ports/btcpay_connection_store.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/prepare_btcpay_pairing_wallets_usecase.dart';
import 'package:bb_mobile/features/get_paid/btcpay/domain/btcpay_connection.dart';
import 'package:bb_mobile/features/get_paid/btcpay/domain/samrock_pairing_request.dart';
import 'package:hive/hive.dart';

class BtcpayConnectionDatasource implements BtcpayConnectionStore {
  static const _boxName = 'btcpay_connection';
  static const _connectionKey = 'connection';

  Future<Box<dynamic>> _openBox() => Hive.openBox<dynamic>(_boxName);

  @override
  Future<BtcpayConnection?> getConnection() async {
    final box = await _openBox();
    final value = box.get(_connectionKey);
    if (value is! Map) return null;

    final serverUrl = value['serverUrl'];
    final pairedAt = value['pairedAt'];
    final capabilities = value['capabilities'];
    final walletNetworks = value['walletNetworks'];
    if (serverUrl is! String ||
        pairedAt is! String ||
        capabilities is! List ||
        walletNetworks is! List) {
      return null;
    }

    final parsedPairedAt = DateTime.tryParse(pairedAt);
    if (parsedPairedAt == null) return null;

    final parsedCapabilities = capabilities
        .whereType<String>()
        .map(SamRockSetupCapability.tryParse)
        .whereType<SamRockSetupCapability>()
        .toList();
    final parsedWalletNetworks = walletNetworks
        .whereType<String>()
        .map(_walletNetworkFromValue)
        .whereType<BtcpayPairingWalletNetwork>()
        .toList();
    if (parsedWalletNetworks.isEmpty) return null;

    return BtcpayConnection(
      serverUrl: serverUrl,
      capabilities: parsedCapabilities,
      walletNetworks: parsedWalletNetworks,
      pairedAt: parsedPairedAt,
    );
  }

  @override
  Future<void> saveConnection(BtcpayConnection connection) async {
    final box = await _openBox();
    await box.put(_connectionKey, {
      'serverUrl': connection.serverUrl,
      'capabilities': connection.capabilities.map((c) => c.value).toList(),
      'walletNetworks': connection.walletNetworks
          .map(_walletNetworkValue)
          .toList(),
      'pairedAt': connection.pairedAt.toIso8601String(),
    });
  }

  BtcpayPairingWalletNetwork? _walletNetworkFromValue(String value) {
    return switch (value) {
      'bitcoin' => BtcpayPairingWalletNetwork.bitcoin,
      'liquid' => BtcpayPairingWalletNetwork.liquid,
      _ => null,
    };
  }

  String _walletNetworkValue(BtcpayPairingWalletNetwork network) {
    return switch (network) {
      BtcpayPairingWalletNetwork.bitcoin => 'bitcoin',
      BtcpayPairingWalletNetwork.liquid => 'liquid',
    };
  }
}
