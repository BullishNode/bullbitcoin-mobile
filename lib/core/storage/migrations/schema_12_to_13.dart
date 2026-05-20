import 'package:drift/drift.dart';

class Schema12To13 {
  static Future<void> migrate(Migrator m, dynamic schema12) async {
    await m.database.customStatement(r"""
CREATE TABLE IF NOT EXISTS bip85_derivations_v13 (
  path TEXT NOT NULL,
  xprv_fingerprint TEXT NOT NULL,
  application TEXT NOT NULL,
  status TEXT NOT NULL,
  usage TEXT NOT NULL DEFAULT 'manual',
  alias TEXT NULL,
  PRIMARY KEY (xprv_fingerprint, path)
);
""");

    await m.database.customStatement(r"""
INSERT OR REPLACE INTO bip85_derivations_v13 (
  path,
  xprv_fingerprint,
  application,
  status,
  usage,
  alias
)
SELECT
  path,
  xprv_fingerprint,
  application,
  status,
  'manual',
  alias
FROM bip85_derivations;
""");

    await m.database.customStatement('DROP TABLE bip85_derivations;');
    await m.database.customStatement(
      'ALTER TABLE bip85_derivations_v13 RENAME TO bip85_derivations;',
    );

  }
}
