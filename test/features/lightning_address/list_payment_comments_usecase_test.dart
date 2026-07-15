import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_default_wallet_xprv_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/list_lightning_address_payment_comments_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/list_wallet_owned_lightning_address_payment_comments_usecase.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBullnym extends Mock implements BullnymFacade {}

class _MockNostrIdentity extends Mock implements NostrIdentityFacade {}

class _FakeDefaultWalletXprv implements LightningAddressDefaultWalletXprvPort {
  int calls = 0;

  @override
  Future<String> deriveDefaultWalletXprv() async {
    calls += 1;
    return 'default-wallet-xprv';
  }
}

void main() {
  late _MockBullnym bullnym;
  late _MockNostrIdentity nostr;
  late ListLightningAddressPaymentCommentsUsecase usecase;

  setUpAll(() {
    registerFallbackValue(
      BullnymAuthSigner(npubHex: '00' * 32, signHashHex: (_) => ''),
    );
  });

  setUp(() {
    bullnym = _MockBullnym();
    nostr = _MockNostrIdentity();
    usecase = ListLightningAddressPaymentCommentsUsecase(bullnym, nostr);
    when(
      () => nostr.deriveBullnymServerAuthPublicKeyFromXprv(any()),
    ).thenReturn('11' * 32);
    when(
      () => nostr.signBullnymServerAuthHashFromXprv(
        xprvBase58: any(named: 'xprvBase58'),
        messageHashHex: any(named: 'messageHashHex'),
      ),
    ).thenReturn('aa' * 64);
  });

  test(
    'derives the merchant signer and maps exact evidenced comment text',
    () async {
      when(
        () => bullnym.listLnurlCommentHistory(
          signer: any(named: 'signer'),
          page: 1,
          pageSize: 20,
        ),
      ).thenAnswer(
        (_) async => const Ok(
          BullnymLnurlCommentHistoryResponse(
            comments: [
              BullnymLnurlCommentHistoryItem(
                intentId: '4de539d7-b0f2-4d4a-a308-d0f31dc111b5',
                nym: 'merchant',
                amountMsat: 42001,
                comment: '<b>not markup</b> ☕',
                receivedAtUnix: 1784041200,
              ),
            ],
            page: 1,
            pageSize: 20,
            hasMore: true,
          ),
        ),
      );

      final page = await usecase.execute(
        xprvBase58: 'default-wallet-xprv',
        page: 1,
        pageSize: 20,
      );

      expect(page.hasMore, isTrue);
      expect(page.comments.single.comment, '<b>not markup</b> ☕');
      expect(page.comments.single.amountMsat, 42001);
      expect(page.comments.single.receivedAt.isUtc, isTrue);
      final signer =
          verify(
                () => bullnym.listLnurlCommentHistory(
                  signer: captureAny(named: 'signer'),
                  page: 1,
                  pageSize: 20,
                ),
              ).captured.single
              as BullnymAuthSigner;
      expect(signer.npubHex, '11' * 32);
      expect(await signer.signHashHex('22' * 32), 'aa' * 64);
      verify(
        () => nostr.signBullnymServerAuthHashFromXprv(
          xprvBase58: 'default-wallet-xprv',
          messageHashHex: '22' * 32,
        ),
      ).called(1);
    },
  );

  test(
    'wallet-owned composition derives the default wallet internally',
    () async {
      when(
        () => bullnym.listLnurlCommentHistory(
          signer: any(named: 'signer'),
          page: 2,
          pageSize: 20,
        ),
      ).thenAnswer(
        (_) async => const Ok(
          BullnymLnurlCommentHistoryResponse(
            comments: [],
            page: 2,
            pageSize: 20,
            hasMore: false,
          ),
        ),
      );
      final xprv = _FakeDefaultWalletXprv();
      final walletOwned = ListWalletOwnedLightningAddressPaymentCommentsUsecase(
        xprv,
        usecase,
      );

      final page = await walletOwned.execute(page: 2, pageSize: 20);

      expect(page.page, 2);
      expect(xprv.calls, 1);
      verify(
        () => nostr.deriveBullnymServerAuthPublicKeyFromXprv(
          'default-wallet-xprv',
        ),
      ).called(1);
    },
  );

  test('domain rejects text beyond grapheme and UTF-8 limits', () {
    expect(
      () => LightningAddressPaymentComment(
        intentId: 'id',
        nym: 'merchant',
        amountMsat: 1000,
        comment: 'é' * 121,
        receivedAt: DateTime.utc(2026),
      ),
      throwsArgumentError,
    );
    expect(
      () => LightningAddressPaymentComment(
        intentId: 'id',
        nym: 'merchant',
        amountMsat: 1000,
        comment: '👨‍👩‍👧‍👦' * 120,
        receivedAt: DateTime.utc(2026),
      ),
      throwsArgumentError,
    );
  });
}
