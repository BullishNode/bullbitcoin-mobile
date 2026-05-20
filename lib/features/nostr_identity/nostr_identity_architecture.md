# Nostr Identity

Nostr Identity owns Bull's reserved BIP85 Nostr role mapping. It is a small
shared boundary between Get Paid, Lightning Address, wallet manifest recovery,
and future Nostr-backed product features.

## Scope

This feature owns:

- reserved BIP85 Nostr role constants;
- role-named derivation helpers for existing xprv call sites.

It does not own Nostr relay publishing, Bullnym wire messages, wallet manifest
events, profile event content, UI, storage, rotation, or user-created Nostr
accounts.

## Derivation

Nostr keys use the draft BIP85 Nostr application path:

```text
m/83696968'/9000'/{identity}'/{account_index}'
```

Reserved roles:

- `1'/1'` => wallet manifest publishing and recovery;
- `2'/1'` => Bullnym server authentication;
- `3'/1'` => NIP-05 / public nym verification.

Identity `0'` and account `0'` are reserved by the draft BIP85 Nostr
application. Product features must use role-named helpers and must not pass raw
identity/account integers at call sites.

## Boundaries

`core/nostr` remains generic: key derivation, signing, public-key access, and
relay primitives. Product role semantics live here, not in `core/nostr` and not
inside `external_receive_wallets`.

Bullnym registration/auth updates use the Bullnym server-authentication key.
The NIP-05 endpoint resolves to the NIP-05 verification key. Wallet manifest
events use the wallet manifest key.
