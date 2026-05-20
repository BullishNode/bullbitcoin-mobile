const createWalletManifestOriginsTableSql = '''
CREATE TABLE IF NOT EXISTS wallet_manifest_origins (
  wallet_id TEXT NOT NULL PRIMARY KEY,
  root_fingerprint TEXT NOT NULL,
  bip85_derivation_path TEXT NOT NULL,
  network TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE(root_fingerprint, bip85_derivation_path, network)
);
''';
