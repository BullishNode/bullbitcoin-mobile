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
  _FakeLookup({this.status, this.error, this.delay = Duration.zero});

  LightningAddressStatus? status;
  Object? error;
  final Duration delay;

  @override
  Future<LightningAddressStatus> execute() async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final error = this.error;
    if (error != null) throw error;
    return status!;
  }
}

class _FakeRegister implements RegisterWalletOwnedLightningAddressUsecase {
  _FakeRegister({this.error});

  Object? error;
  final List<String> nyms = [];
  final List<bool> publishFlags = [];

  @override
  Future<WalletOwnedLightningAddressRegistration> execute({
    required String nym,
  }) => _record(nym, publishBackupSnapshot: true);

  @override
  Future<WalletOwnedLightningAddressRegistration> executeFromRecovery({
    required String nym,
  }) => _record(nym, publishBackupSnapshot: false);

  Future<WalletOwnedLightningAddressRegistration> _record(
    String nym, {
    required bool publishBackupSnapshot,
  }) async {
    nyms.add(nym);
    publishFlags.add(publishBackupSnapshot);
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
  test('a live registration reports live and never re-registers', () async {
    final register = _FakeRegister();
    final usecase = EnsureLightningAddressRegistrationLiveUsecase(
      _FakeLookup(
        status: const LightningAddressStatus(
          nym: 'alice',
          active: true,
          lightningAddress: 'alice@example.invalid',
        ),
      ),
      register,
    );

    final outcome = await usecase.execute();

    expect(outcome.liveness, LightningAddressRegistrationLiveness.live);
    expect(register.nyms, isEmpty);
  });

  test('an inactive legacy registration silently re-registers', () async {
    final register = _FakeRegister();
    final usecase = EnsureLightningAddressRegistrationLiveUsecase(
      _FakeLookup(
        status: const LightningAddressStatus(nym: 'alice', active: false),
      ),
      register,
    );

    final outcome = await usecase.execute();

    expect(outcome.liveness, LightningAddressRegistrationLiveness.reregistered);
    expect(register.nyms, ['alice']);
    expect(register.publishFlags, [false]);
  });

  test('an offline permanent name never triggers a write', () async {
    final register = _FakeRegister();
    final usecase = EnsureLightningAddressRegistrationLiveUsecase(
      _FakeLookup(
        status: const LightningAddressStatus(
          nym: 'alice',
          active: false,
          permanentNameStatus: LightningAddressPermanentNameStatus(
            nym: 'alice',
            lightningAddressOnline: false,
            quota: LightningAddressPermanentNameQuota(
              used: 1,
              cap: 1,
              remaining: 0,
            ),
          ),
        ),
      ),
      register,
    );

    final outcome = await usecase.execute();

    expect(
      outcome.liveness,
      LightningAddressRegistrationLiveness.needsReactivation,
    );
    expect(outcome.nym, 'alice');
    expect(register.nyms, isEmpty);
  });

  test('a rejected re-register needs re-activation', () async {
    final register = _FakeRegister(
      error:
          WalletOwnedLightningAddressRegistrationException.registrationSubmission(
            cause: const LightningAddressServerRejectedRequestException(
              code: 'NymTaken',
              retryable: false,
            ),
            walletId: 'la-wallet',
            walletCreated: false,
          ),
    );
    final usecase = EnsureLightningAddressRegistrationLiveUsecase(
      _FakeLookup(
        status: const LightningAddressStatus(nym: 'alice', active: false),
      ),
      register,
    );

    final outcome = await usecase.execute();

    expect(
      outcome.liveness,
      LightningAddressRegistrationLiveness.needsReactivation,
    );
    expect(register.nyms, ['alice']);
  });

  test('a NymNotFound lookup needs re-activation without a write', () async {
    final register = _FakeRegister();
    final usecase = EnsureLightningAddressRegistrationLiveUsecase(
      _FakeLookup(
        error: const LightningAddressServerRejectedRequestException(
          code: 'NymNotFound',
          retryable: false,
        ),
      ),
      register,
    );

    final outcome = await usecase.execute();

    expect(
      outcome.liveness,
      LightningAddressRegistrationLiveness.needsReactivation,
    );
    expect(register.nyms, isEmpty);
  });

  test('read-only mode flags a lapsed legacy registration for reactivation '
      'without re-registering', () async {
    final register = _FakeRegister();
    final usecase = EnsureLightningAddressRegistrationLiveUsecase(
      _FakeLookup(
        status: const LightningAddressStatus(nym: 'alice', active: false),
      ),
      register,
    );

    final outcome = await usecase.execute(allowReregister: false);

    expect(
      outcome.liveness,
      LightningAddressRegistrationLiveness.needsReactivation,
    );
    expect(outcome.nym, 'alice');
    // The single write this check can make is suppressed in read-only mode.
    expect(register.nyms, isEmpty);
    expect(register.publishFlags, isEmpty);
  });

  test('a network lookup failure reports unreachable', () async {
    final register = _FakeRegister();
    final usecase = EnsureLightningAddressRegistrationLiveUsecase(
      _FakeLookup(
        error: const LightningAddressNetworkException(
          code: 'NetworkError',
          retryable: true,
        ),
      ),
      register,
    );

    final outcome = await usecase.execute();

    expect(outcome.liveness, LightningAddressRegistrationLiveness.unreachable);
    expect(register.nyms, isEmpty);
  });

  test('deadline prevents a late recovery write', () async {
    final register = _FakeRegister();
    final usecase = EnsureLightningAddressRegistrationLiveUsecase(
      _FakeLookup(
        status: const LightningAddressStatus(nym: 'alice', active: false),
        delay: const Duration(milliseconds: 20),
      ),
      register,
    );

    final outcome = await usecase.execute(
      deadline: DateTime.now().add(const Duration(milliseconds: 5)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(outcome.liveness, LightningAddressRegistrationLiveness.timedOut);
    expect(register.nyms, isEmpty);
  });
}
