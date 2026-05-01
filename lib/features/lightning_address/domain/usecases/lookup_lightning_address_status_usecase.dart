import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/domain/entities/lookup_result.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_key_derivation.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';

/// USE CASE: resolve the current LA registration status for the wallet's
/// active default seed.
///
/// Owns the orchestration that the cubit was duplicating: derive the BIP85
/// Nostr identity from the active wallet seed, then call the pay service
/// for that npub. Returns the sealed `LookupResult` (or `null` when the
/// wallet has no Nostr identity yet, e.g. before first wallet creation).
///
/// Existence of this usecase is justified by owning the npub-derivation
/// step (Kumulynja PLAN-2) — without that, this would be a 1-line forward
/// to the port and would violate A3 (over-abstraction).
class LookupLightningAddressStatusUsecase {
  final PayServicePort _payService;
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;

  LookupLightningAddressStatusUsecase({
    required PayServicePort payService,
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
  })  : _payService = payService,
        _walletRepository = walletRepository,
        _seedRepository = seedRepository;

  /// `null` when no Nostr identity could be derived yet (no active default
  /// wallet). When the npub exists but the server has no row, returns
  /// `LookupResult?` from the port (port returns `null` for that case). The
  /// caller distinguishes "no wallet yet" from "wallet exists, no
  /// registration" by remembering that a prior call returned non-null
  /// before.
  Future<LookupResult?> execute() async {
    final nostr = await deriveNostrIdentityForLightningAddress(
      walletRepository: _walletRepository,
      seedRepository: _seedRepository,
    );
    if (nostr == null) return null;
    return _payService.lookupByNpub(nostr.npubHex);
  }
}
