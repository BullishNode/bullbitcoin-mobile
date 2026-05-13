import 'package:bb_mobile/features/get_paid/shared/get_paid_nostr_identity.dart';

/// Display label for the dedicated Liquid wallet whose descriptor is registered
/// with Bullnym. Keep the existing label for users and wallet lookup stability.
const String bullnymReceiveWalletLabel = 'Lightning Address';
const String lightningAddressDomain = 'bullpay.ca';
const String payServiceBaseUrl = 'https://bullpay.ca';

/// BIP85 index for the Bullnym receive wallet (boltz = 75).
const int bullnymReceiveWalletBip85Index = 75;

/// Nostr identity/account indices for pay service authentication.
///
/// These are under the BIP85 Nostr application path
/// `m/83696968'/86'/{identity}'/{account}'`. They are deliberately separate
/// from [bullnymReceiveWalletBip85Index], which is the Bullnym Liquid receive
/// wallet mnemonic index.
const int lightningAddressNostrIdentity = getPaidNostrIdentity;
const int lightningAddressNostrAccount = getPaidNostrAccount;
