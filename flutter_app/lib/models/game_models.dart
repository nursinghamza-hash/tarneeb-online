enum CardSuit { spades, hearts, diamonds, clubs }

extension CardSuitExt on CardSuit {
  String get symbol {
    switch (this) {
      case CardSuit.spades: return '♠';
      case CardSuit.hearts: return '♥';
      case CardSuit.diamonds: return '♦';
      case CardSuit.clubs: return '♣';
    }
  }

  String get arabicName {
    switch (this) {
      case CardSuit.spades: return 'بستوني';
      case CardSuit.hearts: return 'كبة';
      case CardSuit.diamonds: return 'ديناري';
      case CardSuit.clubs: return 'سنك';
    }
  }

  bool get isRed => this == CardSuit.hearts || this == CardSuit.diamonds;
}

class PlayingCardModel {
  final CardSuit suit;
  final int rank;
  final String code;

  const PlayingCardModel({
    required this.suit,
    required this.rank,
    required this.code,
  });

  String get rankLabel {
    switch (rank) {
      case 14: return 'A';
      case 13: return 'K';
      case 12: return 'Q';
      case 11: return 'J';
      default: return rank.toString();
    }
  }
}

class PlayedTrickCard {
  final int seat;
  final PlayingCardModel card;
  const PlayedTrickCard({required this.seat, required this.card});
}
