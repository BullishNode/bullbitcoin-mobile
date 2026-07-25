# Nostr-Compatible Identity

Nostr Identity owns Bull's role-named access to BIP85-derived x-only/BIP340 keys. Some roles are used by Nostr features; the wallet-manifest and wallet-metadata roles authenticate opaque Bullnym backup requests and never construct or publish Nostr events.

## Scope

This feature owns:

- role-named xprv-based derivation helpers;
- validation that identity derivation consumes role-appropriate reservations owned by `features/bip85_registry`.

It does not own Nostr relay publishing, Bullnym wire messages, backup payloads, profile event content, UI, storage, rotation, DMs, or user-created Nostr accounts.

## Derivation

Nostr keys use the BIP85 Nostr application path:

```text
m/83696968'/128002'/{identity}'/{account_index}'
```

Reserved roles:

- `100'/1'` => unified Bull backup signing;
- `101'/1'` => Bullnym server authentication;
- `102'/1'` => NIP-05 public nym verification.

Product features must use role-named helpers and must not pass raw identity/account integers at call sites.

## Boundaries

`core/nostr` remains generic: path derivation, hash signing, and public-key
access. Product role semantics live here, not in `core/nostr` and not inside
later receive/Bullnym product features. The concrete reservation paths stay in
`features/bip85_registry`; this feature consumes the current wallet-backup and
Bullnym-auth reservations through its public facade.

The wallet-backup and Bullnym-authentication roles expose public-key derivation
and hash signing without exposing private key material. The NIP-05 verification
role exposes only its public key so registration cannot accidentally use the
public identity as an authentication signer.
