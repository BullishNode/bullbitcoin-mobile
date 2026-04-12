/// Constants owned by the lightning_address domain layer.
/// The public facade re-exports these for cross-feature access.
const String lightningAddressWalletLabel = 'Lightning Address';
const String lightningAddressDomain = 'bullpay.ca';

// TODO: Switch back to production URL before merging
// const String payServiceBaseUrl = 'https://bullpay.ca';
const String payServiceBaseUrl = 'http://10.0.2.2:8080';

/// BIP85 Nostr application number: n(14)+o(15)+s(19)+t(20)+r(18) = 86
const int nostrBip85Application = 86;

/// Identity index for lightning address nostr keypair
const int lightningAddressNostrIdentity = 75;

/// Account index
const int lightningAddressNostrAccount = 0;
