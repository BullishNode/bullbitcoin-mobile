import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_lightning_address_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/update_lightning_address_wallet_behavior_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pins reads to the Lightning Address product', () async {
    GetPaidWalletProduct? requested;
    final facade = _facade(
      read: ({only}) async {
        requested = only;
        return [_behavior(GetPaidWalletProduct.lightningAddress)];
      },
    );

    final value = await GetLightningAddressWalletBehaviorUsecase(
      getPaidSettings: facade,
    ).execute();

    expect(requested, GetPaidWalletProduct.lightningAddress);
    expect(value, isA<LightningAddressWalletBehaviorFound>());
    expect(
      (value as LightningAddressWalletBehaviorFound).behavior.walletId,
      'wallet-1',
    );
  });

  test('keeps confirmed absence distinct from an unavailable read', () async {
    final value = await GetLightningAddressWalletBehaviorUsecase(
      getPaidSettings: _facade(),
    ).execute();

    expect(value, isA<LightningAddressWalletBehaviorAbsent>());
  });

  test('maps a settings read exception to unavailable', () async {
    final value = await GetLightningAddressWalletBehaviorUsecase(
      getPaidSettings: _facade(read: ({only}) async => throw Exception('down')),
    ).execute();

    expect(value, isA<LightningAddressWalletBehaviorUnavailable>());
  });

  test('does not convert programmer errors into unavailable', () async {
    final future = GetLightningAddressWalletBehaviorUsecase(
      getPaidSettings: _facade(read: ({only}) async => throw StateError('bug')),
    ).execute();

    await expectLater(future, throwsA(isA<StateError>()));
  });

  test('maps a settings write failure to false', () async {
    final facade = _facade(
      update: ({required walletId, hideOnHome, autoSweepEnabled}) async {
        throw Exception('write failed');
      },
    );

    final saved = await UpdateLightningAddressWalletBehaviorUsecase(
      getPaidSettings: facade,
    ).execute(walletId: 'wallet-1', autoSweepEnabled: true);

    expect(saved, isFalse);
  });
}

GetPaidSettingsFacade _facade({
  Future<List<GetPaidWalletBehavior>> Function({GetPaidWalletProduct? only})?
  read,
  Future<void> Function({
    required String walletId,
    bool? hideOnHome,
    bool? autoSweepEnabled,
  })?
  update,
}) => GetPaidSettingsFacade(
  walletBehaviors: read ?? ({only}) async => const [],
  updateWalletBehavior:
      update ?? ({required walletId, hideOnHome, autoSweepEnabled}) async {},
);

GetPaidWalletBehavior _behavior(GetPaidWalletProduct product) =>
    GetPaidWalletBehavior(
      product: product,
      walletId: 'wallet-1',
      hideOnHome: false,
      autoSweepEnabled: true,
    );
