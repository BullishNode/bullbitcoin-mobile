import 'package:bb_mobile/core/errors/bull_exception.dart';

/// Wallet records exist for [fingerprint] but their seed is no longer in the
/// seed store (keystore invalidation, interrupted restore), so anything that
/// derives the xprv is doomed.
///
/// Thrown where the records are reused — cold start and default-wallet
/// creation — so the state is named at detection time instead of surfacing as
/// a `SeedNotFoundException` inside whichever flow happens to need the xprv
/// first (#137). The remedy is restoring the wallet from a backup.
class InconsistentWalletStateException extends BullException {
  InconsistentWalletStateException({required this.fingerprint})
    : super('Wallet records without a seed for fingerprint: $fingerprint');

  final String fingerprint;
}
