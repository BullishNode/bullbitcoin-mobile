import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_purpose.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/get_external_receive_wallet_usecase.dart';

class DeleteCreatedExternalReceiveWalletUsecase {
  final GetExternalReceiveWalletUsecase _getWallet;
  final WalletRepository _walletRepository;

  const DeleteCreatedExternalReceiveWalletUsecase({
    required GetExternalReceiveWalletUsecase getWallet,
    required WalletRepository walletRepository,
  }) : _getWallet = getWallet,
       _walletRepository = walletRepository;

  Future<void> execute({
    required Environment environment,
    required ExternalReceiveWalletPurpose purpose,
    required ExternalReceiveWalletAccountKey accountKey,
    required String expectedWalletId,
  }) async {
    final wallet = await _getWallet.execute(
      environment: environment,
      purpose: purpose,
      accountKey: accountKey,
    );
    if (wallet == null || wallet.id != expectedWalletId) return;

    await _walletRepository.deleteWallet(walletId: wallet.id);
  }
}
