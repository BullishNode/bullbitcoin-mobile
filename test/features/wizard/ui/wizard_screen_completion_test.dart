import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/constants.dart';
import 'package:bb_mobile/core/widgets/snackbar_utils.dart';
import 'package:bb_mobile/features/wizard/domain/entity/wizard_choices.dart';
import 'package:bb_mobile/features/wizard/domain/repository/wizard_repository.dart';
import 'package:bb_mobile/features/wizard/domain/usecase/mark_wizard_complete_usecase.dart';
import 'package:bb_mobile/features/wizard/domain/usecase/save_metadata_backup_choice_usecase.dart';
import 'package:bb_mobile/features/wizard/domain/usecase/save_pending_wizard_choices_usecase.dart';
import 'package:bb_mobile/features/wizard/presentation/bloc/wizard_bloc.dart';
import 'package:bb_mobile/features/wizard/ui/screens/wizard_screen.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('completion failure stays on the wizard with retry available', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    Device.screen = const Size(1000, 1800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _CompletionRepository()..failCompletion = true;
    final bloc = WizardBloc(
      savePending: SavePendingWizardChoicesUsecase(repository: repository),
      saveMetadataBackupChoice: SaveMetadataBackupChoiceUsecase(
        repository: repository,
      ),
      markComplete: MarkWizardCompleteUsecase(repository: repository),
      initialChoices: const WizardChoices(
        metadataBackupEnabled: true,
        reportingConsent: true,
        touched: {
          WizardField.metadataBackupEnabled,
          WizardField.reportingConsent,
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(AppThemeType.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider<WizardBloc>.value(
          value: bloc,
          child: const WizardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable data backups'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    final failed = bloc.stream.firstWhere(
      (state) => state.completionSaveFailed,
    );
    await tester.tap(find.text('Get started'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await failed;
    await tester.pump();

    expect(bloc.state.finished, isFalse);
    expect(
      find.text('Your choices couldn’t be saved. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Get started'), findsOneWidget);
    expect(repository.markCompleteCalls, 0);

    // The app Snackbar is owned by the root overlay rather than the screen.
    // Dispose the test tree, then cancel its static auto-dismiss timer.
    await tester.pumpWidget(const SizedBox.shrink());
    SnackBarUtils.dismiss();
    await tester.pump();
  });
}

class _CompletionRepository implements WizardRepository {
  bool failCompletion = false;
  int markCompleteCalls = 0;

  @override
  Future<void> clearPending() async {}

  @override
  Future<bool> isComplete() async => false;

  @override
  Future<void> markComplete() async => markCompleteCalls++;

  @override
  Future<WizardChoices?> readPending() async => null;

  @override
  Future<void> saveMetadataBackupChoice(bool enabled) async {}

  @override
  Future<void> savePending(WizardChoices choices) async {
    if (failCompletion) throw Exception('storage unavailable');
  }
}
