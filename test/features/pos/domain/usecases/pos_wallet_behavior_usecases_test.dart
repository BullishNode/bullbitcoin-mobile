import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/pos/domain/usecases/get_pos_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/pos/domain/usecases/update_pos_wallet_behavior_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pins reads to the Point of Sale product', () async {
    GetPaidWalletProduct? requested;
    final facade = _facade(
      read: ({only}) async {
        requested = only;
        return [_behavior(GetPaidWalletProduct.pos)];
      },
    );

    final value = await GetPosWalletBehaviorUsecase(
      getPaidSettings: facade,
    ).execute();

    expect(requested, GetPaidWalletProduct.pos);
    expect(value, isA<PosWalletBehaviorFound>());
    expect((value as PosWalletBehaviorFound).behavior.walletId, 'wallet-1');
  });

  test('keeps confirmed absence distinct from an unavailable read', () async {
    final value = await GetPosWalletBehaviorUsecase(
      getPaidSettings: _facade(),
    ).execute();

    expect(value, isA<PosWalletBehaviorAbsent>());
  });

  test('maps a settings read exception to unavailable', () async {
    final value = await GetPosWalletBehaviorUsecase(
      getPaidSettings: _facade(read: ({only}) async => throw Exception('down')),
    ).execute();

    expect(value, isA<PosWalletBehaviorUnavailable>());
  });

  test('does not convert programmer errors into unavailable', () async {
    final future = GetPosWalletBehaviorUsecase(
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

    final saved = await UpdatePosWalletBehaviorUsecase(
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
