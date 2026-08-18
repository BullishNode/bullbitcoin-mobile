import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';
import 'generated/schema_v14.dart' as v14;
import 'generated/schema_v15.dart' as v15;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test(
    'v14 to v15 preserves wallets and adds net backup persistence',
    () async {
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
              label: const Value('Primary wallet'),
            ),
          );
      await oldDb
          .into(oldDb.settings)
          .insert(
            v14.SettingsCompanion.insert(
              environment: 'mainnet',
              bitcoinUnit: 'sats',
              language: 'en',
              currency: 'CRC',
              hideAmounts: 1,
              isSuperuser: 0,
              payjoinEnabled: const Value(1),
              payjoinMinAmountSat: const Value(25000),
              payjoinExpireAfterSec: const Value(1800),
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
              originalTxId: '11' * 32,
              amountSat: 42000,
              createdAt: 1700000000,
              expireAfterSec: 1800,
              isExpired: 0,
              isCompleted: 0,
            ),
          );
      await oldDb
          .into(oldDb.dismissedAnnouncements)
          .insert(
            v14.DismissedAnnouncementsCompanion.insert(
              announcementId: 'release-notice',
              dismissedAt: '2026-07-30T12:00:00Z',
            ),
          );
      await oldDb.close();

      final db = SqliteDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 15);
      await db.close();

      final migratedDb = v15.DatabaseAtV15(schema.newConnection());
      final wallet = await migratedDb
          .select(migratedDb.walletMetadatas)
          .getSingle();
      expect(wallet.id, 'wallet-1');
      expect(wallet.label, 'Primary wallet');
      expect(wallet.hideOnHome, isNull);
      expect(wallet.autoSweepEnabled, isNull);
      final settings = await migratedDb.select(migratedDb.settings).getSingle();
      expect(settings.currency, 'CRC');
      expect(settings.hideAmounts, 1);
      expect(settings.payjoinEnabled, 1);
      expect(settings.payjoinMinAmountSat, 25000);
      final payjoin = await migratedDb
          .select(migratedDb.payjoinSenders)
          .getSingle();
      expect(payjoin.walletId, 'wallet-1');
      expect(payjoin.amountSat, 42000);
      expect(payjoin.originalTxId, '11' * 32);
      final announcement = await migratedDb
          .select(migratedDb.dismissedAnnouncements)
          .getSingle();
      expect(announcement.announcementId, 'release-notice');
      expect(announcement.dismissedAt, '2026-07-30T12:00:00Z');

      const entryId = "f00dbabe:39'/0'/12'/100'";
      await migratedDb
          .into(migratedDb.keychainManifestEntries)
          .insert(
            v15.KeychainManifestEntriesCompanion.insert(
              entryId: entryId,
              parentFingerprint: 'f00dbabe',
              bip85DerivationPath: "39'/0'/12'/100'",
              reservationId: 'btcpay_wallet_seed',
              entryType: 'walletSeed',
              ownerFeature: 'btcpay',
              bip85Application: 39,
              bip85Index: 100,
              createdAt: 1,
              updatedAt: 1,
            ),
          );
      await migratedDb
          .into(migratedDb.keychainManifestWalletBindings)
          .insert(
            v15.KeychainManifestWalletBindingsCompanion.insert(
              walletId: 'wallet-1',
              entryId: entryId,
              childSeedFingerprint: '0123abcd',
              network: 'bitcoinMainnet',
              scriptType: 'bip84',
              createdAt: 1,
              updatedAt: 1,
            ),
          );
      await migratedDb
          .into(migratedDb.walletBackupStates)
          .insert(v15.WalletBackupStatesCompanion.insert());

      expect(
        await migratedDb.select(migratedDb.keychainManifestEntries).get(),
        hasLength(1),
      );
      expect(
        await migratedDb
            .select(migratedDb.keychainManifestWalletBindings)
            .get(),
        hasLength(1),
      );
      expect(
        await migratedDb.select(migratedDb.walletBackupStates).get(),
        hasLength(1),
      );
      await migratedDb.close();
    },
  );
}
