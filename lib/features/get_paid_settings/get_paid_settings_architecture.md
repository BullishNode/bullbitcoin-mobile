# Get Paid Settings

Get Paid Settings owns the reserved Get Paid wallets' behavior controls — the Auto-Sweep and Hide-on-Home rules for the fixed-derivation Lightning Address, Donation Page and Point of Sale wallets — and the shared Advanced Settings sheet every Get Paid product screen opens.

## Scope

This feature owns:

- resolving the reserved product wallets and their current behavior (`GetGetPaidWalletBehaviorsUsecase`, over the keychain manifest);
- writing those behaviors through the core wallet behavior use case;
- the Advanced Settings sheet and the wallet-behavior card that state the two switches, their labels, their ordering and the rule coupling them, once, for every product.

It does not own product configuration, registration, nym claiming, or any product's online/offline action. Each product screen injects its own turn-on/off action and its own writes.

## Public Surface

`public/` is the only importable surface. It carries the facade plus every widget another feature renders:

- `get_paid_settings_facade.dart` — behavior reads + writes;
- `get_paid_advanced_settings_sheet.dart` — the shared sheet;
- `get_paid_wallet_behavior_card.dart` — the two switches as one card;
- `get_paid_nym_claim_step.dart` — the one-field Bull Nym claim step;
- `get_paid_name_choice.dart` — the name a surface will advertise;
- `get_paid_link_qr.dart` + `get_paid_link_qr_saver.dart` — a surface's public link, its QR, and the PNG save seam.

A widget consumed cross-feature lives in `public/`, not in `ui/` — the same shape as `fiat_settlement/public/fiat_settlement_entry_tile.dart` and `invoices/public/invoice_copy.dart`. No feature may reach past `public/` into this feature's internals, and none of these widgets belongs in `lib/core/`: they carry Get Paid product copy and affordances, which is business UI, while core is infrastructure. The generic paired-switch layout lives in `bull_ui`; this feature supplies the Get Paid copy and the domain-derived availability state.

The published entity lives in `domain/get_paid_wallet_behavior.dart`, not inside a use-case file: what the facade publishes must have a home a consumer can read without opening this feature's internals. The facade is callback-injected (the Lightning Address / Payment Page / POS precedent), so no consumer — production code or test — has to name an internal use case to reach the boundary.

## Dependencies

`product screen -> public widgets` (presentational) and `product cubit -> its own wrapper use case -> GetPaidSettingsFacade -> GetGetPaidWalletBehaviorsUsecase -> KeychainManifestFacade`.

No consuming Cubit calls this facade directly. Each product feature owns a wrapper use case pair over it — `Get<Product>WalletBehaviorUsecase` and `Update<Product>WalletBehaviorUsecase`. Reads map the foreign result into the consumer's own `found`, `absent`, or `unavailable` outcome; writes map failure to `false`. This feature's failures therefore never surface as foreign exceptions inside another feature's presentation layer. The Lightning Address, Donation Page and Point of Sale edges are recorded in `FEATURES.md`.
