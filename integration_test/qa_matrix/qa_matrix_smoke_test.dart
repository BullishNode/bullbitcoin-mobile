import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qa_matrix_engine/qa_matrix_engine.dart';

import 'support/matrix_runner.dart';

// Phase-0 smoke floor (GETPAID-APP-E2E-FAILURE-MATRIX §5.2 CG-1): the whole
// engine pipeline exercised on one recovery permutation — generate a tuple,
// compile it into a fake configuration, drive the app's REAL recovery cubit,
// map the terminal status onto the analytic oracle, score the applicable
// P1-P14 invariants, and fold it into a certified run report. If this is green,
// generate→compile→run→evaluate→report all work on live app code.
//
// Fork-only overlay lane. Lives under integration_test/qa_matrix/ so the
// (non-recursive) tool/gen_all_test.dart aggregator never picks it up; run it
// directly: `fvm flutter test integration_test/qa_matrix/qa_matrix_smoke_test.dart`.
Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  test('CG-1 smoke: generate→compile→run→evaluate→report certifies', () async {
    final generator = MatrixGenerator();
    final smoke = generator.smokeFloor();

    final record = await runCase(locator, smoke);
    final report = MatrixReport([record]);

    // The full diagnosis-by-cause-class report, for the run log.
    // ignore: avoid_print
    print(report.render());

    expect(
      record.outcome,
      CaseOutcome.passed,
      reason: 'smoke floor must certify; message=${record.message}',
    );
    expect(record.observedClass, ExpectedRecoveryClass.restored);
    expect(
      record.invariantResults.any((r) => r.id == 'P2' && r.satisfied),
      isTrue,
      reason: 'P2 (no false no-backup) must hold on the happy path',
    );
    expect(report.certified, isTrue);
  });
}
