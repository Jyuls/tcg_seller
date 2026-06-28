import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_seller_app/domain/bid_rules.dart';

void main() {
  group('BidRules', () {
    test('acepta únicamente números enteros y signo de pesos opcional', () {
      expect(BidRules.parseAmount('5'), 5);
      expect(BidRules.parseAmount(r' $ 15 '), 15);
      expect(BidRules.parseAmount('5 peso'), 5);
      expect(BidRules.parseAmount(r'$5 pesos'), 5);
      expect(BidRules.parseAmount('10 MXN'), 10);
      expect(BidRules.parseAmount('voy con 20'), isNull);
      expect(BidRules.parseAmount('10.50'), isNull);
    });

    test('el cierre es exclusivo', () {
      final close = DateTime.utc(2026, 6, 21, 4); // 9:00 PM Pacífico.
      expect(
        BidRules.isEligible(
          message: r'$10',
          createdAtUtc: close.subtract(const Duration(milliseconds: 1)),
          endsAtUtc: close,
          startingBid: 5,
          increment: 5,
        ),
        isTrue,
      );
      expect(
        BidRules.isEligible(
          message: r'$10',
          createdAtUtc: close,
          endsAtUtc: close,
          startingBid: 5,
          increment: 5,
        ),
        isFalse,
      );
    });

    test('valida puja inicial e incremento', () {
      final close = DateTime.utc(2026, 6, 21, 4);
      expect(
        BidRules.isEligible(
          message: '4',
          createdAtUtc: close.subtract(const Duration(minutes: 1)),
          endsAtUtc: close,
          startingBid: 5,
          increment: 5,
        ),
        isFalse,
      );
      expect(
        BidRules.isEligible(
          message: '7',
          createdAtUtc: close.subtract(const Duration(minutes: 1)),
          endsAtUtc: close,
          startingBid: 5,
          increment: 5,
        ),
        isFalse,
      );
      expect(
        BidRules.isEligible(
          message: '15',
          createdAtUtc: close.subtract(const Duration(minutes: 1)),
          endsAtUtc: close,
          startingBid: 5,
          increment: 5,
        ),
        isTrue,
      );
    });
  });
}
