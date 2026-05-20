# Get Paid Architecture

Get Paid is a product surface that coordinates payment receiving features while
keeping their implementation boundaries intact.

## Scope

The dashboard reads Lightning Address state through `LightningAddressFacade`,
Payment Page state through Payment Page use cases, links to invoice routes
owned by the Invoices sub-feature, and can route into the BTCPay/SamRock pairing
flow. Get Paid is currently reachable from the app shell bottom navigation. It
does not move Lightning Address.

## Dependencies

- `features/lightning_address/public/lightning_address_facade.dart` is the only
  Lightning Address dependency.
- `features/get_paid/payment_page/application/` is consumed through use cases.
- `features/get_paid/payment_page/ui/` owns Payment Page editing.
- `features/get_paid/invoices/ui/` owns invoice list/create/detail routes.
- `features/get_paid/btcpay/` owns SamRock pairing URL parsing and BTCPay local
  wallet preparation.
- `features/bullnym/` remains the protocol boundary.
- `features/external_receive_wallets/` owns Get Paid external receive wallet
  creation/lookup/sweep behavior for Lightning Address, Payment Page, and
  BTCPay through a thin public facade.
- `features/wallet_manifest/` owns the neutral BIP85 wallet recovery index,
  BIP139-shaped manifest codec, and encrypted Nostr manifest publish/fetch.
  Server pairing and feature-specific recovery stay in their owning sub-feature
  flows. `wallet_manifest` restores with generic seed/BIP85/wallet primitives;
  it does not call `external_receive_wallets`.
  Payment Page does not yet provision its `Payment Page-LBTC` wallet on save
  because the current server API does not bind Payment Page to that descriptor.
  This avoids durable wallet churn before the descriptor-binding server phase.

## Dashboard Flow

1. `GetPaidDashboardCubit.refresh()` reads the current Lightning Address from
   `LightningAddressFacade`.
2. If no Lightning Address exists, the dashboard shows the Lightning Address
   setup action and does not query Payment Page.
3. If a Lightning Address exists, the cubit derives the nym and loads the
   active Payment Page with `FindPaymentPageUsecase`.
4. Sub-feature screens return `true` after a mutation. The dashboard refreshes
   only when that value is returned, or on pull-to-refresh/app-resume.

## Boundaries

Payment Page archive only archives the page. Lightning Address deactivation
stays in Lightning Address settings. The dashboard may navigate to those
screens, but it does not compose their write operations.

## Deferred

Connected-server state, disconnect, QR scanner polish, saved server list/status,
and broader dashboard polish remain outside this slice. Payment Page supports
social preview image upload from the editor.

## Wallet Recovery

Wallet manifest publish/fetch/restore primitives exist. After onboarding or
RecoverBull restores the app seed and default wallets, the app starts a
non-blocking wallet manifest restore job. This job fetches the latest encrypted
manifest from Nostr and recreates manifest-listed Bull-created BIP85 wallets
without blocking the main recovery UX. Failures are logged and left to manual
Wallet Manifest or Get Paid recovery surfaces.

The manifest is the explicit wallet list. Manifest-listed wallets are recreated
even if no balance or transaction history has been detected. The tradeoff is
that recreating empty BIP85 wallets can add wallets to normal sync and may make
future wallet syncs slower.

Get Paid Settings owns a manual reserved-wallet recovery action for supported
Get Paid reserved wallets when the manifest is missing, failed, or incomplete.
The action is confirmed because it can recreate empty reserved wallets and add
them to future wallet sync. When recovery creates or repairs local wallets, it
may also best-effort publish an updated encrypted wallet manifest to Nostr. The
current supported set is:

- `75 + liquid` Lightning Address;
- `76 + liquid` Payment Page;
- `77 + liquid` BTCPay;
- `77 + bitcoin` BTCPay.

Local Get Paid wallet creation must be atomic: the BIP85-derived wallet must be
successfully created locally before origin metadata or manifest publication is
attempted. Manifest publication is best-effort and must not block the product
flow.

## Get Paid Settings

Hide-on-home and autosweep controls for Get Paid receive wallets live under Get
Paid Settings, not on the individual product screens. The settings apply through
the neutral external receive wallet boundary for Lightning Address, Payment
Page, and BTCPay receive wallets. Wallet list visibility is driven by
manifest-backed external receive wallet ids plus per-purpose hide settings, not
by reserved labels or Lightning Address-specific state.

Lightning Address product pages should focus on Lightning Address product state
such as current address, publish/unpublish, and nym/profile behavior.

## BTCPay State

BTCPay uses reserved path-77 wallet identities and Get Paid manual recovery
rows. SamRock local wallet preparation is separate from server pairing: creating
the BTCPay BTC/LBTC wallets only makes local descriptors available, and the
dashboard must not show connected/ready until SamRock server confirmation
succeeds. Manifest publication for BTCPay happens only after all requested
local wallets exist; connected-server state remains BTCPay/SamRock-owned.

Current BTCPay implementation:

- parses HTTPS SamRock protocol URLs ending in `/samrock/protocol`;
- requires non-empty `otp`;
- reads `setup` capabilities and supports `btc-chain`/`btc`,
  `liquid-chain`/`lbtc`, `btc-ln`/`btcln`, omitted setup, and `setup=all`;
- creates or reuses the requested BTCPay path-77 Bitcoin/Liquid wallets after a
  pairing request is supplied;
- creates/reuses the BTCPay Liquid wallet for Lightning setup because SamRock
  `BTCLN` is Boltz-backed and carries Liquid descriptor data;
- submits the SamRock `json` form field with `BTC`, `LBTC`, and/or `BTCLN`
  descriptor data to the BTCPay protocol URL;
- publishes the wallet manifest once after SamRock server acceptance,
  best-effort;
- exposes a dashboard BTCPay entry point with manual SamRock URL input.
