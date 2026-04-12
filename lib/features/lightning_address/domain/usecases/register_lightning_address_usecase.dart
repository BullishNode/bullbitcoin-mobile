import 'package:bb_mobile/core/nostr/nostr_identity.dart';
import 'package:bb_mobile/core/nostr/nostr_relay_client.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/data/datasources/pay_service_datasource.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/create_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_lightning_address_wallet_usecase.dart';
import 'package:dio/dio.dart';

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
    final nostr = NostrIdentity.derive(
      xprvBase58: xprv,
      identity: lightningAddressNostrIdentity,
      account: lightningAddressNostrAccount,
    );

    final ctDescriptor = wallet.externalPublicDescriptor;
    final message = '$nym$ctDescriptor';
    final signature = nostr.signSchnorr(message.codeUnits);

    try {
      final address = await _payService.register(
        nym: nym,
        ctDescriptor: ctDescriptor,
        npubHex: nostr.npubHex,
        signatureHex: signature,
      );

      // Publish NIP-05 profile to nostr relays (best-effort)
      try {
        await NostrRelayClient.publishProfile(
          privateKeyHex: nostr.nsecHex,
          name: nym,
          nip05: '$nym@$lightningAddressDomain',
          lud16: '$nym@$lightningAddressDomain',
        );
      } catch (_) {}

      return address;
    } on PayServiceException catch (e) {
      throw LightningAddressRegistrationException(e.message);
    } on DioException catch (e) {
      throw LightningAddressRegistrationException(
        e.response?.data?.toString() ?? e.message ?? 'Network error',
      );
    }
  }

  Future<String> _deriveXprv() async {
    final wallets = await _walletRepository.getWallets(
      onlyDefaults: true,
      onlyBitcoin: true,
    );
    if (wallets.isEmpty) throw LightningAddressNoDefaultWalletException();
    final defaultWallet = wallets.first;

    final seed = await _seedRepository.get(defaultWallet.masterFingerprint);
    return Bip32Derivation.getXprvFromSeed(
      seed.bytes,
      defaultWallet.network,
    );
  }
}
