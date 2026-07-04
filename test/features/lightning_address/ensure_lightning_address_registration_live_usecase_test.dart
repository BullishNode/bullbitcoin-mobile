import 'package:bb_mobile/features/lightning_address/domain/lightning_address_error.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_registration.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_registration_liveness.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_wallet_registration.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/ensure_lightning_address_registration_live_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/lookup_wallet_owned_lightning_address_registration_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_wallet_owned_lightning_address_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLookup
    implements LookupWalletOwnedLightningAddressRegistrationUsecase {
  _FakeLookup({this.status, this.error});

  LightningAddressStatus? status;
  Object? error;
  int calls = 0;

  @override
  Future<LightningAddressStatus> execute() async {
    calls++;
    final error = this.error;
    if (error != null) throw error;
    return status!;
  }
}

class _FakeRegister implements RegisterWalletOwnedLightningAddressUsecase {
  _FakeRegister({this.error});

  Object? error;
  final List<String> nyms = [];

  @override
  Future<WalletOwnedLightningAddressRegistration> execute({
    required String nym,
  }) async {
    nyms.add(nym);
    final error = this.error;
    if (error != null) throw error;
    return WalletOwnedLightningAddressRegistration(
      registration: LightningAddressRegistration(
        nym: nym,
        lightningAddress: '$nym@example.invalid',
      ),
      walletId: 'la-wallet',
      walletCreated: false,
    );
  }
}

void main() {
  test('a live registration reports live and never re-registers (DG-3)',
      () async {
    final register = _FakeRegister();
    final usecase = EnsureLightningAddressRegistrationLiveUsecase(
      lookup: _FakeLookup(
        status: const LightningAddressStatus(
          nym: 'alice',
          active: true,
          lightningAddress: 'alice@example.invalid',
        ),
      ),
      register: register,
    );

    final outcome = await usecase.execute();

    expect(outcome.liveness, LightningAddressRegistrationLiveness.live);
    expect(register.nyms, isEmpty);
  });

  test('an inactive registration silently re-registers with the same nym',
      () async {
    final register = _FakeRegister();
    final usecase = EnsureLightningAddressRegistrationLiveUsecase(
      lookup: _FakeLookup(
        status: const LightningAddressStatus(nym: 'alice', active: false),
      ),
      register: register,
    );

    final outcome = await usecase.execute();

    expect(outcome.liveness, LightningAddressRegistrationLiveness.reregistered);
    expect(register.nyms, ['alice']);
  });

  test('a rejected re-register (e.g. NymTaken) needs re-activation', () async {
    final register = _FakeRegister(
      error: WalletOwnedLightningAddressRegistrationException.registrationSubmission(
        cause: const LightningAddressServerRejectedRequestException(
          code: 'NymTaken',
          retryable: false,
        ),
        walletId: 'la-wallet',
        walletCreated: false,
      ),
    );
    final usecase = EnsureLightningAddressRegistrationLiveUsecase(
      lookup: _FakeLookup(
        status: const LightningAddressStatus(nym: 'alice', active: false),
      ),
      register: register,
    );

    final outcome = await usecase.execute();

    expect(
      outcome.liveness,
      LightningAddressRegistrationLiveness.needsReactivation,
    );
    expect(register.nyms, ['alice']);
  });

  test('a NymNotFound lookup needs re-activation and never re-registers',
      () async {
    final register = _FakeRegister();
    final usecase = EnsureLightningAddressRegistrationLiveUsecase(
      lookup: _FakeLookup(
        error: const LightningAddressServerRejectedRequestException(
          code: 'NymNotFound',
          retryable: false,
        ),
      ),
      register: register,
    );

    final outcome = await usecase.execute();

    expect(
      outcome.liveness,
      LightningAddressRegistrationLiveness.needsReactivation,
    );
    expect(register.nyms, isEmpty);
  });

  test('a network lookup failure reports unreachable and never heals blindly',
      () async {
    final register = _FakeRegister();
    final usecase = EnsureLightningAddressRegistrationLiveUsecase(
      lookup: _FakeLookup(
        error: const LightningAddressNetworkException(
          code: 'NetworkError',
          retryable: true,
        ),
      ),
      register: register,
    );

    final outcome = await usecase.execute();

    expect(outcome.liveness, LightningAddressRegistrationLiveness.unreachable);
    expect(register.nyms, isEmpty);
  });
}
