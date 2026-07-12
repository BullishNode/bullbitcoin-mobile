import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_address_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bb_mobile/features/payment_recovery/application/ports/recovery_identity_port.dart';
import 'package:bb_mobile/features/payment_recovery/application/ports/recovery_pay_service_port.dart';
import 'package:bb_mobile/features/payment_recovery/application/usecases/dismiss_stuck_payment_usecase.dart';
import 'package:bb_mobile/features/payment_recovery/application/usecases/recover_stuck_payment_usecase.dart';
import 'package:bb_mobile/features/payment_recovery/application/usecases/scan_stuck_payments_usecase.dart';
import 'package:bb_mobile/features/payment_recovery/application/usecases/watch_stuck_payments_usecase.dart';
import 'package:bb_mobile/features/payment_recovery/data/datasources/recovery_identity_datasource.dart';
import 'package:bb_mobile/features/payment_recovery/data/datasources/recovery_pay_service_datasource.dart';
import 'package:bb_mobile/features/payment_recovery/data/drift_payment_recovery_repository.dart';
import 'package:bb_mobile/features/payment_recovery/domain/repositories/payment_recovery_repository.dart';
import 'package:bb_mobile/features/payment_recovery/presentation/stuck_payments_cubit.dart';
import 'package:bb_mobile/features/payment_recovery/public/payment_recovery_facade.dart';
import 'package:get_it/get_it.dart';

class PaymentRecoveryLocator {
  static void setup(GetIt locator) {
    // lazySingleton: stateless over the shared SqliteDatabase singleton.
    locator.registerLazySingleton<PaymentRecoveryRepository>(
      () => DriftPaymentRecoveryRepository(database: locator<SqliteDatabase>()),
    );
    locator.registerFactory<RecoveryIdentityPort>(
      () => RecoveryIdentityDatasource(
        getSettings: locator<GetSettingsUsecase>(),
        walletRepository: locator<WalletRepository>(),
        seedRepository: locator<SeedRepository>(),
        nostrIdentity: locator<NostrIdentityFacade>(),
      ),
    );
    locator.registerFactory<RecoveryPayServicePort>(
      () => RecoveryPayServiceDatasource(bullnym: locator<BullnymFacade>()),
    );
    locator.registerFactory<ScanStuckPaymentsUsecase>(
      () => ScanStuckPaymentsUsecase(
        identity: locator<RecoveryIdentityPort>(),
        payService: locator<RecoveryPayServicePort>(),
        repository: locator<PaymentRecoveryRepository>(),
        nowSecs: () => locator<Clock>().nowSecs(),
      ),
    );
    locator.registerFactory<WatchStuckPaymentsUsecase>(
      () => WatchStuckPaymentsUsecase(
        repository: locator<PaymentRecoveryRepository>(),
      ),
    );
    locator.registerFactory<DismissStuckPaymentUsecase>(
      () => DismissStuckPaymentUsecase(
        repository: locator<PaymentRecoveryRepository>(),
      ),
    );
    locator.registerFactory<RecoverStuckPaymentUsecase>(
      () => RecoverStuckPaymentUsecase(
        identity: locator<RecoveryIdentityPort>(),
        payService: locator<RecoveryPayServicePort>(),
        repository: locator<PaymentRecoveryRepository>(),
        walletRepository: locator<WalletRepository>(),
        walletAddressRepository: locator<WalletAddressRepository>(),
        getSettings: locator<GetSettingsUsecase>(),
        nowSecs: () => locator<Clock>().nowSecs(),
      ),
    );
    locator.registerFactory<PaymentRecoveryFacade>(
      () => PaymentRecoveryFacade(
        scan: locator<ScanStuckPaymentsUsecase>(),
        watch: locator<WatchStuckPaymentsUsecase>(),
        dismiss: locator<DismissStuckPaymentUsecase>(),
        recover: locator<RecoverStuckPaymentUsecase>(),
      ),
    );
    locator.registerFactory<StuckPaymentsCubit>(
      () => StuckPaymentsCubit(recovery: locator<PaymentRecoveryFacade>()),
    );
  }
}
