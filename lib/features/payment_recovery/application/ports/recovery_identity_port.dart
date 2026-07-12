import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart'
    show BullnymAuthSigner;

/// Resolves the Get Paid signing identity for recovery. Needs ONLY the npub
/// signer — the SAME server-auth npub the Donation Page / POS / invoices derive
/// from the DEFAULT (Bitcoin) wallet xprv. Detection (`invoice-recovery-list`)
/// and the recover action (`invoice-recover`) both authenticate with it; no nym
/// lookup and no active registration are required (each recoverable row carries
/// its own nym). The xprv is derived at point of use and captured only inside
/// the signing closure (charter H1: never stored, never logged).
///
/// Throws `PaymentRecoveryException.noDefaultBitcoinWallet` /
/// `PaymentRecoveryException.signingFailed` when no default wallet / seed is
/// available (locked, superwallet mode).
abstract interface class RecoveryIdentityPort {
  Future<BullnymAuthSigner> getSigningHandle();
}
