import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/storage/data/datasources/key_value_storage/key_value_storage_datasource.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_connection.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_wallet.dart';
import 'package:bb_mobile/features/btcpay/domain/samrock_pairing_request.dart';
import 'package:bb_mobile/features/btcpay/frameworks/datasources/btcpay_connection_datasource.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stores BTCPay connection under the active environment', () async {
    final storage = _MemoryStorage();
    final datasource = BtcpayConnectionDatasource(storage: storage);
    final connection = BtcpayConnection(
      environment: Environment.mainnet,
      serverUrl: 'https://btcpay.example.com',
      storeId: 'store123',
      capabilities: const [
        SamRockSetupCapability.bitcoinChain,
        SamRockSetupCapability.liquidChain,
        SamRockSetupCapability.bitcoinLightning,
      ],
      walletNetworks: const [
        BtcpayWalletNetwork.bitcoin,
        BtcpayWalletNetwork.liquid,
      ],
      status: BtcpayConnectionStatus.uncertain,
      pairedAt: null,
      updatedAt: DateTime.utc(2026, 5, 23),
      lastError: 'timeout',
    );

    await datasource.saveConnection(connection);

    final mainnet = await datasource.getConnection(Environment.mainnet);
    final testnet = await datasource.getConnection(Environment.testnet);
    expect(mainnet, isNotNull);
    expect(mainnet!.environment, Environment.mainnet);
    expect(mainnet.storeId, 'store123');
    expect(mainnet.isUncertain, isTrue);
    expect(mainnet.supportsLightning, isTrue);
    expect(mainnet.lastError, 'timeout');
    expect(testnet, isNull);
  });
}

class _MemoryStorage implements KeyValueStorageDatasource<String> {
  final _values = <String, String>{};

  @override
  Future<void> deleteAll() async => _values.clear();

  @override
  Future<void> deleteValue(String key) async => _values.remove(key);

  @override
  Future<Map<String, String>> getAll() async => Map.of(_values);

  @override
  Future<String?> getValue(String key) async => _values[key];

  @override
  Future<bool> hasValue(String key) async => _values.containsKey(key);

  @override
  Future<void> saveValue({required String key, required String value}) async {
    _values[key] = value;
  }
}
