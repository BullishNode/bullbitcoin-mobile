# Wallet Manifest Architecture

Wallet Manifest is a neutral recovery-index feature for Bull-created,
non-default local-key wallets derived from the user's root seed through BIP85.
It is intentionally independent of Get Paid: it should still make sense even if
Lightning Address, Payment Page, and BTCPay were not present.

## Scope

Wallet Manifest owns:

- durable local metadata linking a wallet to its BIP85 origin;
- an application port for local wallet-origin storage;
- BIP139-shaped manifest models and JSON codec;
- Bull's Liquid-aware extension of BIP139 account network values;
- encrypted Nostr publish/fetch of full manifest snapshots;
- manifest restore primitives for BIP85-derived local wallets using generic
  seed/BIP85/wallet primitives.

It does not own product flows, general wallet settings UI, Get Paid manual restore UI,
BTCPay/SamRock server pairing, or the external receive wallet product facade.
`wallet_manifest` must not import or call `external_receive_wallets`; doing so
would create a feature dependency cycle. Product features may consume
`wallet_manifest` through its public facade, but the manifest restore path
remains neutral.

Consumers must use the public facade at
`features/wallet_manifest/public/wallet_manifest.dart`. Product features must
not import `wallet_manifest` internals.

The public facade is the supported boundary for local origin recording, origin
lookup, best-effort local full snapshot publishing used by external receive
wallet flows, and non-blocking automatic restore after app seed recovery. Wallet
Manifest settings uses narrow application use cases for npub display, remote
manifest check, explicit manual publish, and confirmed manual recovery instead
of the broader facade.

## Manifest Shape

The manifest is BIP139-shaped rather than a strict BIP139 export. It uses the
BIP139 account/key layout where it fits and extends network handling for Liquid.

The first production manifest payload is recovery-focused. Each account entry
must include enough information to recreate a deterministic BIP85 wallet:

- `name`: wallet display name;
- `type`: technical account type, usually `bip_380`;
- `network`: per-account network;
- `timestamp`: account metadata update time used for duplicate resolution;
- `keys[*].bip85_derivation_path`: the source of truth for restore;
- `proprietary.bullbitcoin.wallet_type`: Bull semantic wallet type;
- `proprietary.bullbitcoin.bip85_index`: parsed convenience metadata.

`descriptor` and `change_descriptor` may be supported by the codec as optional
metadata, but the first production restore path must not require publishing
descriptors unless another consumer needs them.

Supported network strings:

- `bitcoin`
- `testnet_3`
- `liquid`
- `liquid_testnet`

The top-level BIP139 `network` field is not used as the source of truth because
one Bull manifest can contain Bitcoin and Liquid accounts together.

Restore uses BIP85, not descriptor import. A missing or mismatched descriptor
must not block restore.

## Wallet Types

Manifest wallet types are protocol values:

- `lightning_address`
- `payment_page`
- `btcpay`
- `manual`

The Dart model should expose these as a `WalletManifestWalletType` enum. The
manifest feature may know these values because they are part of the manifest
protocol, but it must not import Get Paid, Lightning Address, BTCPay, or
external receive wallet internals.

Manual wallet labels are restored from `account.name`. If a manual account name
is missing or empty, restore must generate a fallback label such as
`BIP85 Wallet 0`; when both networks at the same index need fallback labels,
use network-specific names such as `BIP85 Wallet 0 BTC` and
`BIP85 Wallet 0 LBTC`.

The restore orchestration layer must make fallback labels collision-resistant
against the restore batch and existing local wallet labels. It may append the
network suffix and, if still needed, a counter. The codec only exposes the
deterministic base fallback label.

Reserved product wallets use canonical labels in product flows. For manifest
restore, classification is based on reserved identity rules below.

## Identity

Manifest wallet identity is:

```text
root_fingerprint + bip85_derivation_path + network
```

The parsed index is used only for reserved identity classification and display:

```text
bip85_index + network
```

The full normalized `bip85_derivation_path` remains part of the durable
identity so supported BIP85 wallet paths cannot collide merely because they
share an index. The current codec accepts Bull's 12-word BIP39 wallet paths;
future BIP85 wallet applications must extend the parser before publishing those
paths in manifests.

Duplicate manifest entries for the same identity collapse to one wallet. Latest
metadata wins, determined by account timestamp if available, otherwise
`created_at`, otherwise a caller-provided manifest event timestamp. If those are
tied, later decoded account order wins deterministically. The app must never
create two local wallets for the same identity.

## Reserved Identities

Reserved identity is index plus network family, not index alone.

Initial reserved identities:

- `75 + liquid` => `lightning_address`
- `76 + liquid` => `payment_page`
- `77 + liquid` => `btcpay`
- `77 + bitcoin` => `btcpay`

Currently not reserved:

- `75 + bitcoin`
- `76 + bitcoin`

Generic BIP85 wallet creation must prevent users from creating reserved
indexes manually. Even though reserved product identity is network-specific for
manifest classification, manual Add Wallet blocks indexes `75`, `76`, and `77`
for every network so users cannot accidentally occupy purpose-wallet space that
may be used by a current or future product flow.

Reserved identity classification overrides declared manifest `wallet_type`.
Non-reserved identities restore as `manual`, even if the manifest declares a
reserved/product wallet type. This preserves recovery while preventing stale or
incorrect product metadata from creating product-owned wallets outside the
reserved identity registry.

The reserved registry is intentionally minimal. It stores only:

```text
bip85_index + network_family -> wallet_type
```

It does not store supported networks, hide-on-home defaults, autosweep defaults,
UI behavior, or product lifecycle rules.

## Manifest Eligibility

Manifest-eligible wallets are Bull-created, non-default, local-key BIP85
wallets created by retained product flows or the generic Add Wallet BIP85
creator.

Included:

- Get Paid reserved BIP85 wallets.
- User-created manual BIP85 wallets for Bitcoin, Liquid, or both.

Excluded:

- default wallets;
- watch-only wallets;
- arbitrary imported mnemonics not created through Bull's BIP85 flow;
- imported descriptor/xpub wallets.

Local wallet-origin metadata is required so full snapshot publishing can be
built from durable wallet origin data instead of labels or heuristics.

The local origin record is per wallet, not per BIP85 derivation, because one
BIP85 mnemonic path can legitimately produce separate Bitcoin and Liquid wallets
with the same root fingerprint and index. The durable identity uniqueness rule
is therefore `root_fingerprint + bip85_derivation_path + network`, while
`wallet_id` is the local primary key.

Local origin storage does not persist `wallet_type`; that value is derived from
the reserved identity registry at read/build time so there is only one source of
truth for product-owned indexes.

Before keeping or extending a separate origin table, compare it against the
existing `bip85_derivations` storage. The derivation table can remain key
derivation history, but wallet/network identity must have durable wallet
linkage. BTCPay reserves both BTC and LBTC identities at BIP85 index `77`, so
alias/path history alone is not enough to identify both wallet origins once
those wallets exist.

## Restore Model

Onboarding physical seed recovery and RecoverBull `recoverVault` start wallet
manifest recovery automatically after default wallet recovery succeeds. This
automatic path is non-blocking and failure-isolated: onboarding/recovery UX
continues if the Nostr fetch, decrypt, decode, or individual wallet restore
fails. Arbitrary mnemonic import does not start wallet manifest recovery.

Wallet manifest recovery is also exposed through explicit primitives and a
confirmed Backup Settings action. Reviewed callers may explicitly:

- fetch the latest valid encrypted manifest snapshot from Nostr;
- pass a fetched snapshot to the restore primitive;
- or use the Backup Settings manual recovery use case that composes fetch and
  restore after user confirmation;
- recreate every manifest-listed wallet from that snapshot;
- do not scan reserved Get Paid paths automatically;
- create no fallback wallets when the manifest is missing, empty, invalid, or
  unavailable;
- recreate listed wallets even if no activity is detected.

Automatic recovery refreshes wallet state again only when the background restore
creates local wallets. It must not make wallet-manifest internals depend on
`WalletBloc`; callers trigger their own post-restore refresh through the public
facade callback.

Manual recovery does not publish a fresh snapshot as a side effect. Fetching,
snapshot restore, manual recovery, and publishing remain separate use cases so
the UI can expose each operation explicitly.

Get Paid manual restore is separate from manifest restore. It exists only as a
fallback when the manifest is missing, failed, or incomplete. It recreates the
currently supported Get Paid wallets without pre-scanning:

- `75 + liquid` Lightning Address;
- `76 + liquid` Payment Page;
- `77 + liquid` BTCPay;
- `77 + bitcoin` BTCPay.

Do not ship a future manifest-only automatic restore path with no user-visible
reserved-wallet recovery fallback.

General BIP85 Add Wallet creation is implemented as a manifest-backed creation
path. It creates Bitcoin, Liquid, or paired Bitcoin/Liquid wallets, records
their local BIP85 origin through the manifest restore primitive, and publishes a
replacement manifest best-effort after local creation. General manual recovery
by arbitrary BIP85 index remains out of scope; users can recreate manifest
listed wallets through Wallet Manifest recovery and can use Get Paid manual
restore for reserved purpose wallets.

## Backup Settings UI

Wallet Manifest controls live under Backup settings. The current implemented
surface shows the dedicated wallet-manifest `npub1...` public key derived from
the wallet manifest Nostr role, allows copying it, checks the latest readable
manifest from Nostr, and allows an explicit manual publish of a full replacement
manifest. It also supports confirmed manual recovery from the latest readable
remote manifest. The UI must not receive xprvs, Nostr signing handles, or
secret-key access.

Implemented actions:

- checking the latest readable wallet manifest from the Nostr network;
- auditing the latest remote manifest wallet identity list against local
  manifest-recorded wallet identities for the current seed without restoring
  wallets or publishing changes;
- viewing and copying the fetched manifest payload;
- saving the fetched manifest payload to a user-selected file location;
- manually creating/publishing a full replacement wallet manifest after
  confirmation;
- manually recovering all manifest-listed wallets after confirmation. This
  fetches from Nostr, mutates local wallets, and does not publish changes.

All network checks must fetch from Nostr rather than reading only local cache.
Publishing, fetching, recovering, and auditing should be separate use cases so
the page remains a diagnostics/control surface over wallet-manifest
infrastructure rather than a product-flow shortcut.

## Wallet Creation Atomicity

Manifest/origin work must follow local wallet creation, not precede it. A
feature should first derive the BIP85 child mnemonic and successfully create and
initialize the underlying BDK/LWK wallet. Only after that succeeds should it
persist wallet-origin metadata or publish a replacement manifest snapshot.

If local wallet creation fails, the feature must not leave a manifest/origin row
claiming the wallet exists. If manifest publishing fails, local wallet creation
still succeeds; publishing is best-effort recovery metadata.

If local wallet creation succeeds but origin persistence fails, do not publish a
replacement snapshot that omits the wallet. Surface or repair the origin failure
before publishing, or mark the wallet as needing origin repair. Full replacement
snapshots must also avoid erasing accounts after partial restore: publish after
restore only when every fetched account was restored/already present, or carry
unrecovered fetched entries forward.

## Nostr Storage

Use a dedicated BIP85-derived Nostr key for wallet manifests. Do not reuse the
Bullnym server-authentication key or the public NIP-05 verification key.

Current wallet manifest publish/fetch code must use the dedicated wallet-
manifest Nostr role. Do not preserve or add shared-key manifest paths.

Nostr keys follow the draft BIP85 Nostr application path:

```text
m/83696968'/9000'/{identity}'/{account_index}'
```

Reserved Nostr identities:

- `1'/1'` => wallet manifest publishing and recovery;
- `2'/1'` => Bullnym server authentication;
- `3'/1'` => NIP-05 / public nym verification.

Identity `0'` and account `0'` are reserved by the draft BIP85 Nostr
application. Manual/user-created Nostr identities must not use Bull-reserved
identity/account pairs.

No production wallet manifests have been published. This branch ships only the
dedicated wallet-manifest Nostr role for manifest publish/fetch and does not
include any alternate manifest read path or manifest migration.

The Bullnym/NIP-05 split requires a backend contract, not only local key
derivation. Registration/authentication must continue to be signed by the
Bullnym server-authentication key, while the server must know which npub should
be returned by the NIP-05 endpoint. Until that contract is implemented, do not
publish kind:0 NIP-05 metadata from the dedicated NIP-05 key.

Planned backend contract:

- mobile derives both `9000'/2'/1'` and `9000'/3'/1'`;
- registration and authenticated updates are signed with `9000'/2'/1'`;
- registration includes the public verification npub from `9000'/3'/1'`;
- Bullnym stores that verification npub with the nym;
- `/.well-known/nostr.json` resolves the nym to the verification npub;
- profile publish/clear uses `9000'/3'/1'`.

Because no production Bullnym identity split has shipped, mobile and Bullnym
can move directly to this contract together. Do not ship a combined
auth/profile fallback.

The reserved identity constants and role-specific derivation helpers live in the
shared Nostr identity boundary. Product code must use role-named helpers such as
`deriveWalletManifestHandle`, `deriveBullnymServerAuthHandle`, and
`deriveNip05VerificationHandle`; product features should not pass raw
identity/account integers at call sites.

Wallet manifests are published as encrypted Nostr events through a relay port.
Do not use Whitenoise/Marmot in this phase.

Event constants:

```text
kind: 30078
d: manifest
```

The `d` tag is intentionally generic. Because wallet manifests use a dedicated
npub, `manifest` does not link the user's public nym or Bullnym authentication
identity to the recovery manifest. Do not publish public tags containing
`bullbitcoin`, `wallet_manifest`, `manifest_version`, or `client`; put
version/schema data inside encrypted content.

Fetch rules:

- filter by author, kind, and `#d`;
- request several candidates, suggested limit `10`;
- sort newest-first;
- decrypt/parse candidates newest-first;
- use the first valid full snapshot;
- do not merge across older snapshots.

Publishing rules:

- publish a full replacement snapshot after manifest-eligible wallet
  creation/update;
- publish immediately after local wallet creation, before wallet sync;
- a reviewed recovery caller may publish after manifest restore only when the
  publish preserves every fetched account or carries unrecovered entries
  forward;
- publish after manifest-eligible wallet rename;
- publishing is always best-effort and non-blocking.

Deletion/removal semantics are out of scope. Do not change existing wallet
deletion behavior, and do not publish manifest deletions in this phase.
This accepted tradeoff means a deleted manifest-eligible wallet can reappear
after seed restore if the latest published manifest still lists it. Future
delete/revocation UX must address that deliberately.
