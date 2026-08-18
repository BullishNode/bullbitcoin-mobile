# Backup Settings Architecture

`backup_settings` is the global user-facing home for wallet backup controls.
It keeps the existing physical and RecoverBull vault status/actions and adds
the single encrypted Bull backup lifecycle.

Backup-settings-owned use cases import `wallet_backup/public`, map its failures into the `backup_settings` failure family, and expose the result to the presentation layer. The presentation never calls the foreign facade directly. It watches the one `WalletBackupState` and exposes:

- one automatic-backup enable switch;
- pending, last-success, and newer-version-blocked status;
- one explicit “Back up now” action;
- one confirmed remote-delete action, available only after publishing is
  disabled.

The presentation maps typed failures to sanitized user messages. It never receives seed material, xprvs, encryption keys, Nostr private keys, plaintext backup sections, Bullnym request details, or remote ciphertext.

```text
backup_settings
  -> wallet_backup/public
```

Get Paid feature settings do not own or duplicate these controls.
