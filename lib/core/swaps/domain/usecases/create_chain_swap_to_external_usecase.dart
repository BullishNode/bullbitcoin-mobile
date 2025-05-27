import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/seed/domain/repositories/seed_repository.dart';
import 'package:bb_mobile/core/swaps/domain/entity/swap.dart';
import 'package:bb_mobile/core/swaps/domain/repositories/swap_repository.dart';
import 'package:bb_mobile/core/utils/constants.dart';
import 'package:bb_mobile/core/wallet/domain/repositories/wallet_repository.dart';

class CreateChainSwapToExternalUsecase {
  final WalletRepository _walletRepository;
  final SwapRepository _swapRepository;
  final SwapRepository _swapRepositoryTestnet;
  final SeedRepository _seedRepository;

  CreateChainSwapToExternalUsecase({
    required WalletRepository walletRepository,
    required SwapRepository swapRepository,
    required SwapRepository swapRepositoryTestnet,
    required SeedRepository seedRepository,
  }) : _walletRepository = walletRepository,
       _swapRepository = swapRepository,
       _swapRepositoryTestnet = swapRepositoryTestnet,
       _seedRepository = seedRepository;

  Future<ChainSwap> execute({
    required String sendWalletId,
    required String receiveAddress,
    required SwapType type,
    bool drain = false,
    int? amountSat,
  }) async {
    try {
      final sendWallet = await _walletRepository.getWallet(sendWalletId);

      if (sendWallet == null) {
        throw Exception('Send wallet not found');
      }

      final isTestnet = sendWallet.network.isTestnet;
      final swapRepository =
          isTestnet ? _swapRepositoryTestnet : _swapRepository;
      final sendWalletMnemonic =
          await _seedRepository.get(sendWallet.masterFingerprint)
              as MnemonicSeed;

      final btcElectrumUrl =
          sendWallet.network.isTestnet
              ? ApiServiceConstants.bbElectrumTestUrl
              : ApiServiceConstants.bbElectrumUrl;

      final lbtcElectrumUrl =
          sendWallet.network.isTestnet
              ? ApiServiceConstants.publicElectrumTestUrl
              : ApiServiceConstants.bbLiquidElectrumUrlPath;

      switch (type) {
        case SwapType.bitcoinToLiquid:
          if (!sendWallet.network.isBitcoin) {
            throw Exception(
              'Send wallet must be a Bitcoin wallet for bitcoinToLiquid swap',
            );
          }
          return await swapRepository.createBitcoinToLiquidSwap(
            sendWalletMnemonic: sendWalletMnemonic.mnemonicWords.join(' '),
            sendWalletId: sendWalletId,
            amountSat: amountSat!,
            isTestnet: isTestnet,
            btcElectrumUrl: btcElectrumUrl,
            lbtcElectrumUrl: lbtcElectrumUrl,
            externalRecipientAddress: receiveAddress,
          );
        case SwapType.liquidToBitcoin:
          if (!sendWallet.network.isLiquid) {
            throw Exception(
              'Send wallet must be a Liquid wallet for liquidToBitcoin swap',
            );
          }
          return await swapRepository.createLiquidToBitcoinSwap(
            sendWalletMnemonic: sendWalletMnemonic.mnemonicWords.join(' '),
            sendWalletId: sendWalletId,
            amountSat: amountSat!,
            isTestnet: isTestnet,
            btcElectrumUrl: btcElectrumUrl,
            lbtcElectrumUrl: lbtcElectrumUrl,
            externalRecipientAddress: receiveAddress,
          );
        default:
          throw Exception(
            'Swap Type provided is not a supported chain swap to external address!',
          );
      }
    } catch (e) {
      throw e.toString();
    }
  }
}
