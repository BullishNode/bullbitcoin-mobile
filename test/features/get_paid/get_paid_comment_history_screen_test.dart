import 'package:bb_mobile/features/get_paid/presentation/get_paid_comment_history_cubit.dart';
import 'package:bb_mobile/features/get_paid/ui/screens/get_paid_comment_history_screen.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

const _untrustedText = '<script>alert(1)</script> [pay](bitcoin:bc1qtest)';

LightningAddressFacade _facade(LightningAddressPaymentComment comment) {
  return LightningAddressFacade(
    prepareWallet: () => throw UnimplementedError(),
    lookupRegistration: ({required npubHex}) => throw UnimplementedError(),
    registerWalletOwned: ({required nym}) => throw UnimplementedError(),
    lookupWalletOwnedRegistration: () => throw UnimplementedError(),
    ensureRegistrationLive: () => throw UnimplementedError(),
    listPaymentComments: ({required page, required pageSize}) async =>
        LightningAddressPaymentCommentPage(
          comments: [comment],
          page: page,
          pageSize: pageSize,
          hasMore: false,
        ),
  );
}

void main() {
  testWidgets(
    'reveals exact untrusted text only after opening payment detail',
    (tester) async {
      final comment = LightningAddressPaymentComment(
        intentId: '4de539d7-b0f2-4d4a-a308-d0f31dc111b5',
        nym: 'merchant',
        amountMsat: 42001,
        comment: _untrustedText,
        receivedAt: DateTime.utc(2026, 7, 14, 12, 30),
      );
      final cubit = GetPaidCommentHistoryCubit(_facade(comment));
      addTearDown(cubit.close);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: BlocProvider<GetPaidCommentHistoryCubit>.value(
            value: cubit,
            child: const GetPaidCommentHistoryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_untrustedText), findsNothing);
      expect(find.text('42,001 msats'), findsOneWidget);
      expect(find.textContaining('merchant'), findsOneWidget);

      await tester.tap(
        find.byKey(ValueKey('lnurl-comment-${comment.intentId}')),
      );
      await tester.pumpAndSettle();

      final textFinder = find.byKey(
        const ValueKey('private-lnurl-comment-text'),
      );
      expect(textFinder, findsOneWidget);
      final text = tester.widget<Text>(textFinder);
      expect(text.data, _untrustedText);
      expect(find.text(_untrustedText), findsOneWidget);
      expect(find.text('Payer comment'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
