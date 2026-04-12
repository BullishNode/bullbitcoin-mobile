const String lightningAddressWalletLabel = 'Lightning Address';
const String lightningAddressDomain = 'bullpay.ca';
const String payServiceBaseUrl = 'http://10.0.2.2:8080';

/// BIP85 index for the Lightning Address receive wallet (boltz = 75).
const int lightningAddressWalletBip85Index = 75;

/// BIP85 Nostr application (NIP-06).
const int nostrBip85Application = 86;

/// Nostr keypair derivation path: 86'/{identity}'/{account}'
const int lightningAddressNostrIdentity = 75;
const int lightningAddressNostrAccount = 0;
