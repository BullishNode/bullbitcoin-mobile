import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_purpose.dart';

class ExternalReceiveWalletIds {
  final Map<String, ExternalReceiveWalletPurpose> purposeByWalletId;
  final Map<String, ExternalReceiveWalletAccountKey> accountKeyByWalletId;
  final Set<String> hiddenOnHomeWalletIds;

  factory ExternalReceiveWalletIds({
    Map<String, ExternalReceiveWalletPurpose> purposeByWalletId = const {},
    Map<String, ExternalReceiveWalletAccountKey> accountKeyByWalletId =
        const {},
    Set<String> hiddenOnHomeWalletIds = const {},
  }) => ExternalReceiveWalletIds._(
    purposeByWalletId: Map.unmodifiable(purposeByWalletId),
    accountKeyByWalletId: Map.unmodifiable(accountKeyByWalletId),
    hiddenOnHomeWalletIds: Set.unmodifiable(hiddenOnHomeWalletIds),
  );

  const ExternalReceiveWalletIds._({
    required this.purposeByWalletId,
    required this.accountKeyByWalletId,
    required this.hiddenOnHomeWalletIds,
  });

  static const empty = ExternalReceiveWalletIds._(
    purposeByWalletId: {},
    accountKeyByWalletId: {},
    hiddenOnHomeWalletIds: {},
  );

  ExternalReceiveWalletPurpose? purposeForWalletId(String walletId) =>
      purposeByWalletId[walletId];

  ExternalReceiveWalletAccountKey? accountKeyForWalletId(String walletId) =>
      accountKeyByWalletId[walletId];

  bool isExternalReceiveWallet(String walletId) =>
      purposeByWalletId.containsKey(walletId);

  bool isHiddenOnHome(String walletId) =>
      hiddenOnHomeWalletIds.contains(walletId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExternalReceiveWalletIds &&
          _mapEquals(purposeByWalletId, other.purposeByWalletId) &&
          _accountKeyMapEquals(
            accountKeyByWalletId,
            other.accountKeyByWalletId,
          ) &&
          _setEquals(hiddenOnHomeWalletIds, other.hiddenOnHomeWalletIds);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(
      purposeByWalletId.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
    Object.hashAllUnordered(
      accountKeyByWalletId.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
    Object.hashAllUnordered(hiddenOnHomeWalletIds),
  );

  static bool _mapEquals(
    Map<String, ExternalReceiveWalletPurpose> a,
    Map<String, ExternalReceiveWalletPurpose> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  static bool _accountKeyMapEquals(
    Map<String, ExternalReceiveWalletAccountKey> a,
    Map<String, ExternalReceiveWalletAccountKey> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
