enum NostrIdentityRole {
  walletManifest(identity: 1, account: 1),
  bullnymServerAuth(identity: 2, account: 1),
  nip05Verification(identity: 3, account: 1);

  final int identity;
  final int account;

  const NostrIdentityRole({required this.identity, required this.account});
}
