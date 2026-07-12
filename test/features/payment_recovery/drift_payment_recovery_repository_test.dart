import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/features/payment_recovery/data/drift_payment_recovery_repository.dart';
import 'package:bb_mobile/features/payment_recovery/domain/entities/stuck_payment.dart';
import 'package:bb_mobile/features/payment_recovery/domain/primitives/recovery_state.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SqliteDatabase database;
  late DriftPaymentRecoveryRepository repo;

  setUp(() {
    database = SqliteDatabase(NativeDatabase.memory());
    repo = DriftPaymentRecoveryRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  StuckPayment payment({
    String invoiceId = 'inv-1',
    RecoveryState state = RecoveryState.detected,
    String? refundAddress,
    String? refundTxid,
    int detectedAtUnix = 1000,
  }) {
    return StuckPayment(
      invoiceId: invoiceId,
      nym: 'alice',
      state: state,
      refundAddress: refundAddress,
      refundTxid: refundTxid,
      lockupAddress: 'bc1qlock',
      amountSat: 105000,
      fiatCurrency: 'CAD',
      fiatAmountMinor: 5000,
      detectedAtUnix: detectedAtUnix,
      attemptCount: 0,
    );
  }

  test('upsert then fetch round-trips all fields', () async {
    await repo.upsert(
      payment(
        state: RecoveryState.addressCommitted,
        refundAddress: 'bc1qdest',
      ),
    );
    final row = await repo.fetch('inv-1');
    expect(row, isNotNull);
    expect(row!.state, RecoveryState.addressCommitted);
    expect(row.refundAddress, 'bc1qdest');
    expect(row.nym, 'alice');
    expect(row.amountSat, 105000);
    expect(row.fiatCurrency, 'CAD');
  });

  test('upsert overwrites the same invoice row (read-modify-write)', () async {
    await repo.upsert(payment());
    await repo.upsert(
      payment(state: RecoveryState.recovered, refundTxid: 'txid-1'),
    );
    final all = await repo.fetchAll();
    expect(all, hasLength(1));
    expect(all.single.state, RecoveryState.recovered);
    expect(all.single.refundTxid, 'txid-1');
  });

  test('fetchAll orders by detectedAt descending', () async {
    await repo.upsert(payment(invoiceId: 'old', detectedAtUnix: 100));
    await repo.upsert(payment(invoiceId: 'new', detectedAtUnix: 200));
    final all = await repo.fetchAll();
    expect(all.map((p) => p.invoiceId), ['new', 'old']);
  });

  test('delete removes the row', () async {
    await repo.upsert(payment());
    await repo.delete('inv-1');
    expect(await repo.fetch('inv-1'), isNull);
  });

  test('watch emits the current rows', () async {
    await repo.upsert(payment());
    final rows = await repo.watch().first;
    expect(rows.single.invoiceId, 'inv-1');
  });

  test('unknown persisted state round-trips as inFlightUnknown', () async {
    // Defensive: a row written by a newer app version with an unknown state
    // string must degrade to inFlightUnknown, not crash.
    await repo.upsert(payment(state: RecoveryState.inFlightUnknown));
    expect((await repo.fetch('inv-1'))!.state, RecoveryState.inFlightUnknown);
  });
}
