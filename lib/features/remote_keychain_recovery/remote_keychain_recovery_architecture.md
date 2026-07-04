# Remote Keychain Recovery Architecture

## Scope

`remote_keychain_recovery` orchestrates recovering the Get Paid deterministic
wallets from the encrypted Nostr backup and drives the recovery UI. It checks
the relays for a manifest (authenticated-recency selection), restores the
selected import plan through `keychain_recovery`, interprets the result for the
user (all statuses, including the KC-2 "newer version" and the decision-[D]
older-restore warning), runs the DG-3 auto-heal for recovered bullnym-backed
products, and republishes the backup after a latest-manifest restore.

It does not own manifest fetch/decrypt mechanics, the wire transport, the codec,
or the restore materializer (those are `keychain_manifest` /
`keychain_recovery`); it does not own the backup preference, the publish gate,
or the relay list (those are `get_paid_settings` / `nostr_relay_policy`); and it
does not own product activation (`lightning_address`).

The recovery-fetch disclosure gate is sourced from the SAME persisted
acknowledgement the creation-time consent writes (R2-P21c): `start()` resolves
the effective disclosure as an explicit accept OR the persisted ack, so the
consent shown once at creation is honoured at recovery.

Republish discipline (§3.11/§8.3): after a **latest**-manifest restore the
backup republishes (the toggle/consent/empty gates still apply in the
chokepoint); after an **older**-approved restore it does NOT republish — a fresh
NIP-33 event would clobber a newer, this-binary-unreadable manifest on the
relays. No republish fires on `unsupportedNewerManifest` (nothing is restored).

## Boundaries

Allowed dependencies:

- `remote_keychain_recovery -> keychain_manifest/public`
- `remote_keychain_recovery -> keychain_recovery/public`
- `remote_keychain_recovery -> nostr_relay_policy/public`
- `remote_keychain_recovery -> lightning_address/public` (DG-3 heal + the
  exported `LightningAddressHealOutcome` contract type rendered by the UI)
- `remote_keychain_recovery -> get_paid_settings/public` (persisted consent +
  the publish chokepoint)
- `remote_keychain_recovery -> core/*`

Forbidden dependencies:

- `remote_keychain_recovery -> btcpay`
- `remote_keychain_recovery -> bullnym` (direct; the heal goes through
  `lightning_address/public`)
- `remote_keychain_recovery -> keychain_manifest/domain | .../data` internals

## Contract semantics

- The DG-3 heal is a conditional liveness check with silent re-register, never
  an unconditional reactivation prompt. `healOutcome` is the rendered
  interpretation; `hasProductReactivationRequired` stays the raw restore signal.
- Payment Page (102) is recovered wallet-only (no page client surface yet), so
  it contributes no heal outcome.
- Known residual (§13 Q9): after an older-approved restore, a user who later
  flips the settings toggle OFF->ON fires a catch-up publish that could replace
  a newer unreadable relay backup. Automatic suppression there would need a
  fetch-before-publish recency check — out of PR23 scope.
