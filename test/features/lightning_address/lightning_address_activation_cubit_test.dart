import 'dart:async';

import 'package:bb_mobile/core/wallet/domain/usecases/update_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_error.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_registration.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/activate_wallet_owned_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/deactivate_wallet_owned_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_lightning_address_permanent_name_capability_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_lightning_address_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/lookup_lightning_address_receive_readiness_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/update_lightning_address_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_activation_cubit.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_activation_state.dart';
import 'package:test/test.dart';

void main() {
  group('LightningAddressActivationCubit permanent-name flow', () {
    late _FakeCapability capability;
    late _FakeActivate activate;
    late _FakeDeactivate deactivate;
    late _FakeLookupReadiness lookup;
    late _FakeWalletBehaviors walletBehaviors;
    late _FakeUpdateWalletBehavior updateWalletBehavior;
    late LightningAddressActivationCubit cubit;

    setUp(() {
      capability = _FakeCapability();
      activate = _FakeActivate();
      deactivate = _FakeDeactivate();
      lookup = _FakeLookupReadiness();
      walletBehaviors = _FakeWalletBehaviors();
      updateWalletBehavior = _FakeUpdateWalletBehavior(walletBehaviors);
      final settings = GetPaidSettingsFacade(
        walletBehaviors: walletBehaviors.execute,
        updateWalletBehavior: updateWalletBehavior.execute,
      );
      cubit = LightningAddressActivationCubit(
        capability,
        activate,
        deactivate,
        lookup,
        GetLightningAddressWalletBehaviorUsecase(getPaidSettings: settings),
        UpdateLightningAddressWalletBehaviorUsecase(getPaidSettings: settings),
      );
    });

    tearDown(() => cubit.close());

    test('old server hides claim and management actions', () async {
      capability.supported = false;
      lookup.error = const LightningAddressServerRejectedRequestException(
        code: 'NymNotFound',
        retryable: false,
      );

      await cubit.load();
      cubit.showRegistrationForm();
      cubit.nymChanged('alice');
      await cubit.submit();
      await cubit.activateExisting();
      await cubit.deactivate();

      expect(cubit.state.status, LightningAddressActivationStatus.unsupported);
      expect(cubit.state.permanentNamesSupported, isFalse);
      expect(cubit.state.hasPermanentNym, isFalse);
      expect(activate.nyms, isEmpty);
      expect(deactivate.nyms, isEmpty);
    });

    test('programmer errors during legacy status lookup propagate', () async {
      capability.supported = false;
      lookup.error = StateError('broken readiness adapter');

      await expectLater(cubit.load(), throwsA(isA<StateError>()));
    });

    test('legacy active status stays visible but cannot be managed', () async {
      capability.supported = false;
      lookup.result = const LightningAddressReceiveReadiness(
        registration: LightningAddressStatus(
          nym: 'alice',
          active: true,
          lightningAddress: 'alice@pay2.bull-wallet.com',
        ),
      );

      await cubit.load();
      await cubit.deactivate();

      expect(cubit.state.status, LightningAddressActivationStatus.active);
      expect(cubit.state.nym, 'alice');
      expect(cubit.state.hasPermanentNym, isFalse);
      expect(cubit.state.permanentNamesSupported, isFalse);
      expect(deactivate.nyms, isEmpty);
    });

    test('capability read failure fails closed before lookup', () async {
      capability.error = const LightningAddressNetworkException(
        code: 'Network',
        retryable: true,
      );

      await cubit.load();

      expect(
        cubit.state.failure,
        LightningAddressActivationFailure.capabilityUnavailable,
      );
      expect(cubit.state.permanentNamesSupported, isFalse);
      expect(lookup.calls, 0);
    });

    test('capable unregistered wallet reaches first-claim state', () async {
      await _loadFirstClaim(cubit, lookup);

      expect(cubit.state.status, LightningAddressActivationStatus.idle);
      expect(cubit.state.permanentNamesSupported, isTrue);
      expect(cubit.state.hasPermanentNym, isFalse);
      expect(cubit.state.nym, isEmpty);
    });

    test('keeps an unavailable wallet read distinct from absence', () async {
      walletBehaviors.error = Exception('settings unavailable');

      await cubit.load();

      expect(cubit.state.walletBehavior, isNull);
      expect(cubit.state.walletBehaviorUnavailable, isTrue);
    });

    test('confirmed wallet absence does not report unavailability', () async {
      await cubit.load();

      expect(cubit.state.walletBehavior, isNull);
      expect(cubit.state.walletBehaviorUnavailable, isFalse);
    });

    test(
      'wallet retry preserves nym draft and coalesces duplicate taps',
      () async {
        walletBehaviors.error = Exception('settings unavailable');
        await _loadFirstClaim(cubit, lookup);
        cubit.nymChanged('unsaved-name');

        walletBehaviors
          ..error = null
          ..behaviors = const [
            GetPaidWalletBehavior(
              product: GetPaidWalletProduct.lightningAddress,
              walletId: 'wallet-101',
              hideOnHome: false,
              autoSweepEnabled: false,
            ),
          ];
        final gate = Completer<void>();
        walletBehaviors.gate = gate.future;

        final first = cubit.retryWalletBehavior();
        await Future<void>.delayed(Duration.zero);
        await cubit.retryWalletBehavior();

        expect(walletBehaviors.calls, 2); // initial load + one retry
        expect(cubit.state.nym, 'unsaved-name');
        gate.complete();
        await first;

        expect(cubit.state.nym, 'unsaved-name');
        expect(cubit.state.walletBehavior?.walletId, 'wallet-101');
        expect(cubit.state.walletBehaviorUnavailable, isFalse);
      },
    );

    test('capable lookup without exact policy fields fails closed', () async {
      lookup.result = const LightningAddressReceiveReadiness(
        registration: LightningAddressStatus(nym: 'alice', active: true),
      );

      await cubit.load();

      expect(cubit.state.status, LightningAddressActivationStatus.failure);
      expect(
        cubit.state.failure,
        LightningAddressActivationFailure.capabilityUnavailable,
      );
      expect(cubit.state.permanentNamesSupported, isFalse);
      expect(cubit.state.hasPermanentNym, isFalse);
    });

    test('missing default wallet during lookup remains actionable', () async {
      lookup.error = LightningAddressException.localPreparationFailed(
        code: 'NoDefaultBitcoinWallet',
        retryable: false,
      );

      await cubit.load();

      expect(
        cubit.state.failure,
        LightningAddressActivationFailure.noDefaultBitcoinWallet,
      );
      expect(cubit.state.permanentNamesSupported, isTrue);
      expect(cubit.state.hasPermanentNym, isFalse);
    });

    test('owned nym is reconstructed read-only from server status', () async {
      lookup.result = _permanentReadiness(
        nym: 'alice',
        online: false,
        lightningAddress: 'alice@pay2.bull-wallet.com',
      );

      await cubit.load();
      cubit.nymChanged('bob');
      cubit.showRegistrationForm();
      await cubit.submit();

      expect(cubit.state.status, LightningAddressActivationStatus.inactive);
      expect(cubit.state.nym, 'alice');
      expect(cubit.state.hasPermanentNym, isTrue);
      expect(cubit.state.registeredAddress, 'alice@pay2.bull-wallet.com');
      expect(cubit.state.permanentNameQuota?.used, 1);
      expect(activate.nyms, isEmpty);
    });

    test('missing server-owned address is incomplete, not active', () async {
      lookup.result = _permanentReadiness(
        nym: 'alice',
        online: true,
        lightningAddress: null,
      );

      await cubit.load();

      expect(
        cubit.state.status,
        LightningAddressActivationStatus.addressUnavailable,
      );
      expect(cubit.state.registeredAddress, isNull);
      expect(cubit.state.receiveReady, isFalse);
      expect(cubit.state.hasPermanentNym, isTrue);
    });

    test('first claim normalizes and refreshes authoritative status', () async {
      await _loadFirstClaim(cubit, lookup);
      cubit.nymChanged('  Alice  ');
      lookup.result = _permanentReadiness(
        nym: 'alice',
        online: true,
        lightningAddress: 'alice@pay2.bull-wallet.com',
        autoSweepEnabled: true,
      );

      await cubit.submit();

      expect(activate.nyms, ['alice']);
      expect(cubit.state.status, LightningAddressActivationStatus.active);
      expect(cubit.state.nym, 'alice');
      expect(cubit.state.registeredAddress, 'alice@pay2.bull-wallet.com');
      expect(cubit.state.hasPermanentNym, isTrue);
      expect(cubit.state.autoSweepConfirmed, isTrue);
      expect(lookup.calls, 2, reason: 'initial lookup plus post-claim refresh');
    });

    test(
      'does not convert a post-claim programmer error into UI failure',
      () async {
        await _loadFirstClaim(cubit, lookup);
        cubit.nymChanged('alice');
        walletBehaviors.error = StateError('broken wallet behavior adapter');

        await expectLater(cubit.submit(), throwsA(isA<StateError>()));
        expect(activate.nyms, ['alice']);
      },
    );

    test('invalid and reserved nyms never reach registration', () async {
      await _loadFirstClaim(cubit, lookup);

      cubit.nymChanged('register');
      await cubit.submit();
      expect(
        cubit.state.failure,
        LightningAddressActivationFailure.reservedNym,
      );

      cubit.nymChanged('not valid');
      await cubit.submit();
      expect(cubit.state.failure, LightningAddressActivationFailure.invalidNym);
      expect(activate.nyms, isEmpty);
    });

    test('NameTaken remains a safe first-claim failure', () async {
      await _loadFirstClaim(cubit, lookup);
      cubit.nymChanged('alice');
      activate.error = _activationSubmissionError(
        const LightningAddressServerRejectedRequestException(
          code: 'NameTaken',
          retryable: false,
        ),
      );

      await cubit.submit();

      expect(cubit.state.failure, LightningAddressActivationFailure.nameTaken);
      expect(cubit.state.hasPermanentNym, isFalse);
      expect(cubit.state.nym, 'alice');
    });

    test('NymAlreadyAssigned reloads the server-owned nym', () async {
      await _loadFirstClaim(cubit, lookup);
      cubit.nymChanged('bob');
      activate.error = _activationSubmissionError(
        const LightningAddressServerRejectedRequestException(
          code: 'NymAlreadyAssigned',
          retryable: false,
          ownedNym: 'alice',
        ),
      );
      lookup.result = _permanentReadiness(
        nym: 'alice',
        online: true,
        lightningAddress: 'alice@pay2.bull-wallet.com',
      );

      await cubit.submit();

      expect(activate.nyms, ['bob']);
      expect(cubit.state.status, LightningAddressActivationStatus.active);
      expect(cubit.state.nym, 'alice');
      expect(cubit.state.hasPermanentNym, isTrue);
      expect(
        cubit.state.failure,
        LightningAddressActivationFailure.alreadyAssigned,
      );
    });

    test('turning off deletes the same nym then refreshes offline', () async {
      lookup.result = _permanentReadiness(
        nym: 'alice',
        online: true,
        lightningAddress: 'alice@pay2.bull-wallet.com',
      );
      await cubit.load();
      lookup.result = _permanentReadiness(
        nym: 'alice',
        online: false,
        lightningAddress: 'alice@pay2.bull-wallet.com',
      );

      await cubit.deactivate();

      expect(deactivate.nyms, ['alice']);
      expect(activate.nyms, isEmpty);
      expect(cubit.state.status, LightningAddressActivationStatus.inactive);
      expect(cubit.state.nym, 'alice');
      expect(cubit.state.hasPermanentNym, isTrue);
      expect(cubit.state.registeredAddress, 'alice@pay2.bull-wallet.com');
    });

    test('turning on posts the same nym then refreshes online', () async {
      lookup.result = _permanentReadiness(
        nym: 'alice',
        online: false,
        lightningAddress: 'alice@pay2.bull-wallet.com',
      );
      await cubit.load();
      lookup.result = _permanentReadiness(
        nym: 'alice',
        online: true,
        lightningAddress: 'alice@pay2.bull-wallet.com',
      );

      await cubit.activateExisting();

      expect(activate.nyms, ['alice']);
      expect(deactivate.nyms, isEmpty);
      expect(cubit.state.status, LightningAddressActivationStatus.active);
      expect(cubit.state.nym, 'alice');
    });

    test('uncertain toggle keeps prior state until a refresh', () async {
      lookup.result = _permanentReadiness(
        nym: 'alice',
        online: true,
        lightningAddress: 'alice@pay2.bull-wallet.com',
      );
      await cubit.load();
      deactivate.error = const LightningAddressNetworkException(
        code: 'Network',
        retryable: true,
      );

      await cubit.deactivate();

      expect(cubit.state.status, LightningAddressActivationStatus.active);
      expect(
        cubit.state.failure,
        LightningAddressActivationFailure.toggleUncertain,
      );
      expect(cubit.state.onlineSaving, isFalse);
    });

    test(
      'successful claim with failed refresh is uncertain and locked',
      () async {
        await _loadFirstClaim(cubit, lookup);
        cubit.nymChanged('alice');
        lookup.error = const LightningAddressNetworkException(
          code: 'Network',
          retryable: true,
        );

        await cubit.submit();

        expect(activate.nyms, ['alice']);
        expect(cubit.state.hasPermanentNym, isTrue);
        expect(
          cubit.state.failure,
          LightningAddressActivationFailure.submissionUncertain,
        );
        cubit.nymChanged('bob');
        expect(cubit.state.nym, 'alice');
      },
    );

    test('a claim the server never answered is not called uncertain', () async {
      await _loadFirstClaim(cubit, lookup);
      cubit.nymChanged('alice');
      activate
          .error = WalletOwnedLightningAddressActivationException.fromRegistration(
        WalletOwnedLightningAddressRegistrationException.registrationSubmission(
          cause: const LightningAddressTimeoutException(
            code: 'Timeout',
            retryable: true,
          ),
          walletId: 'wallet-101',
          walletCreated: false,
        ),
      );

      await cubit.submit();

      // Nothing came back, so there is no half-known outcome to check — the nym
      // is unclaimed and the nym typed stays available to retry with.
      expect(
        cubit.state.failure,
        LightningAddressActivationFailure.noServerResponse,
      );
      expect(cubit.state.hasPermanentNym, isFalse);
      expect(cubit.state.nym, 'alice');
    });

    test('an unreachable server reads the same as a timeout', () async {
      await _loadFirstClaim(cubit, lookup);
      cubit.nymChanged('alice');
      activate
          .error = WalletOwnedLightningAddressActivationException.fromRegistration(
        WalletOwnedLightningAddressRegistrationException.registrationSubmission(
          cause: const LightningAddressNetworkException(
            code: 'Network',
            retryable: true,
          ),
          walletId: 'wallet-101',
          walletCreated: false,
        ),
      );

      await cubit.submit();

      expect(
        cubit.state.failure,
        LightningAddressActivationFailure.noServerResponse,
      );
    });

    test('a garbled server answer stays genuinely uncertain', () async {
      await _loadFirstClaim(cubit, lookup);
      cubit.nymChanged('alice');
      activate
          .error = WalletOwnedLightningAddressActivationException.fromRegistration(
        WalletOwnedLightningAddressRegistrationException.registrationSubmission(
          cause: const LightningAddressInvalidServerResponseException(
            code: 'InvalidServerResponse',
            retryable: true,
          ),
          walletId: 'wallet-101',
          walletCreated: false,
        ),
      );

      await cubit.submit();

      expect(
        cubit.state.failure,
        LightningAddressActivationFailure.submissionUncertain,
      );
    });

    test(
      'active local setup failure preserves online ownership state',
      () async {
        lookup.result = _permanentReadiness(
          nym: 'alice',
          online: true,
          lightningAddress: 'alice@pay2.bull-wallet.com',
          localSetupFailed: true,
          localSetupRetryable: true,
        );

        await cubit.load();

        expect(
          cubit.state.status,
          LightningAddressActivationStatus.activeLocalSetupFailed,
        );
        expect(cubit.state.hasPermanentNym, isTrue);
        expect(cubit.state.localSetupRetryable, isTrue);
        expect(cubit.state.receiveReady, isFalse);
      },
    );

    test(
      'missing default wallet remains actionable before submission',
      () async {
        await _loadFirstClaim(cubit, lookup);
        cubit.nymChanged('alice');
        activate.error =
            WalletOwnedLightningAddressActivationException.fromRegistration(
              WalletOwnedLightningAddressRegistrationException.localPreparation(
                cause: LightningAddressException.localPreparationFailed(
                  code: 'NoDefaultBitcoinWallet',
                  retryable: false,
                ),
              ),
            );

        await cubit.submit();

        expect(
          cubit.state.failure,
          LightningAddressActivationFailure.noDefaultBitcoinWallet,
        );
        expect(cubit.state.hasPermanentNym, isFalse);
      },
    );

    test('local wallet controls remain independent of server naming', () async {
      capability.supported = false;
      lookup.error = const LightningAddressServerRejectedRequestException(
        code: 'NymNotFound',
        retryable: false,
      );
      walletBehaviors.behaviors = const [
        GetPaidWalletBehavior(
          product: GetPaidWalletProduct.lightningAddress,
          walletId: 'wallet-101',
          hideOnHome: true,
          autoSweepEnabled: true,
        ),
      ];

      await cubit.load();

      expect(cubit.state.status, LightningAddressActivationStatus.unsupported);
      expect(cubit.state.walletBehavior?.walletId, 'wallet-101');
    });

    /// A wallet that keeps its funds must stay countable on the home list, so
    /// hide-on-home only holds while auto-sweep empties the wallet.
    Future<void> loadWithBehavior({
      required bool hideOnHome,
      required bool autoSweepEnabled,
    }) async {
      capability.supported = false;
      lookup.error = const LightningAddressServerRejectedRequestException(
        code: 'NymNotFound',
        retryable: false,
      );
      walletBehaviors.behaviors = [
        GetPaidWalletBehavior(
          product: GetPaidWalletProduct.lightningAddress,
          walletId: 'wallet-101',
          hideOnHome: hideOnHome,
          autoSweepEnabled: autoSweepEnabled,
        ),
      ];
      await cubit.load();
    }

    test('turning auto-sweep off unhides the wallet', () async {
      await loadWithBehavior(hideOnHome: true, autoSweepEnabled: true);

      await cubit.updateWalletBehavior(
        walletId: 'wallet-101',
        autoSweepEnabled: false,
      );

      expect(updateWalletBehavior.calls.single.autoSweepEnabled, isFalse);
      expect(cubit.state.walletBehavior?.autoSweepEnabled, isFalse);
      expect(cubit.state.walletBehavior?.hideOnHome, isFalse);
    });

    test('hide on home cannot be turned on while auto-sweep is off', () async {
      await loadWithBehavior(hideOnHome: false, autoSweepEnabled: false);

      await cubit.updateWalletBehavior(
        walletId: 'wallet-101',
        hideOnHome: true,
      );

      expect(cubit.state.walletBehavior?.hideOnHome, isFalse);
    });

    test('unhiding is allowed even with auto-sweep off', () async {
      await loadWithBehavior(hideOnHome: true, autoSweepEnabled: false);

      await cubit.updateWalletBehavior(
        walletId: 'wallet-101',
        hideOnHome: false,
      );

      expect(cubit.state.walletBehavior?.hideOnHome, isFalse);
    });
  });
}

Future<void> _loadFirstClaim(
  LightningAddressActivationCubit cubit,
  _FakeLookupReadiness lookup,
) async {
  lookup.error = const LightningAddressServerRejectedRequestException(
    code: 'NymNotFound',
    retryable: false,
  );
  await cubit.load();
  lookup.error = null;
}

LightningAddressReceiveReadiness _permanentReadiness({
  required String nym,
  required bool online,
  String? lightningAddress,
  bool autoSweepEnabled = false,
  bool localSetupFailed = false,
  bool localSetupRetryable = false,
}) {
  return LightningAddressReceiveReadiness(
    registration: LightningAddressStatus(
      nym: nym,
      active: online,
      lightningAddress: lightningAddress,
      permanentNameStatus: LightningAddressPermanentNameStatus(
        nym: nym,
        lightningAddressOnline: online,
        quota: const LightningAddressPermanentNameQuota(
          used: 1,
          cap: 1,
          remaining: 0,
        ),
      ),
    ),
    autoSweepEnabled: autoSweepEnabled,
    localSetupFailed: localSetupFailed,
    localSetupRetryable: localSetupRetryable,
  );
}

WalletOwnedLightningAddressActivationException _activationSubmissionError(
  LightningAddressException cause,
) {
  return WalletOwnedLightningAddressActivationException.fromRegistration(
    WalletOwnedLightningAddressRegistrationException.registrationSubmission(
      cause: cause,
      walletId: 'wallet-101',
      walletCreated: false,
    ),
  );
}

class _FakeCapability
    implements GetLightningAddressPermanentNameCapabilityUsecase {
  bool supported = true;
  Object? error;
  int calls = 0;

  @override
  Future<bool> execute() async {
    calls += 1;
    final error = this.error;
    if (error != null) throw error;
    return supported;
  }
}

class _FakeActivate implements ActivateWalletOwnedLightningAddressUsecase {
  final nyms = <String>[];
  Object? error;

  @override
  Future<LightningAddressRegistration> execute({required String nym}) async {
    nyms.add(nym);
    final error = this.error;
    if (error != null) throw error;
    return LightningAddressRegistration(
      nym: nym,
      lightningAddress: '$nym@pay2.bull-wallet.com',
    );
  }
}

class _FakeDeactivate implements DeactivateWalletOwnedLightningAddressUsecase {
  final nyms = <String>[];
  Object? error;

  @override
  Future<void> execute({required String nym}) async {
    nyms.add(nym);
    final error = this.error;
    if (error != null) throw error;
  }
}

class _FakeLookupReadiness
    implements LookupLightningAddressReceiveReadinessUsecase {
  int calls = 0;
  LightningAddressReceiveReadiness result = _permanentReadiness(
    nym: 'alice',
    online: true,
  );
  Object? error;

  @override
  Future<LightningAddressReceiveReadiness> execute() async {
    calls += 1;
    final error = this.error;
    if (error != null) throw error;
    return result;
  }
}

/// Stands in for the wallet-behavior read the facade callback is wired to.
class _FakeWalletBehaviors {
  List<GetPaidWalletBehavior> behaviors = const [];
  Object? error;
  Future<void>? gate;
  int calls = 0;

  Future<List<GetPaidWalletBehavior>> execute({
    GetPaidWalletProduct? only,
  }) async {
    calls += 1;
    final currentGate = gate;
    if (currentGate != null) await currentGate;
    final currentError = error;
    if (currentError != null) throw currentError;
    if (only == null) return behaviors;
    return behaviors.where((behavior) => behavior.product == only).toList();
  }
}

/// Stands in for the store, applying the same auto-sweep / hide-on-home rule
/// `WalletRepository.updateWalletBehavior` applies, so what the cubit reads back
/// after a write is what the device would have persisted.
class _FakeUpdateWalletBehavior implements UpdateWalletBehaviorUsecase {
  _FakeUpdateWalletBehavior(this._store);
  final _FakeWalletBehaviors _store;
  final List<({String walletId, bool? hideOnHome, bool? autoSweepEnabled})>
  calls = [];

  @override
  Future<void> execute({
    required String walletId,
    bool? hideOnHome,
    bool? autoSweepEnabled,
  }) async {
    calls.add((
      walletId: walletId,
      hideOnHome: hideOnHome,
      autoSweepEnabled: autoSweepEnabled,
    ));
    _store.behaviors = _store.behaviors
        .map(
          (behavior) => behavior.walletId == walletId
              ? behavior.withRequestedChange(
                  hideOnHome: hideOnHome,
                  autoSweepEnabled: autoSweepEnabled,
                )
              : behavior,
        )
        .toList();
  }
}
