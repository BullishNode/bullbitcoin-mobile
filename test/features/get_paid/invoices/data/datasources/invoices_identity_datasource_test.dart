import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/invoices_application_error.dart';
import 'package:bb_mobile/features/get_paid/invoices/data/datasources/invoices_identity_datasource.dart';
import 'package:bb_mobile/features/get_paid/shared/get_paid_identity_derivation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockGetPaidIdentityDerivation extends Mock
    implements GetPaidIdentityDerivation {}

void main() {
  late _MockGetPaidIdentityDerivation identityDerivation;
  late InvoicesIdentityDatasource datasource;

  setUp(() {
    identityDerivation = _MockGetPaidIdentityDerivation();
    datasource = InvoicesIdentityDatasource(
      identityDerivation: identityDerivation,
    );
  });

  test('returns the shared Get Paid signing handle', () async {
    final handle = NostrKeychainHandle.fromSecretKeyHex('01' * 32);
    when(
      () => identityDerivation.getSigningHandle(),
    ).thenAnswer((_) async => handle);

    await expectLater(datasource.getSigningHandle(), completion(handle));
    verify(() => identityDerivation.getSigningHandle()).called(1);
  });

  test(
    'throws typed identity error when default Bitcoin wallet is missing',
    () async {
      when(
        () => identityDerivation.getSigningHandle(),
      ).thenAnswer((_) async => null);

      await expectLater(
        datasource.getSigningHandle(),
        throwsA(isA<InvoicesIdentityUnavailableError>()),
      );
    },
  );
}
