import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/themes/colors.dart';
import 'package:bb_mobile/features/wizard/ui/widgets/metadata_backup_choice_actions.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:bull_ui/bull_ui.dart' show BullButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppLocalizations loc;

  setUpAll(
    () async => loc = await AppLocalizations.delegate.load(const Locale('en')),
  );

  Future<void> pumpActions(
    WidgetTester tester, {
    bool? choice,
    bool saving = false,
    VoidCallback? onEnable,
    VoidCallback? onDecline,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(AppThemeType.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: MetadataBackupChoiceActions(
                  choice: choice,
                  saving: saving,
                  onEnable: onEnable ?? () {},
                  onDecline: onDecline ?? () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders the exact weighted backup decision with no default', (
    tester,
  ) async {
    await pumpActions(tester);

    final enable = find.widgetWithText(
      BullButton,
      loc.wizardMetadataBackupEnable,
    );
    final decline = find.widgetWithText(
      BullButton,
      loc.wizardMetadataBackupDecline,
    );
    expect(enable, findsOneWidget);
    expect(decline, findsOneWidget);
    expect(find.text('Not now'), findsNothing);
    expect(
      tester.getSize(enable).width,
      greaterThan(tester.getSize(decline).width),
    );
    expect(tester.getSize(enable).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(decline).height, greaterThanOrEqualTo(48));

    final declineButton = tester.widget<BullButton>(decline);
    expect(declineButton.outlined, isTrue);
    expect(declineButton.textColor, AppColors.light.error);

    final enableSemantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == loc.wizardMetadataBackupEnable,
      ),
    );
    final declineSemantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == loc.wizardMetadataBackupDecline,
      ),
    );
    expect(enableSemantics.properties.selected, isFalse);
    expect(declineSemantics.properties.selected, isFalse);
    expect(enableSemantics.properties.onTap, isNotNull);
    expect(declineSemantics.properties.onTap, isNotNull);
  });

  test('disclosure distinguishes encrypted app data from the wallet seed', () {
    expect(
      loc.wizardMetadataBackupBody,
      contains('does not back up or replace your wallet seed'),
    );
    expect(
      loc.wizardMetadataBackupBody,
      contains('observe backup timing and size but cannot read'),
    );
  });

  testWidgets('both choices remain explicit and operable', (tester) async {
    var enabled = 0;
    var declined = 0;
    await pumpActions(
      tester,
      onEnable: () => enabled++,
      onDecline: () => declined++,
    );

    await tester.tap(find.text(loc.wizardMetadataBackupEnable));
    await tester.tap(find.text(loc.wizardMetadataBackupDecline));

    expect(enabled, 1);
    expect(declined, 1);
  });

  testWidgets('announces persistence and blocks duplicate choices', (
    tester,
  ) async {
    await pumpActions(tester, saving: true);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(loc.wizardMetadataBackupEnable), findsNothing);
    expect(find.text(loc.wizardMetadataBackupDecline), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.liveRegion == true &&
            widget.properties.label == loc.wizardMetadataBackupSaving,
      ),
      findsOneWidget,
    );
  });

  testWidgets('remains usable at 200 percent text scaling', (tester) async {
    await pumpActions(tester, textScale: 2);

    expect(find.text(loc.wizardMetadataBackupEnable), findsOneWidget);
    expect(find.text(loc.wizardMetadataBackupDecline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
