import 'package:bb_mobile/core/errors/bull_exception.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/wallet_label_reservations.dart';
import 'package:bb_mobile/features/import_watch_only_wallet/watch_only_wallet_entity.dart';

class ImportWatchOnlyDescriptorUsecase {
  final WalletRepository _wallet;
  final WalletLabelReservationPolicy _walletLabelReservationPolicy;

  ImportWatchOnlyDescriptorUsecase({
    required WalletRepository walletRepository,
    required WalletLabelReservationPolicy walletLabelReservationPolicy,
  }) : _wallet = walletRepository,
       _walletLabelReservationPolicy = walletLabelReservationPolicy;

  Future<Wallet> call({
    required WatchOnlyDescriptorEntity watchOnlyDescriptor,
  }) async {
    try {
      _walletLabelReservationPolicy.throwIfReserved(watchOnlyDescriptor.label);

      final wallet = await _wallet.importDescriptor(
        watchOnlyDescriptor: watchOnlyDescriptor,
      );

      return wallet;
    } on ReservedWalletLabelException {
      rethrow;
    } catch (e) {
      throw ImportWatchOnlyDescriptorException(e.toString());
    }
  }
}

class ImportWatchOnlyDescriptorException extends BullException {
  ImportWatchOnlyDescriptorException(super.message);
}
