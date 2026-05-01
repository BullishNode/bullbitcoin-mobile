import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/delete_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/presentation/lightning_address_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockGetWallet extends Mock implements GetLightningAddressWalletUsecase {}

class _MockRegister extends Mock implements RegisterLightningAddressUsecase {}

class _MockDelete extends Mock implements DeleteLightningAddressUsecase {}

class _MockPayService extends Mock implements PayServicePort {}

class _MockWalletRepository extends Mock implements WalletRepository {}

class _MockSeedRepository extends Mock implements SeedRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(Environment.mainnet);
  });

  late _MockGetWallet getWallet;
  late _MockRegister register;
  late _MockDelete delete;
  late _MockPayService payService;
  late _MockWalletRepository walletRepo;
  late _MockSeedRepository seedRepo;

  setUp(() {
    getWallet = _MockGetWallet();
    register = _MockRegister();
    delete = _MockDelete();
    payService = _MockPayService();
    walletRepo = _MockWalletRepository();
    seedRepo = _MockSeedRepository();
  });

  LightningAddressCubit build() => LightningAddressCubit(
        getWallet: getWallet,
        register: register,
        delete: delete,
        payService: payService,
        walletRepository: walletRepo,
        seedRepository: seedRepo,
      );

  test('registerNym is reentrancy-guarded (I-2)', () async {
    when(() => register.execute(
          nym: any(named: 'nym'),
          environment: any(named: 'environment'),
        )).thenAnswer((_) async => 'alice@bullpay.ca');

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
        )).called(1);
    await cubit.close();
  });

  test('deleteAddress is reentrancy-guarded (I-2)', () async {
    when(() => delete.execute()).thenAnswer((_) async {});

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
        ));
    expect(cubit.state.registering, isFalse);
    await cubit.close();
  });

  test('register failure is captured into state.error', () async {
    when(() => register.execute(
          nym: any(named: 'nym'),
          environment: any(named: 'environment'),
        )).thenThrow(Exception('NymTaken'));

    final cubit = build();
    await cubit.registerNym('alice', Environment.mainnet);

    expect(cubit.state.registering, isFalse);
    expect(cubit.state.error, contains('NymTaken'));
    expect(cubit.state.lightningAddress, isNull);
    await cubit.close();
  });

  test('successful register populates address + clears registering', () async {
    when(() => register.execute(
          nym: any(named: 'nym'),
          environment: any(named: 'environment'),
        )).thenAnswer((_) async => 'alice@bullpay.ca');

    final cubit = build();
    await cubit.registerNym('alice', Environment.mainnet);

    expect(cubit.state.lightningAddress, 'alice@bullpay.ca');
    expect(cubit.state.registering, isFalse);
    expect(cubit.state.error, isNull);
    await cubit.close();
  });

  test('successful delete leaves previousNym set for reactivation banner',
      () async {
    when(() => register.execute(
          nym: any(named: 'nym'),
          environment: any(named: 'environment'),
        )).thenAnswer((_) async => 'alice@bullpay.ca');
    when(() => delete.execute()).thenAnswer((_) async {});

    final cubit = build();
    await cubit.registerNym('alice', Environment.mainnet);
    await cubit.deleteAddress();

    expect(cubit.state.previousNym, 'alice');
    expect(cubit.state.lightningAddress, isNull);
    expect(cubit.state.registering, isFalse);
    await cubit.close();
  });
}
