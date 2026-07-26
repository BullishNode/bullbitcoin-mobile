import 'package:bb_mobile/core/exchange/data/datasources/bullbitcoin_api_key_datasource.dart';
import 'package:bb_mobile/core/exchange/data/models/api_key_model.dart';
import 'package:bb_mobile/core/exchange/data/models/scoped_api_key_model.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/features/fiat_settlement/data/scoped_settlement_key_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Datasource extends Mock implements BullbitcoinApiKeyDatasource {}

class _Settings extends Mock implements GetSettingsUsecase {}

const _scopedKey =
    'bbak-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  late _Datasource datasource;
  late ScopedSettlementKeyAdapter adapter;

  setUp(() {
    datasource = _Datasource();
    final settings = _Settings();
    when(settings.execute).thenAnswer(
      (_) async => const SettingsEntity(
        environment: Environment.mainnet,
        bitcoinUnit: BitcoinUnit.sats,
        currencyCode: 'USD',
      ),
    );
    adapter = ScopedSettlementKeyAdapter(
      datasource: datasource,
      getSettings: settings,
    );
  });

  test(
    'returns a well-formed scoped key bound to the active account',
    () async {
      when(
        () => datasource.get(isTestnet: false),
      ).thenAnswer((_) async => _broad('user-a'));
      when(
        () => datasource.getSellToFiatBalanceApiKey(isTestnet: false),
      ).thenAnswer(
        (_) async => const ScopedApiKeyModel(userId: 'user-a', key: _scopedKey),
      );

      expect(await adapter.readPlaintext(), _scopedKey);
    },
  );

  test('fails closed when the scoped key belongs to another account', () async {
    when(
      () => datasource.get(isTestnet: false),
    ).thenAnswer((_) async => _broad('user-b'));
    when(
      () => datasource.getSellToFiatBalanceApiKey(isTestnet: false),
    ).thenAnswer(
      (_) async => const ScopedApiKeyModel(userId: 'user-a', key: _scopedKey),
    );

    expect(await adapter.readPlaintext(), isNull);
    expect(await adapter.isPresent(), isFalse);
  });

  test('fails closed on either secure-storage read failure', () async {
    when(
      () => datasource.get(isTestnet: false),
    ).thenThrow(Exception('read failed'));

    expect(await adapter.readPlaintext(), isNull);
  });
}

ExchangeApiKeyModel _broad(String userId) => ExchangeApiKeyModel(
  id: 'id',
  key: 'broad-secret',
  name: 'mobile',
  userId: userId,
  isActive: true,
  createdAt: 1,
  updatedAt: 1,
);
