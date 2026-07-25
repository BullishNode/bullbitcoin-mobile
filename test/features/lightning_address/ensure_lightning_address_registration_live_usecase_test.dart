import 'package:bb_mobile/features/lightning_address/domain/lightning_address_error.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_registration.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_registration_liveness.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_wallet_registration.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/ensure_lightning_address_registration_live_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/lookup_wallet_owned_lightning_address_registration_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_wallet_owned_lightning_address_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps a live registration without re-registering', () async {
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
    expect(outcome.nym, 'alice');
    expect(register.recoveryNyms, isEmpty);
  });

  test('re-registers an inactive nym as recovery-originated', () async {
    final register = _FakeRegister();
    final usecase = EnsureLightningAddressRegistrationLiveUsecase(
      _FakeLookup(
        status: const LightningAddressStatus(nym: 'alice', active: false),
      ),
      register,
    );

    final outcome = await usecase.execute();

    expect(outcome.liveness, LightningAddressRegistrationLiveness.reregistered);
    expect(register.recoveryNyms, ['alice']);
    expect(register.normalNyms, isEmpty);
  });

  test('does not guess a nym when the registration is absent', () async {
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
    expect(register.recoveryNyms, isEmpty);
  });

  test('treats other lookup failures as unreachable', () async {
    final usecase = EnsureLightningAddressRegistrationLiveUsecase(
      _FakeLookup(
        error: const LightningAddressNetworkException(
          code: 'NetworkError',
          retryable: true,
        ),
      ),
      _FakeRegister(),
    );

    final outcome = await usecase.execute();

    expect(outcome.liveness, LightningAddressRegistrationLiveness.unreachable);
  });

  test('surfaces a failed silent re-registration for later retry', () async {
    final register = _FakeRegister()..error = StateError('server');
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
    expect(outcome.nym, 'alice');
  });

  test(
    'does not start registration after a lookup exhausts the deadline',
    () async {
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
      expect(register.recoveryNyms, isEmpty);
    },
  );
}

final class _FakeLookup
    implements LookupWalletOwnedLightningAddressRegistrationUsecase {
  final LightningAddressStatus? status;
  final Object? error;
  final Duration delay;

  const _FakeLookup({this.status, this.error, this.delay = Duration.zero});

  @override
  Future<LightningAddressStatus> execute() async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final error = this.error;
    if (error != null) throw error;
    return status!;
  }
}

final class _FakeRegister
    implements RegisterWalletOwnedLightningAddressUsecase {
  final normalNyms = <String>[];
  final recoveryNyms = <String>[];
  Object? error;

  @override
  Future<WalletOwnedLightningAddressRegistration> execute({
    required String nym,
  }) {
    normalNyms.add(nym);
    return _result(nym);
  }

  @override
  Future<WalletOwnedLightningAddressRegistration> executeFromRecovery({
    required String nym,
  }) {
    recoveryNyms.add(nym);
    return _result(nym);
  }

  Future<WalletOwnedLightningAddressRegistration> _result(String nym) async {
    final error = this.error;
    if (error != null) throw error;
    return WalletOwnedLightningAddressRegistration(
      registration: LightningAddressRegistration(
        nym: nym,
        lightningAddress: '$nym@example.invalid',
      ),
      walletId: 'lightning-wallet',
      walletCreated: false,
    );
  }
}
