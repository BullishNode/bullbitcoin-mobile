import 'package:bb_mobile/features/bip85_registry/domain/bip85_reservation.dart';

class Bip85Reservations {
  const Bip85Reservations._();

  static const btcpayWalletSeed = Bip85Reservation(
    id: 'btcpay_wallet_seed',
    deterministicAlias: 'BTCPay',
    owner: Bip85ReservationOwner.btcpay,
    purpose: Bip85ReservationPurpose.walletSeed,
    application: Bip85ApplicationSpec(
      number: 39,
      name: 'bip39Mnemonic',
      standard: true,
    ),
    scope: Bip85ReservationScope(
      exactPath: "39'/0'/12'/100'",
      segments: [
        Bip85PathSegment(name: 'language', value: 0),
        Bip85PathSegment(name: 'words', value: 12),
        Bip85PathSegment(name: 'index', value: 100),
      ],
    ),
    allocation: Bip85AllocationPolicy.blockExactPath,
  );

  static const lightningAddressWalletSeed = Bip85Reservation(
    id: 'lightning_address_wallet_seed',
    deterministicAlias: 'Lightning Address',
    owner: Bip85ReservationOwner.lightningAddress,
    purpose: Bip85ReservationPurpose.walletSeed,
    application: Bip85ApplicationSpec(
      number: 39,
      name: 'bip39Mnemonic',
      standard: true,
    ),
    scope: Bip85ReservationScope(
      exactPath: "39'/0'/12'/101'",
      segments: [
        Bip85PathSegment(name: 'language', value: 0),
        Bip85PathSegment(name: 'words', value: 12),
        Bip85PathSegment(name: 'index', value: 101),
      ],
    ),
    allocation: Bip85AllocationPolicy.blockExactPath,
    walletMaterializationPolicy: Bip85WalletMaterializationPolicy(
      count: 1,
      networkNameByEnvironment: {
        'mainnet': 'liquidMainnet',
        'testnet': 'liquidTestnet',
      },
      walletPurpose: 'liquid',
      scriptType: 'bip84',
      requiresProductReactivationOnRecovery: true,
    ),
  );

  static const paymentPageWalletSeed = Bip85Reservation(
    id: 'payment_page_wallet_seed',
    deterministicAlias: 'Payment Page',
    owner: Bip85ReservationOwner.paymentPage,
    purpose: Bip85ReservationPurpose.walletSeed,
    application: Bip85ApplicationSpec(
      number: 39,
      name: 'bip39Mnemonic',
      standard: true,
    ),
    scope: Bip85ReservationScope(
      exactPath: "39'/0'/12'/102'",
      segments: [
        Bip85PathSegment(name: 'language', value: 0),
        Bip85PathSegment(name: 'words', value: 12),
        Bip85PathSegment(name: 'index', value: 102),
      ],
    ),
    allocation: Bip85AllocationPolicy.blockExactPath,
  );

  static const nostrWalletManifestKey = Bip85Reservation(
    id: 'nostr_wallet_manifest_key',
    deterministicAlias: 'Nostr Wallet Manifest',
    owner: Bip85ReservationOwner.nostr,
    purpose: Bip85ReservationPurpose.nonWalletNostrKey,
    application: Bip85ApplicationSpec(
      number: 9000,
      name: 'nostr',
      standard: false,
    ),
    scope: Bip85ReservationScope(
      exactPath: "9000'/1'/1'",
      segments: [
        Bip85PathSegment(name: 'identity', value: 1),
        Bip85PathSegment(name: 'account', value: 1),
      ],
    ),
    allocation: Bip85AllocationPolicy.blockExactPath,
  );

  static const nostrBullnymServerAuthKey = Bip85Reservation(
    id: 'nostr_bullnym_server_auth_key',
    deterministicAlias: 'Nostr Bullnym Auth',
    owner: Bip85ReservationOwner.nostr,
    purpose: Bip85ReservationPurpose.nonWalletNostrKey,
    application: Bip85ApplicationSpec(
      number: 9000,
      name: 'nostr',
      standard: false,
    ),
    scope: Bip85ReservationScope(
      exactPath: "9000'/2'/1'",
      segments: [
        Bip85PathSegment(name: 'identity', value: 2),
        Bip85PathSegment(name: 'account', value: 1),
      ],
    ),
    allocation: Bip85AllocationPolicy.blockExactPath,
  );

  static const nostrNip05PublicNymVerificationKey = Bip85Reservation(
    id: 'nostr_nip05_public_nym_verification_key',
    deterministicAlias: 'Nostr NIP-05 Public Nym Verification',
    owner: Bip85ReservationOwner.nostr,
    purpose: Bip85ReservationPurpose.nonWalletNostrKey,
    application: Bip85ApplicationSpec(
      number: 9000,
      name: 'nostr',
      standard: false,
    ),
    scope: Bip85ReservationScope(
      exactPath: "9000'/3'/1'",
      segments: [
        Bip85PathSegment(name: 'identity', value: 3),
        Bip85PathSegment(name: 'account', value: 1),
      ],
    ),
    allocation: Bip85AllocationPolicy.blockExactPath,
  );

  static const keychainManifestEncryptionKey = Bip85Reservation(
    id: 'keychain_manifest_encryption_key',
    deterministicAlias: 'Keychain Manifest Encryption',
    owner: Bip85ReservationOwner.keychainManifest,
    purpose: Bip85ReservationPurpose.manifestEncryptionKey,
    application: Bip85ApplicationSpec(
      number: 1642,
      name: 'keychainManifestEncryption',
      standard: false,
    ),
    scope: Bip85ReservationScope(
      exactPath: "1642'/0'/1'",
      segments: [
        Bip85PathSegment(name: 'namespace', value: 0),
        Bip85PathSegment(name: 'key', value: 1),
      ],
    ),
    allocation: Bip85AllocationPolicy.blockExactPath,
  );

  static const all = [
    btcpayWalletSeed,
    lightningAddressWalletSeed,
    paymentPageWalletSeed,
    nostrWalletManifestKey,
    nostrBullnymServerAuthKey,
    nostrNip05PublicNymVerificationKey,
    keychainManifestEncryptionKey,
  ];
}
