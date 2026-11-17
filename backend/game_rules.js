'use strict';

const SUITS = Object.freeze(['SPADES', 'HEARTS', 'DIAMONDS', 'CLUBS']);
const RANKS_DESC = Object.freeze([14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2]);

function assertSeat(seat) {
  if (!Number.isInteger(seat) || seat < 0 || seat > 3) {
    throw new RangeError('seat must be an integer from 0 to 3');
  }
}

function seatToRight(seat) {
  assertSeat(seat);
  // Seats: 0 south, 1 east/right, 2 north, 3 west/left.
  return (seat + 1) % 4;
}

function seatToLeft(seat) {
  assertSeat(seat);
  return (seat + 3) % 4;
}

function dealSeatForCard(dealerSeat, cardIndex) {
  assertSeat(dealerSeat);
  if (!Number.isInteger(cardIndex) || cardIndex < 0 || cardIndex >= 52) {
    throw new RangeError('cardIndex must be an integer from 0 to 51');
  }
  // First card goes to the dealer's right; direction is counterclockwise.
  return (dealerSeat + 1 + cardIndex) % 4;
}

function bidderSeatAfter(fromSeat, step) {
  assertSeat(fromSeat);
  if (!Number.isInteger(step) || step < 1 || step > 4) {
    throw new RangeError('step must be an integer from 1 to 4');
  }
  return (fromSeat + step) % 4;
}

function teamForSeat(partnerSeat, seat) {
  assertSeat(seat);
  if (![1, 2, 3].includes(partnerSeat)) {
    throw new RangeError('partnerSeat must be one of the other three seats');
  }
  return seat === 0 || seat === partnerSeat ? 0 : 1;
}

function dealHands(deck, dealerSeat, pattern = 'one') {
  assertSeat(dealerSeat);
  if (!Array.isArray(deck) || deck.length !== 52 || new Set(deck.map(card => card && card.code)).size !== 52 ||
      deck.some(card => !card || typeof card.code !== 'string')) {
    throw new TypeError('deck must contain 52 unique cards with string codes');
  }

  const batches = pattern === '4333'
    ? [4, 3, 3, 3]
    : pattern === 'one'
      ? Array(13).fill(1)
      : Array.isArray(pattern) ? pattern : null;

  if (!batches || batches.length === 0 || batches.some(n => !Number.isInteger(n) || n < 1) ||
      batches.reduce((sum, n) => sum + n, 0) !== 13) {
    throw new RangeError('deal pattern must be "one", "4333", or positive batches totaling 13');
  }

  const hands = [[], [], [], []];
  let cursor = 0;
  for (const batchSize of batches) {
    for (let offset = 1; offset <= 4; offset += 1) {
      const seat = (dealerSeat + offset) % 4;
      hands[seat].push(...deck.slice(cursor, cursor + batchSize));
      cursor += batchSize;
    }
  }
  if (cursor !== 52 || hands.some(hand => hand.length !== 13)) {
    throw new Error('dealing invariant failed: every seat must receive 13 cards');
  }
  return hands;
}

function getLegalCards(hand, currentTrick) {
  if (!Array.isArray(hand) || !Array.isArray(currentTrick)) {
    throw new TypeError('hand and currentTrick must be arrays');
  }
  if (currentTrick.length === 0) return [...hand];
  const ledSuit = currentTrick[0].card.suit;
  const follows = hand.filter(card => card.suit === ledSuit);
  return follows.length ? follows : [...hand];
}

function cardBeats(candidate, current, ledSuit, trumpSuit) {
  if (!candidate || !current) throw new TypeError('candidate and current cards are required');
  if (candidate.suit === trumpSuit && current.suit !== trumpSuit) return true;
  if (candidate.suit !== trumpSuit && current.suit === trumpSuit) return false;
  if (candidate.suit === current.suit) return candidate.rank > current.rank;
  if (candidate.suit === ledSuit && current.suit !== ledSuit) return true;
  return false;
}

function trickWinner(trickCards, trumpSuit) {
  if (!Array.isArray(trickCards) || trickCards.length !== 4) {
    throw new RangeError('a completed trick must contain exactly four cards');
  }
  const ledSuit = trickCards[0].card.suit;
  let winner = trickCards[0];
  for (const item of trickCards.slice(1)) {
    if (cardBeats(item.card, winner.card, ledSuit, trumpSuit)) winner = item;
  }
  return winner;
}

function mustDealerOpenBid(dealerSeat, actingSeat, passedSeats, currentBid) {
  assertSeat(dealerSeat);
  assertSeat(actingSeat);
  if (currentBid) return false;
  if (!Array.isArray(passedSeats)) throw new TypeError('passedSeats must be an array');
  const uniquePassed = new Set(passedSeats);
  return actingSeat === dealerSeat &&
    [0, 1, 2, 3].filter(seat => seat !== dealerSeat).every(seat => uniquePassed.has(seat));
}

function scoreRound(scores, tricks, bidTeam, bidAmount, options = {}) {
  if (!Array.isArray(scores) || scores.length !== 2 || !scores.every(Number.isFinite)) {
    throw new TypeError('scores must contain two finite numbers');
  }
  if (!Array.isArray(tricks) || tricks.length !== 2 ||
      !tricks.every(Number.isInteger) || tricks.some(value => value < 0 || value > 13) ||
      tricks[0] + tricks[1] !== 13) {
    throw new RangeError('tricks must be two non-negative integers totaling 13');
  }
  if (bidTeam !== 0 && bidTeam !== 1) throw new RangeError('bidTeam must be 0 or 1');
  if (!Number.isInteger(bidAmount) || bidAmount < 7 || bidAmount > 13) {
    throw new RangeError('bidAmount must be an integer from 7 to 13');
  }

  // Jawaker standard Tarneeb: declared 13-and-made = 26; an unannounced sweep = 16.
  // The alternative value can be supplied for a custom house-rule room.
  const declaredKabootPoints = options.declaredKabootPoints ?? 26;
  const failedKabootPenalty = options.failedKabootPenalty ?? 16;
  const sweepPoints = options.sweepPoints ?? 16;
  for (const [name, value] of Object.entries({ declaredKabootPoints, failedKabootPenalty, sweepPoints })) {
    if (!Number.isFinite(value) || value < 0) throw new RangeError(name + ' must be a non-negative finite number');
  }

  const result = [...scores];
  const otherTeam = 1 - bidTeam;
  const bidMet = tricks[bidTeam] >= bidAmount;
  const allTricksTeam = tricks[0] === 13 ? 0 : (tricks[1] === 13 ? 1 : null);

  if (bidAmount === 13) {
    if (bidMet) {
      result[bidTeam] += declaredKabootPoints;
    } else {
      result[bidTeam] -= failedKabootPenalty;
      result[otherTeam] += allTricksTeam === otherTeam ? sweepPoints : tricks[otherTeam];
    }
  } else if (allTricksTeam !== null) {
    result[allTricksTeam] += sweepPoints;
    if (allTricksTeam === otherTeam) result[bidTeam] -= bidAmount;
  } else if (bidMet) {
    result[bidTeam] += tricks[bidTeam];
  } else {
    result[bidTeam] -= bidAmount;
    result[otherTeam] += tricks[otherTeam];
  }

  return { scores: result, bidMet };
}

module.exports = {
  SUITS,
  RANKS_DESC,
  seatToRight,
  seatToLeft,
  dealSeatForCard,
  bidderSeatAfter,
  teamForSeat,
  dealHands,
  getLegalCards,
  cardBeats,
  trickWinner,
  mustDealerOpenBid,
  scoreRound,
};
