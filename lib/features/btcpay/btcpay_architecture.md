# BTCPay

BTCPay owns the SamRock pairing surface exposed from Bitcoin Settings.

## Scope

- Entry point: Bitcoin Settings -> BTCPay.
- PR 1 pairs a BTCPay Server store with dedicated BTCPay Bitcoin and Liquid
  wallets.
- Both wallets are deterministic from BIP85 index 77. BTCPay supplies that
  product policy as a caller-provided deterministic wallet request; it does not
  own the wallet materialization machinery.
- SamRock `btc-ln` is supported as Lightning via Liquid/Boltz descriptor
  setup. It does not expose the later Get Paid Lightning Address flow.
- PR 1 does not expose Get Paid navigation, dashboard, automated recovery,
  Lightning Address, Payment Page, invoices, Nostr, Bullnym, wallet manifest
  behavior, auto-sweep, hide-on-home, or wallet display settings.

## Boundaries

- Settings may navigate to BTCPay through `public/btcpay_routes.dart`.
- Settings must not import BTCPay domain, data, presentation, or UI internals.
- BTCPay pairing orchestration belongs in BTCPay use cases under
  `domain/usecases/`.
- BTCPay may consume `features/deterministic_wallets/public/` and must not
  import deterministic wallet internals.
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
  because the SamRock slice prepares both path-77 wallets even when a server
  asks for only one payment rail.
- Before descriptor submission, local wallets created during the current attempt may be rolled back.
- After descriptor submission starts, wallets are kept. Explicit SamRock
  rejection is not saved as a connection; transport/server/unknown completion
  failures are saved as `uncertain`.
- SamRock submits the requested setup in one HTTP call, so PR 1 persists a
  single `uncertain` state rather than pretending to have per-rail server ACKs.
- Pairing state is scoped by wallet environment and persists the BTCPay server
  URL, SamRock store ID, requested capabilities, paired wallet networks, status,
  update timestamp, and pairing timestamp when confirmed.
- Raw exception text is logged only. User-facing uncertain state uses localized
  generic copy.

## Deferred

- Neutral external receive wallet abstractions belong to a later PR only after another concrete consumer exists.
- Full deterministic Get Paid navigation and recovery are stacked on top of
  this feature in a later PR.
- Auto-sweep, hide-on-home, and wallet display controls are generic
  deterministic wallet capabilities. Later Get Paid wallets can use them, but
  they do not belong to SamRock, BTCPay pairing, or the Get Paid feature itself.
