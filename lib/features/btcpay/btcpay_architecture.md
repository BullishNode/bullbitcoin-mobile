# BTCPay

BTCPay owns the SamRock pairing surface exposed from Bitcoin Settings.

## Scope

- Entry point: Bitcoin Settings -> BTCPay.
- BTCPay pairs a BTCPay Server store with dedicated BTCPay Bitcoin and Liquid
  wallets.
- Both wallets are deterministic from the BIP85 registry's BTCPay reservation:
  BIP39 English 12-word path `39'/0'/12'/100'`. BTCPay consumes that reserved
  path and canonical deterministic alias through the registry public boundary
  and supplies wallet specs as a caller-provided deterministic wallet request;
  it does not own the wallet materialization machinery.
- SamRock `btc-ln` is supported as Lightning via Liquid/Boltz descriptor
  setup. It does not expose the later Lightning Address flow.
- BTCPay applies generic wallet-owned behavior defaults to the dedicated BTCPay
  wallets after SamRock accepts descriptor submission. BTCPay Liquid is hidden
  from Home and auto-sweep enabled by default; BTCPay Bitcoin is visible and
  auto-sweep disabled by default.
- BTCPay records one local Keychain Manifest reserved derivation with Bitcoin
  and Liquid wallet materializations immediately after deterministic wallets are
  prepared, before SamRock payload construction and before descriptors are
  submitted. If that local record step fails before submission, descriptors are
  not shared, and prepared wallets are kept for retry.
- BTCPay applies wallet behavior defaults best-effort after server acceptance.
  A defaults failure is logged and never degrades a successful pairing; the
  same settings stay editable from the BTCPay details screen.
- BTCPay exposes those generic wallet behavior settings from the BTCPay details
  screen only.
- BTCPay does not expose product receive navigation, dashboard, automated recovery,
  Lightning Address, Payment Page, invoices, Nostr, Bullnym, wallet manifest
  behavior, manual BIP85 creation, or non-BTCPay wallet behavior settings.

## Boundaries

- Settings may navigate to BTCPay through `public/btcpay_routes.dart`.
- Settings must not import BTCPay domain, data, presentation, or UI internals.
- BTCPay pairing orchestration belongs in BTCPay use cases under
  `domain/usecases/`.
- BTCPay may consume `features/deterministic_wallets/public/` and must not
  import deterministic wallet internals.
- BTCPay may consume `features/bip85_registry/public/` and must not import
  registry internals. The registry is reserved path/purpose policy only, not
  runtime wallet/key state.
- BTCPay may consume `features/keychain_manifest/public/` and must not import
  keychain manifest internals. Keychain Manifest records local derivation
  metadata for app-created BIP85 materializations; it never stores mnemonic
  words, seeds, private keys, or descriptors.
- BTCPay may consume wallet behavior use cases to apply and edit settings for
  its own wallets. The wallet layer owns the flags and persistence.
- BTCPay does not own the auto-sweep runner. It only enables the generic
  wallet-owned flag for the Liquid BTCPay wallet by default.
- BTCPay UI consumes presentation state and view models. It must not import
  BTCPay errors or domain entities directly.
- BTCPay UI and Cubits must not create wallets, derive BIP85 material, submit
  descriptors, or decide rollback behavior directly.
- BTCPay stores its pairing connection through
  `BtcpayConnectionRepository`, whose implementation persists a wire model
  via the existing secure key-value storage abstraction. Datasources are
  private members of their repository and are never reached from
  presentation or UI.

## Layers

- `domain/`: SamRock request parsing, BTCPay connection entity, BTCPay wallet
  policy constants, network mapping, the `BtcpayConnectionRepository`
  contract, the `SamRockPairingServicePort` capability port, the SamRock
  setup payload builder, and the sealed `BtcpayError` family in
  `btcpay_error.dart`.
- `domain/usecases/`: preview, connection fetch, and full SamRock pairing
  orchestration.
- `data/models/`: the `BtcpayConnectionModel` wire model owning JSON
  encode/decode and the model <-> entity mapping.
- `data/`: `BtcpayConnectionRepositoryImpl`, which owns its datasource and
  maps wire models to domain entities.
- `data/datasources/`: secure-storage connection datasource (returns wire
  models only) and HTTP SamRock datasource.
- `presentation/`: Cubit state, error mapping, loading/submitting/success
  states, and connection view models.
- `ui/screens/`: settings and scanner screens.
- `public/`: route exported to Settings.

## Pairing Contract

- Users must explicitly consent before descriptors are submitted to BTCPay.
- The consent copy always discloses both dedicated Bitcoin and Liquid wallets
  because the SamRock slice prepares both BTCPay reservation wallets even when
  a server asks for only one payment rail.
- The BTCPay Liquid wallet defaults to hidden on Home and auto-sweeps received
  funds to the default Liquid wallet. These settings remain editable from the
  BTCPay details screen.
- Explicit SamRock rejection after descriptor submission is not saved as a
  connection, but prepared wallets plus keychain manifest entries are kept so a
  later retry can reuse the same deterministic materialization.
- Transport/server/unknown completion failures are saved as `uncertain`, and
  wallets plus keychain manifest entries are kept because remote completion
  cannot be confirmed.
- Wallet behavior default failures after server acceptance are logged and do
  not fail the pairing. BTCPay does not roll back already materialized wallets
  because behavior settings can be retried independently.
- SamRock submits the requested setup in one HTTP call, so BTCPay persists a
  single `uncertain` state rather than pretending to have per-rail server ACKs.
- Pairing state is scoped by wallet environment and persists the BTCPay server
  URL, SamRock store ID, requested capabilities, paired wallet networks, status,
  update timestamp, and pairing timestamp when confirmed.
- Raw exception text is logged only. User-facing uncertain state uses localized
  generic copy.
