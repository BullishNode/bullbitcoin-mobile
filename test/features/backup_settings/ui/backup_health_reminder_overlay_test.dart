import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/backup_settings/domain/backup_health_reminder.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/acknowledge_backup_health_reminder_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/evaluate_backup_health_reminder_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/start_backup_health_action_usecase.dart';
import 'package:bb_mobile/features/backup_settings/presentation/cubit/backup_health_reminder_cubit.dart';
import 'package:bb_mobile/features/backup_settings/ui/widgets/backup_health_reminder_overlay.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockEvaluate extends Mock
    implements EvaluateBackupHealthReminderUsecase {}

class _MockAcknowledge extends Mock
    implements AcknowledgeBackupHealthReminderUsecase {}

class _MockStartAction extends Mock implements StartBackupHealthActionUsecase {}

void main() {
  const decision = BackupHealthDecision(
    masterFingerprint: 'f00dbabe',
    posture: BackupHealthPosture.recoverbullOnly,
    trigger: BackupHealthTrigger.scheduled,
  );

  testWidgets(
    'visible reminder hides covered controls from assistive technology',
    (tester) async {
      final evaluate = _MockEvaluate();
      final acknowledge = _MockAcknowledge();
      final startAction = _MockStartAction();
      when(
        () =>
            evaluate.execute(wallets: any(named: 'wallets'), arkBalanceSat: 0),
      ).thenAnswer((_) async => const Ok(decision));
      when(
        () => acknowledge.execute(decision),
      ).thenAnswer((_) async => const Ok(null));
      final cubit = BackupHealthReminderCubit(
        evaluate,
        acknowledge,
        startAction,
      );
      addTearDown(cubit.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.themeData(AppThemeType.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: BlocProvider.value(
            value: cubit,
            child: BackupHealthReminderOverlay(
              canShow: true,
              wallets: const [],
              arkBalanceSat: 0,
              child: Scaffold(
                body: Semantics(
                  label: 'covered-wallet-action',
                  button: true,
                  child: const ExcludeSemantics(child: Text('covered control')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('covered control'), findsOneWidget);
      expect(
        tester
            .widget<ExcludeSemantics>(
              find.byKey(const Key('backup_health_covered_content')),
            )
            .excluding,
        isTrue,
      );
      expect(
        find.byKey(const Key('backup_health_modal_blocker')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Semantics>(
              find.byKey(const Key('backup_health_modal_semantics')),
            )
            .properties
            .scopesRoute,
        isTrue,
      );

      await cubit.acknowledge();
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<ExcludeSemantics>(
              find.byKey(const Key('backup_health_covered_content')),
            )
            .excluding,
        isFalse,
      );
    },
  );
}
