class BidRules {
  const BidRules._();

  static int? parseAmount(String message) {
    final match = RegExp(
      r'^\s*\$?\s*([0-9]+)\s*(?:pesos?|mxn)?\s*$',
      caseSensitive: false,
    ).firstMatch(message);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static bool isEligible({
    required String message,
    required DateTime createdAtUtc,
    required DateTime endsAtUtc,
    required int startingBid,
    required int increment,
  }) {
    final amount = parseAmount(message);
    if (amount == null || increment <= 0) return false;
    return createdAtUtc.isBefore(endsAtUtc) &&
        amount >= startingBid &&
        (amount - startingBid) % increment == 0;
  }
}
