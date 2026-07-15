import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/heal_recovered_products_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLightningAddressFacade implements LightningAddressFacade {
  int ensureCalls = 0;
  LightningAddressHealOutcome outcome = const LightningAddressHealOutcome(
    liveness: LightningAddressRegistrationLiveness.live,
  );

  @override
  Future<LightningAddressHealOutcome> ensureRegistrationLive() async {
    ensureCalls++;
    return outcome;
  }

  @override
  Future<PreparedLightningAddressWallet> prepareWallet() =>
      throw UnimplementedError();

  @override
  Future<WalletOwnedLightningAddressRegistration> registerWalletOwned({
    required String nym,
  }) => throw UnimplementedError();

  @override
  Future<LightningAddressStatus> lookupWalletOwnedRegistration() =>
      throw UnimplementedError();

  @override
  Future<LightningAddressStatus> lookupRegistration({
    required String npubHex,
  }) => throw UnimplementedError();
}

void main() {
  test('heals the Lightning Address when its reservation is flagged', () async {
    final facade = _FakeLightningAddressFacade()
      ..outcome = const LightningAddressHealOutcome(
        liveness: LightningAddressRegistrationLiveness.reregistered,
      );
    final usecase = HealRecoveredProductsUsecase(facade);

    final outcome = await usecase.execute({'lightning_address_wallet_seed'});

    expect(facade.ensureCalls, 1);
    expect(
      outcome!.liveness,
      LightningAddressRegistrationLiveness.reregistered,
    );
  });

  test(
    'does not heal for a payment page reservation alone (no client surface)',
    () async {
      final facade = _FakeLightningAddressFacade();
      final usecase = HealRecoveredProductsUsecase(facade);

      final outcome = await usecase.execute({'payment_page_wallet_seed'});

      expect(facade.ensureCalls, 0);
      expect(outcome, isNull);
    },
  );

  test('returns null when there is nothing to heal', () async {
    final facade = _FakeLightningAddressFacade();
    final usecase = HealRecoveredProductsUsecase(facade);

    final outcome = await usecase.execute(const {});

    expect(facade.ensureCalls, 0);
    expect(outcome, isNull);
  });
}
