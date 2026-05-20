# External Receive Wallets Architecture

This feature owns local wallets whose descriptors are shared with an external
Get Paid surface, such as Lightning Address, Payment Page, or BTCPay.

It is intentionally neutral: Lightning Address and Get Paid both depend on this
feature, but this feature does not depend on either of them. This avoids a
feature dependency cycle while keeping wallet creation, lookup, recovery, and
sweep behavior in one place.

## Account Identity

External receive wallet accounts are identified by:

```text
purpose + network
```

The BIP85 index is purpose-level:

- Lightning Address: 75
- Payment Page: 76
- BTCPay: 77

Network-specific labels are display labels, not the long-term durable identity.
This feature has not shipped, so there is no legacy Lightning Address, Payment
Page, or BTCPay label compatibility requirement.

## Current Scope

- Liquid account lookup and creation for Lightning Address, Payment Page, and
  BTCPay.
- Bitcoin account lookup and creation for BTCPay.
- Canonical reserved labels for product wallets.
- Reserved-label blocking for user-created wallets.
- Liquid sweep support used by Lightning Address.
- Product-level creation of reserved external receive wallets for Get Paid
  surfaces.
- A thin public facade for create/get/classification/sweep primitives.
- Manual restoration of the fixed reserved external receive wallet set:
  Lightning Address Liquid, Payment Page Liquid, BTCPay Liquid, and BTCPay
  Bitcoin.

## Settings

Hide-on-home and autosweep settings are account settings keyed by purpose plus
network family. New callers should pass explicit account keys whenever a
product can support more than one network. Purpose-only calls are limited to
single-network products where the default Liquid account is the intended
account.

Defaults:

- Liquid external receive wallets: hide on home enabled, autosweep enabled.
- Bitcoin external receive wallets: hide on home disabled, autosweep disabled.

Wallet classification uses manifest origin metadata to resolve the account key
for each local wallet, then applies the matching account settings. Bitcoin
external receive wallets must not inherit Liquid hiding/autosweep defaults just
because they share the same purpose.

Product orchestration and UI copy stay outside this feature. For example, Get
Paid Advanced can expose a manual reserved-wallet recovery action, but it
should call the external receive wallet facade instead of duplicating BIP85
indexes, networks, or repair rules.

## Wallet Manifest Boundary

Manifest storage and automatic seed-restore indexing belong to the neutral
`features/wallet_manifest` feature, not to external receive wallets. External
receive wallets may trigger manifest publication through the public wallet
manifest facade after local wallet creation, but `wallet_manifest` restore must
not call back into `external_receive_wallets`.

The old transitional `ExternalReceiveWalletManifest` adapter from the
pre-`wallet_manifest` design is quarantined from runtime and must not be
reintroduced. The manifest-integration subphase must publish/recover through
the `wallet_manifest` public facade and BIP139-shaped snapshot publisher.

Manifest publish must be a best-effort add-on. Local external wallet creation
must not require manifest publication to succeed.

Automatic seed-recovery restore is handled by `wallet_manifest`, not by external
receive wallets. Onboarding physical seed recovery and RecoverBull start a
non-blocking manifest restore after default wallet recovery succeeds. That
automatic path restores only manifest-listed wallets; it must not scan `75`,
`76`, or `77` automatically, and must create no fallback wallets when the
manifest is missing, empty, invalid, or unavailable. The Get Paid Settings
manual restore flow is the explicit fallback when manifest recovery fails or is
incomplete. That UI flow should call this feature's reserved external receive
wallet restore primitive.

Manifest publishing is best-effort recovery metadata. Local external receive
wallet creation must first succeed locally, then publish/update the manifest.
Relay or encryption failure must not make wallet creation fail.

Generic Add Wallet manual BIP85 wallets are not external receive wallets. They
use the same wallet-manifest recovery index, but they do not get product
purpose, descriptor-sharing, hide-on-home, or autosweep behavior from this
feature.

## Lightning Address Boundary

Lightning Address must not own generic external receive wallet recovery or
sweep behavior. Non-Lightning callers should depend on this feature's public
facade, not `LightningAddressFacade`. `LightningAddressFacade` should remain
limited to nym registration/status, publish/unpublish, NIP-05/profile behavior,
and Lightning Address product state.
