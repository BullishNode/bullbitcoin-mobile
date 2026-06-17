import 'package:bb_mobile/features/deterministic_wallets/application/application_errors.dart';
import 'package:bb_mobile/features/deterministic_wallets/application/prepare_deterministic_wallets_usecase.dart';
import 'package:bb_mobile/features/deterministic_wallets/domain/deterministic_wallets.dart';

export 'package:bb_mobile/features/deterministic_wallets/domain/deterministic_wallets.dart';

class DeterministicWalletsFacade {
  final PrepareDeterministicWalletsUsecase _prepareWallets;

  const DeterministicWalletsFacade({required this._prepareWallets});

  Future<PreparedDeterministicWallets> prepare(
    DeterministicWalletsRequest request,
  ) async {
    try {
      return await _prepareWallets.execute(request);
    } on DeterministicWalletException {
      rethrow;
    } catch (_) {
      throw DeterministicWalletException.generic();
    }
  }

  Future<void> rollbackCreatedWallets(PreparedDeterministicWallets result) {
    return _prepareWallets.rollbackCreatedWallets(result);
  }
}
