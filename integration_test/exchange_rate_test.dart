import 'dart:async';

import 'package:bb_mobile/_core/data/datasources/bullbitcoin_api_datasource.dart';
import 'package:bb_mobile/_core/domain/usecases/convert_currency_to_sats_amount_usecase.dart';
import 'package:bb_mobile/_core/domain/usecases/convert_sats_to_currency_amount_usecase.dart';
import 'package:bb_mobile/_core/domain/usecases/get_available_currencies_usecase.dart';
import 'package:bb_mobile/_utils/constants.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:payjoin_flutter/src/generated/frb_generated.dart';
import 'package:test/test.dart';

void main() {
  late BitcoinPriceDatasource bitcoinPriceDatasource;
  late GetAvailableCurrenciesUsecase getAvailableCurrenciesUsecase;
  late ConvertCurrencyToSatsAmountUsecase convertCurrencyToSatsAmountUsecase;
  late ConvertSatsToCurrencyAmountUsecase convertSatsToCurrencyAmountUsecase;

  setUpAll(() async {
    await Future.wait([
      Hive.initFlutter(),
      core.init(),
    ]);

    await AppLocator.setup();

    bitcoinPriceDatasource = locator.get<BitcoinPriceDatasource>();
    getAvailableCurrenciesUsecase =
        locator.get<GetAvailableCurrenciesUsecase>();
    convertCurrencyToSatsAmountUsecase =
        locator.get<ConvertCurrencyToSatsAmountUsecase>();
    convertSatsToCurrencyAmountUsecase =
        locator.get<ConvertSatsToCurrencyAmountUsecase>();
  });

  setUp(() async {});

  group(
    'Exchange Rate Integration Tests',
    () {
      group(
        'have a working BullBitcoin API',
        () {
          test('with currencies we expect', () async {
            final expectedCurrencies = ['USD', 'CAD', 'INR', 'CRC', 'EUR'];
            final currencies = await getAvailableCurrenciesUsecase.execute();

            for (final currency in expectedCurrencies) {
              expect(currencies.contains(currency), true);
            }
          });
          test('with prices for available currencies', () async {
            final currencies = await getAvailableCurrenciesUsecase.execute();
            for (final currency in currencies) {
              try {
                final price = await bitcoinPriceDatasource.getPrice(currency);
                debugPrint('Price for $currency: $price');

                expect(price, isNonZero);
                expect(price, isPositive);
              } catch (e) {
                fail('Failed to get price for $currency: $e');
              }
            }
          });
        },
      );

      group(
        'have working conversion use cases',
        () {
          const currency = 'USD';
          late double bitcoinPrice;

          setUp(() async {
            bitcoinPrice = await bitcoinPriceDatasource.getPrice(currency);
          });

          test('that get the price of one bitcoin', () async {
            final amountSat = ConversionConstants.satsAmountOfOneBitcoin;

            final amount = await convertSatsToCurrencyAmountUsecase.execute(
              currencyCode: currency,
              amountSat: amountSat,
            );

            debugPrint('Converted $amountSat sats to $amount $currency');

            expect(bitcoinPrice, amount);
          });

          test('that converts currency to sats', () async {
            const amount = 123.0;

            final sats = await convertCurrencyToSatsAmountUsecase.execute(
              currencyCode: currency,
              amountFiat: amount,
            );

            debugPrint('Converted $amount $currency to $sats sats');

            final expectedSats =
                BigInt.from((amount * 100000000) ~/ bitcoinPrice);

            expect(expectedSats, sats);
          });

          test('that converts sats to currency', () async {
            final sats = BigInt.from(150000);

            final amount = await convertSatsToCurrencyAmountUsecase.execute(
              currencyCode: currency,
              amountSat: sats,
            );

            debugPrint('Converted $sats sats to $amount $currency');

            final expectedAmount = sats / BigInt.from(100000000) * bitcoinPrice;
            expect(expectedAmount, amount);
          });
        },
      );
    },
  );
}
