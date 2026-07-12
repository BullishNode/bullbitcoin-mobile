import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bb_mobile/features/payment_recovery/application/ports/recovery_identity_port.dart';
import 'package:bb_mobile/features/payment_recovery/domain/payment_recovery_error.dart';

/// Resolves the Get Paid signing identity for recovery from the DEFAULT
/// (Bitcoin) wallet xprv — identical derivation to `InvoicesIdentityDatasource`
/// (charter H1). The xprv never leaves the signing closure.
class RecoveryIdentityDatasource implements RecoveryIdentityPort {
  final GetSettingsUsecase _getSettings;
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;
  final NostrIdentityFacade _nostrIdentity;

  const RecoveryIdentityDatasource({
    required this._getSettings,
    required this._walletRepository,
    required this._seedRepository,
    required this._nostrIdentity,
  });

  @override
  Future<BullnymAuthSigner> getSigningHandle() async {
    final xprvBase58 = await _deriveDefaultWalletXprv();
    final String npubHex;
    try {
      npubHex = _nostrIdentity.deriveBullnymServerAuthPublicKeyFromXprv(
        xprvBase58,
      );
    } catch (_) {
      throw const PaymentRecoveryException.signingFailed();
    }
    return BullnymAuthSigner(
      npubHex: npubHex,
      signHashHex: (messageHashHex) =>
          _nostrIdentity.signBullnymServerAuthHashFromXprv(
            xprvBase58: xprvBase58,
            messageHashHex: messageHashHex,
          ),
    );
  }

  Future<String> _deriveDefaultWalletXprv() async {
    final settings = await _getSettings.execute();
    final wallets = await _walletRepository.getWallets(
      environment: settings.environment,
      onlyDefaults: true,
      onlyBitcoin: true,
    );
    if (wallets.isEmpty) {
      throw const PaymentRecoveryException.noDefaultBitcoinWallet();
    }
    final defaultWallet = wallets.first;
    try {
      final seed = await _seedRepository.get(defaultWallet.masterFingerprint);
      return Bip32Derivation.getXprvFromSeed(
        seed.bytes,
        defaultWallet.network,
      );
    } on PaymentRecoveryException {
      rethrow;
    } catch (_) {
      throw const PaymentRecoveryException.signingFailed();
    }
  }
}
