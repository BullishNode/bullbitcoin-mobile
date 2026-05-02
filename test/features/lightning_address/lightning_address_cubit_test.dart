import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/delete_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/lookup_lightning_address_status_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/republish_nostr_profile_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/nym_quota.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockGetWallet extends Mock implements GetLightningAddressWalletUsecase {}

class _MockRegister extends Mock implements RegisterLightningAddressUsecase {}

class _MockDelete extends Mock implements DeleteLightningAddressUsecase {}

class _MockLookupStatus extends Mock
    implements LookupLightningAddressStatusUsecase {}

class _MockPayService extends Mock implements PayServicePort {}

class _MockRepublishNostrProfile extends Mock
    implements RepublishNostrProfileUsecase {}

void main() {
  setUpAll(() {
    registerFallbackValue(Environment.mainnet);
  });

  late _MockGetWallet getWallet;
  late _MockRegister register;
  late _MockDelete delete;
  late _MockLookupStatus lookupStatus;
  late _MockPayService payService;
  late _MockRepublishNostrProfile republishNostrProfile;

  setUp(() {
    getWallet = _MockGetWallet();
    register = _MockRegister();
    delete = _MockDelete();
    lookupStatus = _MockLookupStatus();
    payService = _MockPayService();
    republishNostrProfile = _MockRepublishNostrProfile();
    when(() => republishNostrProfile.execute()).thenAnswer((_) async {});
  });

  LightningAddressCubit build() => LightningAddressCubit(
        getWallet: getWallet,
        register: register,
        delete: delete,
        lookupStatus: lookupStatus,
        republishNostrProfile: republishNostrProfile,
        payService: payService,
      );

  void stubRegisterOk({NymQuota quota = const NymQuota(used: 1, cap: 3)}) {
    when(() => register.execute(
          nym: any(named: 'nym'),
          environment: any(named: 'environment'),
          publishOnNostr: any(named: 'publishOnNostr'),
        )).thenAnswer((_) async => (address: 'alice@bullpay.ca', quota: quota));
  }

  void stubDeleteOk({NymQuota quota = const NymQuota(used: 1, cap: 3)}) {
    when(() => delete.execute()).thenAnswer((_) async => quota);
  }

  test('registerNym is reentrancy-guarded (I-2)', () async {
    stubRegisterOk();

    final cubit = build();
    // Fire both calls before awaiting either. Cubit `emit` is synchronous,
    // so the second call observes `state.registering == true` and returns.
    await Future.wait([
      cubit.registerNym('alice', Environment.mainnet),
      cubit.registerNym('alice', Environment.mainnet),
    ]);

    verify(() => register.execute(
          nym: any(named: 'nym'),
          environment: any(named: 'environment'),
          publishOnNostr: any(named: 'publishOnNostr'),
        )).called(1);
    await cubit.close();
  });

  test('deleteAddress is reentrancy-guarded (I-2)', () async {
    stubDeleteOk();

    final cubit = build();
    await Future.wait([cubit.deleteAddress(), cubit.deleteAddress()]);

    verify(() => delete.execute()).called(1);
    await cubit.close();
  });

  test('registerNym ignores empty nym', () async {
    final cubit = build();
    await cubit.registerNym('', Environment.mainnet);
    verifyNever(() => register.execute(
          nym: any(named: 'nym'),
          environment: any(named: 'environment'),
          publishOnNostr: any(named: 'publishOnNostr'),
        ));
    expect(cubit.state.registering, isFalse);
    await cubit.close();
  });

  test('register failure is captured into state.error', () async {
    when(() => register.execute(
          nym: any(named: 'nym'),
          environment: any(named: 'environment'),
          publishOnNostr: any(named: 'publishOnNostr'),
        )).thenThrow(Exception('NymTaken'));

    final cubit = build();
    await cubit.registerNym('alice', Environment.mainnet);

    expect(cubit.state.registering, isFalse);
    expect(cubit.state.error, contains('NymTaken'));
    expect(cubit.state.lightningAddress, isNull);
    await cubit.close();
  });

  test('successful register populates address + quota + clears registering',
      () async {
    stubRegisterOk(quota: const NymQuota(used: 2, cap: 3));

    final cubit = build();
    await cubit.registerNym('alice', Environment.mainnet);

    expect(cubit.state.lightningAddress, 'alice@bullpay.ca');
    expect(cubit.state.quota, const NymQuota(used: 2, cap: 3));
    expect(cubit.state.registering, isFalse);
    expect(cubit.state.error, isNull);
    await cubit.close();
  });

  test('successful delete leaves previousNym set for reactivation banner',
      () async {
    stubRegisterOk();
    stubDeleteOk();

    final cubit = build();
    await cubit.registerNym('alice', Environment.mainnet);
    await cubit.deleteAddress();

    expect(cubit.state.previousNym, 'alice');
    expect(cubit.state.lightningAddress, isNull);
    expect(cubit.state.registering, isFalse);
    await cubit.close();
  });

  test('quota.state() boundaries drive the dereg-warning logic', () {
    expect(const NymQuota(used: 0, cap: 3).state(), QuotaState.available);
    expect(const NymQuota(used: 1, cap: 3).state(), QuotaState.available);
    expect(const NymQuota(used: 2, cap: 3).state(), QuotaState.lastSlot);
    expect(const NymQuota(used: 3, cap: 3).state(), QuotaState.exhausted);
    // Defensive — server-reported `used > cap` clamps remaining at zero.
    expect(const NymQuota(used: 4, cap: 3).state(), QuotaState.exhausted);
  });

  test('publishOnNostr=false threads through to the register usecase',
      () async {
    stubRegisterOk();

    final cubit = build();
    await cubit.registerNym(
      'alice',
      Environment.mainnet,
      publishOnNostr: false,
    );

    final captured = verify(() => register.execute(
          nym: any(named: 'nym'),
          environment: any(named: 'environment'),
          publishOnNostr: captureAny(named: 'publishOnNostr'),
        )).captured;
    expect(captured.single, isFalse);
    await cubit.close();
  });
}
