const String lightningAddressWalletLabel = 'Lightning Address';
const String lightningAddressDomain = 'bullpay.ca';
const String payServiceBaseUrl = 'https://bullpay.ca';

/// BIP85 index for the Lightning Address receive wallet (boltz = 75).
const int lightningAddressWalletBip85Index = 75;

/// Nostr identity/account indices for pay service authentication.
///
/// These are under the BIP85 Nostr application path
/// `m/83696968'/86'/{identity}'/{account}'`. They are deliberately separate
/// from [lightningAddressWalletBip85Index], which is the Liquid receive wallet
/// mnemonic index.
const int lightningAddressNostrIdentity = 1;
const int lightningAddressNostrAccount = 1;
