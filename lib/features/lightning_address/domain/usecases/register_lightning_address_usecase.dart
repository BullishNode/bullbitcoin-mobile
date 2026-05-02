import 'package:bb_mobile/core/nostr/nostr_identity.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_key_derivation.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_v1_signing.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/nostr_publish_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/nym_quota.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/create_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_lightning_address_wallet_usecase.dart';

class RegisterLightningAddressUsecase {
  final CreateLightningAddressWalletUsecase _createWallet;
  final GetLightningAddressWalletUsecase _getWallet;
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;
  final PayServicePort _payService;
  final NostrPublishPort _nostrPublish;

  RegisterLightningAddressUsecase({
    required CreateLightningAddressWalletUsecase createWallet,
    required GetLightningAddressWalletUsecase getWallet,
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
    required PayServicePort payService,
    required NostrPublishPort nostrPublish,
  }) : _createWallet = createWallet,
       _getWallet = getWallet,
       _walletRepository = walletRepository,
       _seedRepository = seedRepository,
       _payService = payService,
       _nostrPublish = nostrPublish;

  Future<({String address, NymQuota quota})> execute({
    required String nym,
    required Environment environment,
    bool publishOnNostr = true,
  }) async {
    var wallet = await _getWallet.execute(environment: environment);
    wallet ??= await _createWallet.execute(environment: environment);

    final xprv = await deriveDefaultWalletXprv(
      walletRepository: _walletRepository,
      seedRepository: _seedRepository,
    );
    final nostr = NostrIdentity.derive(
      xprvBase58: xprv,
      identity: lightningAddressNostrIdentity,
      account: lightningAddressNostrAccount,
    );

    final ctDescriptor = wallet.externalPublicDescriptor;
    final timestampSecs = currentUnixTimestampSecs();
    final messageBytes = buildLaV1Message(
      action: 'register',
      npubHex: nostr.npubHex,
      payloadFields: [nym, ctDescriptor],
      timestampSecs: timestampSecs,
    );
    final signature = nostr.signSchnorr(messageBytes);

    try {
      final result = await _payService.register(
        nym: nym,
        ctDescriptor: ctDescriptor,
        npubHex: nostr.npubHex,
        signatureHex: signature,
        timestampSecs: timestampSecs,
      );

      // Best-effort kind:0 broadcast. Opt-out via `publishOnNostr: false`
      // skips it entirely; on zero-relay failure the adapter throws
      // [LightningAddressNostrPublishFailedException] which propagates to
      // the cubit (server registration is already committed and is not
      // unwound).
      if (publishOnNostr) {
        await nostr.withPrivateKeyHex(
          (nsec) => _nostrPublish.publishProfile(
            privateKeyHex: nsec,
            name: nym,
            nip05: '$nym@$lightningAddressDomain',
            lud16: '$nym@$lightningAddressDomain',
          ),
        );
      }

      return result;
    } on PayServiceException catch (e) {
      throw LightningAddressRegistrationException(e.message);
    }
  }

}
