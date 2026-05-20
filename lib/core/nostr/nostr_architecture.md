# Core Nostr

`core/nostr` is the app-wide Nostr boundary. It owns generic key derivation,
Schnorr signing, public-key access, and relay publishing primitives.

Feature-specific protocol semantics stay outside this package. Bullnym actions,
Lightning Address message fields, invoices, payment pages, NIP-05 naming rules,
and UI recovery policy belong to their feature layers.

## BIP85 Derivation

Nostr keys are derived with BIP85 application `9000`:

`m/83696968'/9000'/{identity}'/{account_index}'`

Generic callers may pass both `identity` and `account` explicitly, but Bull
product features should use the role-named helpers exported by
`features/nostr_identity/public/nostr_identity.dart`.

Lightning Address's separate Liquid receive wallet still uses BIP85 mnemonic
index `75`; that wallet index is not a Nostr identity number.

## Public Surface

- `NostrKeychainHandle` wraps the dart-nostr key object and keeps the secret key
  private behind callback-scoped access.
- `NostrKeychainHandle` derives role-scoped keys, returns x-only public keys,
  and signs messages.
- `NostrRelayClient` publishes already-built Nostr events to relays and can
  fetch events with explicit caller-owned filters.

## Boundaries

- DTOs and persistence models must not contain `NostrKeychainHandle`.
- Feature layers pass public keys, signatures, or callback-scoped secrets across
  their own ports.
- Feature layers own their protocol-specific event contents. For example,
  Lightning Address owns the NIP-05/LUD16 kind:0 profile metadata shape and only
  uses core Nostr to broadcast the completed event.
- `toString()` implementations must never include secret-key material.
- Bullnym/Bullpay signing belongs under Get Paid shared protocol, not here.
