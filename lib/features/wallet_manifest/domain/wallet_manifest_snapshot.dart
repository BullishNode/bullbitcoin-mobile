import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_account.dart';

class WalletManifestSnapshot {
  final int createdAt;
  final List<WalletManifestAccount> accounts;

  WalletManifestSnapshot({
    required this.createdAt,
    required List<WalletManifestAccount> accounts,
  }) : accounts = List.unmodifiable(accounts);

  WalletManifestSnapshot collapseDuplicates() {
    final byIdentity = <String, WalletManifestAccount>{};
    for (final account in accounts) {
      final existing = byIdentity[account.identity];
      if (existing == null || _isNewer(account, existing)) {
        byIdentity[account.identity] = account;
      }
    }

    final collapsed = byIdentity.values.toList()
      ..sort((a, b) {
        final fingerprintOrder = a.rootFingerprint.compareTo(b.rootFingerprint);
        if (fingerprintOrder != 0) return fingerprintOrder;
        final indexOrder = a.bip85Index.compareTo(b.bip85Index);
        if (indexOrder != 0) return indexOrder;
        return a.network.value.compareTo(b.network.value);
      });

    return WalletManifestSnapshot(createdAt: createdAt, accounts: collapsed);
  }

  bool _isNewer(
    WalletManifestAccount candidate,
    WalletManifestAccount existing,
  ) {
    final candidateTimestamp = candidate.timestamp ?? createdAt;
    final existingTimestamp = existing.timestamp ?? createdAt;
    if (candidateTimestamp != existingTimestamp) {
      return candidateTimestamp > existingTimestamp;
    }

    // Later entries win deterministic ties.
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WalletManifestSnapshot &&
          createdAt == other.createdAt &&
          _accountsEqual(accounts, other.accounts);

  @override
  int get hashCode => Object.hash(createdAt, Object.hashAll(accounts));

  bool _accountsEqual(
    List<WalletManifestAccount> a,
    List<WalletManifestAccount> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
