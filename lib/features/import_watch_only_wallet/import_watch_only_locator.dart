import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/wallet_label_reservations.dart';
import 'package:bb_mobile/features/import_watch_only_wallet/import_watch_only_descriptor_usecase.dart';
import 'package:bb_mobile/features/import_watch_only_wallet/import_watch_only_xpub_usecase.dart';
import 'package:get_it/get_it.dart';

class ImportWatchOnlyLocator {
  static void setup(GetIt locator) {
    // Use cases
    locator.registerFactory<ImportWatchOnlyDescriptorUsecase>(
      () => ImportWatchOnlyDescriptorUsecase(
        walletRepository: locator<WalletRepository>(),
        walletLabelReservationPolicy: locator<WalletLabelReservationPolicy>(),
      ),
    );

    locator.registerFactory<ImportWatchOnlyXpubUsecase>(
      () => ImportWatchOnlyXpubUsecase(
        walletRepository: locator<WalletRepository>(),
        walletLabelReservationPolicy: locator<WalletLabelReservationPolicy>(),
      ),
    );
  }
}
