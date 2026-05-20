import 'dart:async';

import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/features/lightning_address/data/datasources/lightning_address_settings_datasource.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/primitives/nostr_publish_status.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/clear_lightning_address_nostr_profile_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/delete_lightning_address_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/lookup_lightning_address_status_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/publish_lightning_address_nostr_profile_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/entities/lookup_result.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/nym_quota.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/previous_nym.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockExternalReceiveWalletsFacade extends Mock
    implements ExternalReceiveWalletsFacade {}

class _MockRegister extends Mock implements RegisterLightningAddressUsecase {}

class _MockDelete extends Mock implements DeleteLightningAddressUsecase {}

class _MockLookupStatus extends Mock
    implements LookupLightningAddressStatusUsecase {}

class _MockPublishProfile extends Mock
    implements PublishLightningAddressNostrProfileUsecase {}

class _MockClearProfile extends Mock
    implements ClearLightningAddressNostrProfileUsecase {}

class _MockPayService extends Mock implements PayServicePort {}

class _MockSettings extends Mock
    implements LightningAddressSettingsDatasource {}

void main() {
  setUpAll(() {
    registerFallbackValue(Environment.mainnet);
    registerFallbackValue(ExternalReceiveWalletPurpose.lightningAddress);
    registerFallbackValue(NostrPublishStatus.success);
  });

  late _MockExternalReceiveWalletsFacade externalReceiveWallets;
  late _MockRegister register;
  late _MockDelete delete;
  late _MockLookupStatus lookupStatus;
  late _MockPublishProfile publishProfile;
  late _MockClearProfile clearProfile;
  late _MockPayService payService;
  late _MockSettings settings;

  setUp(() {
    externalReceiveWallets = _MockExternalReceiveWalletsFacade();
    register = _MockRegister();
    delete = _MockDelete();
    lookupStatus = _MockLookupStatus();
    publishProfile = _MockPublishProfile();
    clearProfile = _MockClearProfile();
    payService = _MockPayService();
    settings = _MockSettings();
    when(() => settings.setNostrPublishOutcome(any())).thenAnswer((_) async {});
    when(() => settings.clearNostrPublishOutcome()).thenAnswer((_) async {});
    when(() => settings.getNostrPublishOutcome()).thenAnswer((_) async => null);
    when(
      () => publishProfile.execute(nym: any(named: 'nym')),
    ).thenAnswer((_) async {});
    when(() => clearProfile.execute()).thenAnswer((_) async {});
  });

  LightningAddressCubit build() => LightningAddressCubit(
    externalReceiveWallets: externalReceiveWallets,
    register: register,
    delete: delete,
    lookupStatus: lookupStatus,
    publishProfile: publishProfile,
    clearProfile: clearProfile,
    payService: payService,
    settings: settings,
  );

  void stubRegisterOk({NymQuota quota = const NymQuota(used: 1, cap: 3)}) {
    when(
      () => register.execute(
        nym: any(named: 'nym'),
        environment: any(named: 'environment'),
      ),
    ).thenAnswer((_) async => (address: 'alice@bullpay.ca', quota: quota));
  }

  void stubDeleteOk({NymQuota quota = const NymQuota(used: 1, cap: 3)}) {
    when(
      () => delete.execute(nym: any(named: 'nym')),
    ).thenAnswer((_) async => quota);
  }

  test('registerNym is reentrancy-guarded (I-2)', () async {
    stubRegisterOk();

    final cubit = build();
    await Future.wait([
      cubit.registerNym('alice', Environment.mainnet),
      cubit.registerNym('alice', Environment.mainnet),
    ]);

    verify(
      () => register.execute(
        nym: any(named: 'nym'),
        environment: any(named: 'environment'),
      ),
    ).called(1);
    await cubit.close();
  });

  test('deleteAddress is reentrancy-guarded (I-2)', () async {
    stubRegisterOk();
    stubDeleteOk();

    final cubit = build();
    await cubit.registerNym(
      'alice',
      Environment.mainnet,
      publishOnNostr: false,
    );
    await Future.wait([cubit.deleteAddress(), cubit.deleteAddress()]);

    verify(() => delete.execute(nym: 'alice')).called(1);
    await cubit.close();
  });

  test('registerNym ignores empty nym', () async {
    final cubit = build();
    await cubit.registerNym('', Environment.mainnet);
    verifyNever(
      () => register.execute(
        nym: any(named: 'nym'),
        environment: any(named: 'environment'),
      ),
    );
    expect(cubit.state.registering, isFalse);
    await cubit.close();
  });

  test('register generic failure uses friendly state.error copy', () async {
    when(
      () => register.execute(
        nym: any(named: 'nym'),
        environment: any(named: 'environment'),
      ),
    ).thenThrow(Exception('NymTaken'));

    final cubit = build();
    await cubit.registerNym('alice', Environment.mainnet);

    expect(cubit.state.registering, isFalse);
    expect(cubit.state.error, 'Something went wrong. Please try again.');
    expect(cubit.state.lightningAddress, isNull);
    await cubit.close();
  });

  test('register unavailable nym uses curated validation copy', () async {
    when(
      () => register.execute(
        nym: any(named: 'nym'),
        environment: any(named: 'environment'),
      ),
    ).thenThrow(
      LightningAddressRegistrationException('This nym is not available'),
    );

    final cubit = build();
    await cubit.registerNym('alice', Environment.mainnet);

    expect(cubit.state.registering, isFalse);
    expect(cubit.state.error, 'This nym is not available');
    await cubit.close();
  });

  test('register server reason does not leak to state.error', () async {
    when(
      () => register.execute(
        nym: any(named: 'nym'),
        environment: any(named: 'environment'),
      ),
    ).thenThrow(
      LightningAddressRegistrationException('AuthError: bad signature'),
    );

    final cubit = build();
    await cubit.registerNym('alice', Environment.mainnet);

    expect(cubit.state.registering, isFalse);
    expect(cubit.state.error, isNot(contains('bad signature')));
    expect(
      cubit.state.error,
      'Could not update Lightning Address. Please try again.',
    );
    await cubit.close();
  });

  test('register surfaces network rate limit message', () async {
    const message =
        'Too many distinct wallets have used this service from this network. '
        'Retry later, or switch networks.';
    when(
      () => register.execute(
        nym: any(named: 'nym'),
        environment: any(named: 'environment'),
      ),
    ).thenThrow(LightningAddressRegistrationException(message));

    final cubit = build();
    await cubit.registerNym('alice', Environment.mainnet);

    expect(cubit.state.registering, isFalse);
    expect(cubit.state.error, message);
    await cubit.close();
  });

  test(
    'registerNym emits success + nostrPublishStatus.pending immediately, '
    'then transitions to .success when the background publish settles',
    () async {
      stubRegisterOk(quota: const NymQuota(used: 2, cap: 3));
      final completer = Completer<void>();
      when(
        () => publishProfile.execute(nym: any(named: 'nym')),
      ).thenAnswer((_) => completer.future);

      final cubit = build();
      await cubit.registerNym('alice', Environment.mainnet);

      // Synchronous-after-server-success snapshot: address visible, pending
      // status, registering already false, publish not yet settled.
      expect(cubit.state.lightningAddress, 'alice@bullpay.ca');
      expect(cubit.state.nostrPublishStatus, NostrPublishStatus.pending);
      expect(cubit.state.registering, isFalse);

      completer.complete();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.nostrPublishStatus, NostrPublishStatus.success);
      verify(
        () => settings.setNostrPublishOutcome(NostrPublishStatus.success),
      ).called(1);
      await cubit.close();
    },
  );

  test('background publish failure transitions pending → failed', () async {
    stubRegisterOk();
    when(
      () => publishProfile.execute(nym: any(named: 'nym')),
    ).thenThrow(LightningAddressNostrPublishFailedException('no relays'));

    final cubit = build();
    await cubit.registerNym('alice', Environment.mainnet);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.nostrPublishStatus, NostrPublishStatus.failed);
    verify(
      () => settings.setNostrPublishOutcome(NostrPublishStatus.failed),
    ).called(1);
    await cubit.close();
  });

  test('republishOnNostr flips failed → pending → success on retry', () async {
    stubRegisterOk();
    final cubit = build();

    when(
      () => publishProfile.execute(nym: any(named: 'nym')),
    ).thenThrow(LightningAddressNostrPublishFailedException('no relays'));
    await cubit.registerNym('alice', Environment.mainnet);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.nostrPublishStatus, NostrPublishStatus.failed);

    final completer = Completer<void>();
    when(
      () => publishProfile.execute(nym: any(named: 'nym')),
    ).thenAnswer((_) => completer.future);

    await cubit.republishOnNostr();
    expect(cubit.state.nostrPublishStatus, NostrPublishStatus.pending);

    completer.complete();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.nostrPublishStatus, NostrPublishStatus.success);
    await cubit.close();
  });

  test('publishOnNostr=false skips the publish task entirely', () async {
    stubRegisterOk();

    final cubit = build();
    await cubit.registerNym(
      'alice',
      Environment.mainnet,
      publishOnNostr: false,
    );

    expect(cubit.state.nostrPublishStatus, NostrPublishStatus.none);
    verifyNever(() => publishProfile.execute(nym: any(named: 'nym')));
    verify(
      () => settings.setNostrPublishOutcome(NostrPublishStatus.none),
    ).called(1);
    await cubit.close();
  });

  test(
    'persisted Nostr opt-out does not auto-publish on cold status check',
    () async {
      when(
        () => externalReceiveWallets.get(
          environment: any(named: 'environment'),
          purpose: any(named: 'purpose'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => payService.getStoredAddress(),
      ).thenAnswer((_) async => 'alice@bullpay.ca');
      when(
        () => settings.getNostrPublishOutcome(),
      ).thenAnswer((_) async => NostrPublishStatus.none);

      final cubit = build();
      await cubit.checkStatus(Environment.mainnet);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.lightningAddress, 'alice@bullpay.ca');
      expect(cubit.state.nostrPublishStatus, NostrPublishStatus.none);
      verifyNever(() => publishProfile.execute(nym: any(named: 'nym')));
      await cubit.close();
    },
  );

  test(
    'unknown persisted Nostr state does not auto-publish on cold status check',
    () async {
      when(
        () => externalReceiveWallets.get(
          environment: any(named: 'environment'),
          purpose: any(named: 'purpose'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => payService.getStoredAddress(),
      ).thenAnswer((_) async => 'alice@bullpay.ca');
      when(
        () => settings.getNostrPublishOutcome(),
      ).thenAnswer((_) async => null);

      final cubit = build();
      await cubit.checkStatus(Environment.mainnet);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.lightningAddress, 'alice@bullpay.ca');
      expect(cubit.state.nostrPublishStatus, NostrPublishStatus.none);
      verifyNever(() => publishProfile.execute(nym: any(named: 'nym')));
      await cubit.close();
    },
  );

  test(
    'opt-out registration fails closed when preference cannot persist',
    () async {
      stubRegisterOk();
      when(
        () => settings.setNostrPublishOutcome(NostrPublishStatus.none),
      ).thenThrow(Exception('hive closed'));

      final cubit = build();
      await cubit.registerNym(
        'alice',
        Environment.mainnet,
        publishOnNostr: false,
      );

      expect(cubit.state.registering, isFalse);
      expect(
        cubit.state.error,
        'Could not save Nostr preference. Please try again.',
      );
      expect(cubit.state.lightningAddress, isNull);
      verifyNever(
        () => register.execute(
          nym: any(named: 'nym'),
          environment: any(named: 'environment'),
        ),
      );
      verifyNever(() => publishProfile.execute(nym: any(named: 'nym')));
      await cubit.close();
    },
  );

  test(
    'successful delete prepends deactivated nym to previousNyms + clears persisted outcome',
    () async {
      stubRegisterOk();
      stubDeleteOk();

      final cubit = build();
      await cubit.registerNym('alice', Environment.mainnet);
      await cubit.deleteAddress();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.previousNyms.length, 1);
      expect(cubit.state.previousNyms.first.nym, 'alice');
      expect(cubit.state.lightningAddress, isNull);
      expect(cubit.state.nostrPublishStatus, NostrPublishStatus.none);
      verify(() => settings.clearNostrPublishOutcome()).called(greaterThan(0));
      verify(() => clearProfile.execute()).called(1);
      await cubit.close();
    },
  );

  test(
    'checkStatus surfaces full previousNyms list from inactive lookup',
    () async {
      when(
        () => externalReceiveWallets.get(
          environment: any(named: 'environment'),
          purpose: any(named: 'purpose'),
        ),
      ).thenAnswer((_) async => null);
      when(() => payService.getStoredAddress()).thenAnswer((_) async => null);
      when(() => lookupStatus.execute()).thenAnswer(
        (_) async => InactiveLookupResult(
          nym: 'tester3',
          quota: const NymQuota(used: 3, cap: 3),
          previousNyms: [
            PreviousNym(
              nym: 'tester3',
              createdAt: DateTime.utc(2026, 5, 2, 21, 5),
            ),
            PreviousNym(
              nym: 'tester2',
              createdAt: DateTime.utc(2026, 5, 2, 20, 58),
            ),
            PreviousNym(
              nym: 'tester1',
              createdAt: DateTime.utc(2026, 5, 2, 1, 56),
            ),
          ],
        ),
      );

      final cubit = build();
      await cubit.checkStatus(Environment.mainnet);

      expect(cubit.state.previousNyms.length, 3);
      expect(cubit.state.previousNyms.first.nym, 'tester3');
      expect(cubit.state.previousNyms.last.nym, 'tester1');
      await cubit.close();
    },
  );

  test('registerNym strips just-registered nym from previousNyms', () async {
    stubRegisterOk();
    when(
      () => externalReceiveWallets.get(
        environment: any(named: 'environment'),
        purpose: any(named: 'purpose'),
      ),
    ).thenAnswer((_) async => null);
    when(() => payService.getStoredAddress()).thenAnswer((_) async => null);
    when(() => lookupStatus.execute()).thenAnswer(
      (_) async => InactiveLookupResult(
        nym: 'alice',
        quota: const NymQuota(used: 2, cap: 3),
        previousNyms: [
          PreviousNym(nym: 'alice', createdAt: DateTime.utc(2026, 5, 1)),
          PreviousNym(nym: 'bob', createdAt: DateTime.utc(2026, 4, 30)),
        ],
      ),
    );

    final cubit = build();
    await cubit.checkStatus(Environment.mainnet);
    await cubit.registerNym(
      'alice',
      Environment.mainnet,
      publishOnNostr: false,
    );

    expect(cubit.state.lightningAddress, 'alice@bullpay.ca');
    expect(cubit.state.previousNyms.map((p) => p.nym).toList(), ['bob']);
    await cubit.close();
  });

  test('quota.state() boundaries drive the dereg-warning logic', () {
    expect(const NymQuota(used: 0, cap: 3).state(), QuotaState.available);
    expect(const NymQuota(used: 1, cap: 3).state(), QuotaState.available);
    expect(const NymQuota(used: 2, cap: 3).state(), QuotaState.lastSlot);
    expect(const NymQuota(used: 3, cap: 3).state(), QuotaState.exhausted);
    expect(const NymQuota(used: 4, cap: 3).state(), QuotaState.exhausted);
  });
}
