import 'dart:typed_data';

import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/data/datasources/pay_service_datasource.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/create_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_lightning_address_wallet_usecase.dart';
import 'package:bip85_entropy/bip85_entropy.dart' as bip85;
import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:crypto/crypto.dart';

class RegisterLightningAddressUsecase {
  final CreateLightningAddressWalletUsecase _createWallet;
  final GetLightningAddressWalletUsecase _getWallet;
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;
  final PayServiceDatasource _payService;

  RegisterLightningAddressUsecase({
    required CreateLightningAddressWalletUsecase createWallet,
    required GetLightningAddressWalletUsecase getWallet,
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
    required PayServiceDatasource payService,
  }) : _createWallet = createWallet,
       _getWallet = getWallet,
       _walletRepository = walletRepository,
       _seedRepository = seedRepository,
       _payService = payService;

  Future<String> execute({
    required String nym,
    required Environment environment,
  }) async {
    var wallet = await _getWallet.execute(environment: environment);
    wallet ??= await _createWallet.execute(environment: environment);

    final xprv = await _deriveXprv();
    final nostrPath = bip85.Bip85HardenedPath(
      "$nostrBip85Application'/$lightningAddressNostrIdentity'/$lightningAddressNostrAccount'",
    );
    final entropyHex = bip85.Bip85Entropy.deriveFromHardenedPath(
      xprvBase58: xprv,
      path: nostrPath,
    );

    final nsecHex = entropyHex.substring(0, 64);
    final ecPrivate = ECPrivate.fromHex(nsecHex);
    final npubHex = ecPrivate.getPublic().toXOnlyHex();

    final ctDescriptor = wallet.externalPublicDescriptor;
    final message = '$nym$ctDescriptor';
    final messageHash = sha256.convert(message.codeUnits).bytes;
    final signature = ecPrivate.signSchnorr(
      Uint8List.fromList(messageHash),
    );

    return await _payService.register(
      nym: nym,
      ctDescriptor: ctDescriptor,
      npubHex: npubHex,
      signatureHex: signature,
    );
  }

  Future<String> _deriveXprv() async {
    final wallets = await _walletRepository.getWallets(
      onlyDefaults: true,
      onlyBitcoin: true,
    );
    if (wallets.isEmpty) throw Exception('No default Bitcoin wallet found');
    final defaultWallet = wallets.first;

    final seed = await _seedRepository.get(defaultWallet.masterFingerprint);
    return Bip32Derivation.getXprvFromSeed(
      seed.bytes,
      defaultWallet.network,
    );
  }
}
