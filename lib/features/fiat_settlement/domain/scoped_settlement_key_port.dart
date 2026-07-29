/// What the local credential store holds for fiat settlement.
///
/// Distinguishes the two states an exchange login can leave behind, because they
/// need different things said to the merchant: no session at all (the login was
/// never completed) versus a session whose account issued no scoped
/// `SELL_TO_FIAT_BALANCE` credential (the login worked, the permission did not
/// arrive — which logging in again will not fix).
enum FiatSettlementConnectionStatus {
  notLoggedIn,
  missingSettlementPermission,
  connected,
}

/// Availability and confidential access to the locally stored scoped
/// `SELL_TO_FIAT_BALANCE` credential.
///
/// [isPresent] and [connectionStatus] are the only signals exposed to gating and
/// UI. [readPlaintext] returns the raw key and MUST be called from nowhere except
/// the final set-fiat operation, immediately before handing the value to the
/// Bullnym transport.
abstract interface class ScopedSettlementKeyPort {
  Future<bool> isPresent();

  /// Why the scoped credential is or is not usable — never the credential.
  Future<FiatSettlementConnectionStatus> connectionStatus();

  /// Plaintext scoped key for the current environment, or null when absent.
  Future<String?> readPlaintext();
}
