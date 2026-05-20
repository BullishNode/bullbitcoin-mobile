import 'package:bb_mobile/features/import_wallet/create_bip85_wallet_state.dart';
import 'package:bb_mobile/features/wallet_manifest/public/create_manual_bip85_wallets.dart';
import 'package:bb_mobile/features/wallet_manifest/public/wallet_manifest_facade.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class CreateBip85WalletCubit extends Cubit<CreateBip85WalletState> {
  final WalletManifestFacade _walletManifest;

  CreateBip85WalletCubit({required WalletManifestFacade walletManifest})
    : _walletManifest = walletManifest,
      super(const CreateBip85WalletState());

  Future<void> submit(CreateManualBip85WalletsCommand command) async {
    if (state.isSubmitting) return;
    emit(
      const CreateBip85WalletState(status: CreateBip85WalletStatus.submitting),
    );

    try {
      final result = await _walletManifest.createManualBip85Wallets(command);
      if (isClosed) return;
      emit(
        CreateBip85WalletState(
          status: CreateBip85WalletStatus.succeeded,
          result: result,
        ),
      );
    } catch (e) {
      if (isClosed) return;
      emit(
        CreateBip85WalletState(
          status: CreateBip85WalletStatus.failed,
          failure: _failureFor(e),
        ),
      );
    }
  }

  CreateManualBip85WalletsFailure _failureFor(Object error) {
    return switch (error) {
      CreateManualBip85WalletsException() => error.failure,
      _ => CreateManualBip85WalletsFailure.generic,
    };
  }
}
