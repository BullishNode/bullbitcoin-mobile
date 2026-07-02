import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/storage/data/datasources/key_value_storage/key_value_storage_datasource.dart';
import 'package:bb_mobile/features/btcpay/data/btcpay_connection_repository_impl.dart';
import 'package:bb_mobile/features/btcpay/data/datasources/btcpay_connection_datasource.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_connection.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_wallet.dart';
import 'package:bb_mobile/features/btcpay/domain/samrock_pairing_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BtcpayConnectionRepositoryImpl repositoryWith(_MemoryStorage storage) {
    return BtcpayConnectionRepositoryImpl(
      datasource: BtcpayConnectionDatasource(storage: storage),
    );
  }

  test('stores BTCPay connection under the active environment', () async {
    final storage = _MemoryStorage();
    final repository = repositoryWith(storage);
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

    await repository.saveConnection(connection);

    final mainnet = await repository.getConnection(Environment.mainnet);
    final testnet = await repository.getConnection(Environment.testnet);
    expect(mainnet, isNotNull);
    expect(mainnet!.environment, Environment.mainnet);
    expect(mainnet.storeId, 'store123');
    expect(mainnet.isUncertain, isTrue);
    expect(mainnet.supportsLightning, isTrue);
    expect(mainnet.lastError, 'timeout');
    expect(testnet, isNull);
  });

  test('treats malformed stored values as absent', () async {
    final storage = _MemoryStorage();
    final repository = repositoryWith(storage);
    await storage.saveValue(
      key: 'btcpay_connection_mainnet',
      value: 'not-json',
    );

    expect(await repository.getConnection(Environment.mainnet), isNull);
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
