import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_nym_claim_step.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _helper = 'Use 1–32 lowercase letters, numbers, or internal hyphens.';

Future<void> _pump(WidgetTester tester, {double width = 360}) async {
  await tester.binding.setSurfaceSize(Size(width, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = TextEditingController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.themeData(AppThemeType.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: GetPaidNymClaimStep(
            formKey: GlobalKey<FormState>(),
            controller: controller,
            submitting: false,
            errorText: null,
            onChanged: (_) {},
            onSubmit: () {},
            validator: (_) => null,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('the syntax rule is readable in full on a phone-width screen', (
    tester,
  ) async {
    await _pump(tester);

    // The character counter used to share the line and ellipsize the rule.
    expect(find.text('0/32'), findsNothing);
    final helper = tester.widget<Text>(find.text(_helper));
    expect(helper.maxLines, greaterThan(1));
    expect(tester.takeException(), isNull);
  });
}
