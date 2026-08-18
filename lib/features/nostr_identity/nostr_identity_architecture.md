# Nostr Identity

Nostr Identity owns Bull's role-named access to reserved BIP85 Nostr keys. It is
a planned shared boundary for Get Paid, Lightning Address, wallet manifest
recovery, and future Nostr-backed product features.

## Scope

This feature owns:

- role-named xprv-based derivation helpers;
- validation that Nostr identity derivation consumes reservations owned by
  `features/bip85_registry`.

It does not own Nostr relay publishing, Bullnym wire messages, wallet manifest
events, profile event content, UI, storage, rotation, DMs, or user-created Nostr
accounts.

## Derivation

Nostr keys use the BIP85 Nostr application path:

```text
m/83696968'/128002'/{identity}'/{account_index}'
```

Reserved roles:

- `100'/1'` => unified Bull backup signing;
- `101'/1'` => Bullnym server authentication;
- `102'/1'` => NIP-05 public nym verification.

Product features must use role-named helpers and must not pass raw
identity/account integers at call sites.

## Boundaries

`core/nostr` remains generic: path derivation, hash signing, and public-key
access. Product role semantics live here, not in `core/nostr` and not inside
later receive/Bullnym product features. The concrete reservation paths stay in
`features/bip85_registry`; this feature consumes the current wallet-backup and
Bullnym-auth reservations through its public facade.

These roles are reserved for Bullnym backup signing, Bullnym auth, and public
nym verification. This PR exposes only wallet-backup and Bullnym-auth
public-key/signing helpers; it does not implement those protocols or events.
