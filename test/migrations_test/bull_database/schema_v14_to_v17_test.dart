import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';
import 'generated/schema_v14.dart' as v14;
import 'generated/schema_v17.dart' as v17;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('seeded v14 upgrades cumulatively to the complete v17 schema', () async {
    final schema = await verifier.schemaAt(14);
    final oldDb = v14.DatabaseAtV14(schema.newConnection());
    await oldDb
        .into(oldDb.walletMetadatas)
        .insert(
          v14.WalletMetadatasCompanion.insert(
            id: 'wallet-1',
            masterFingerprint: 'f00dbabe',
            xpubFingerprint: 'deadbeef',
            isEncryptedVaultTested: 1,
            isPhysicalBackupTested: 0,
            xpub: 'xpub-test',
            externalPublicDescriptor: 'external-descriptor',
            internalPublicDescriptor: 'internal-descriptor',
            signer: 'local',
            isDefault: 1,
          ),
        );
    await oldDb
        .into(oldDb.settings)
        .insert(
          v14.SettingsCompanion.insert(
            environment: 'mainnet',
            bitcoinUnit: 'sats',
            language: 'en',
            currency: 'CAD',
            hideAmounts: 0,
            isSuperuser: 1,
            payjoinEnabled: const Value(1),
            payjoinMinAmountSat: const Value(31000),
            payjoinExpireAfterSec: const Value(2400),
          ),
        );
    await oldDb
        .into(oldDb.payjoinSenders)
        .insert(
          v14.PayjoinSendersCompanion.insert(
            uri: 'bitcoin:bc1qexample?pj=https://payjoin.example',
            isTestnet: 0,
            sender: 'sender-id',
            walletId: 'wallet-1',
            originalPsbt: 'cHNidP8BAAoCAAAAAQ==',
            originalTxId: '22' * 32,
            amountSat: 51000,
            createdAt: 1700000000,
            expireAfterSec: 2400,
            isExpired: 0,
            isCompleted: 0,
          ),
        );
    await oldDb
        .into(oldDb.dismissedAnnouncements)
        .insert(
          v14.DismissedAnnouncementsCompanion.insert(
            announcementId: 'security-notice',
            dismissedAt: '2026-07-30T13:00:00Z',
          ),
        );
    await oldDb.close();

    final db = SqliteDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 17);
    await db.close();

    final migratedDb = v17.DatabaseAtV17(schema.newConnection());
    final wallet = await migratedDb
        .select(migratedDb.walletMetadatas)
        .getSingle();
    expect(wallet.id, 'wallet-1');
    expect(wallet.hideOnHome, isNull);
    expect(wallet.autoSweepEnabled, isNull);
    final settings = await migratedDb.select(migratedDb.settings).getSingle();
    expect(settings.currency, 'CAD');
    expect(settings.isSuperuser, 1);
    expect(settings.payjoinMinAmountSat, 31000);
    expect(settings.payjoinExpireAfterSec, 2400);
    final payjoin = await migratedDb
        .select(migratedDb.payjoinSenders)
        .getSingle();
    expect(payjoin.walletId, 'wallet-1');
    expect(payjoin.amountSat, 51000);
    expect(payjoin.originalTxId, '22' * 32);
    final announcement = await migratedDb
        .select(migratedDb.dismissedAnnouncements)
        .getSingle();
    expect(announcement.announcementId, 'security-notice');
    expect(announcement.dismissedAt, '2026-07-30T13:00:00Z');

    await migratedDb
        .into(migratedDb.walletBackupStates)
        .insert(
          v17.WalletBackupStatesCompanion.insert(
            recoveryBlocked: const Value(1),
          ),
        );
    final backup = await migratedDb
        .select(migratedDb.walletBackupStates)
        .getSingle();
    expect(backup.recoveryBlocked, 1);

    const entryId = "f00dbabe:128002'/1'/1'";
    await migratedDb
        .into(migratedDb.keychainManifestEntries)
        .insert(
          v17.KeychainManifestEntriesCompanion.insert(
            entryId: entryId,
            parentFingerprint: 'f00dbabe',
            bip85DerivationPath: "128002'/1'/1'",
            reservationId: 'nostr_user_key',
            entryType: 'userGenerated',
            ownerFeature: 'nostr',
            bip85Application: 128002,
            bip85Index: 1,
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    await migratedDb
        .into(migratedDb.keychainManifestNostrKeys)
        .insert(
          v17.KeychainManifestNostrKeysCompanion.insert(
            entryId: entryId,
            publicKeyHex: 'cd' * 32,
            keyKind: 'userGenerated',
            purpose: 'Recovered identity',
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    expect(
      await migratedDb.select(migratedDb.keychainManifestNostrKeys).get(),
      hasLength(1),
    );
    await migratedDb.close();
  });
}
