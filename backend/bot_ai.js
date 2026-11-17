'use strict';

const SUITS = Object.freeze(['SPADES', 'HEARTS', 'DIAMONDS', 'CLUBS']);

function validateCard(card) {
  return !!card && SUITS.includes(card.suit) && Number.isInteger(card.rank) &&
    card.rank >= 2 && card.rank <= 14 && typeof card.code === 'string';
}

function evaluateHandForBid(hand) {
  if (!Array.isArray(hand) || hand.length !== 13 || hand.some(card => !validateCard(card))) {
    throw new TypeError('AI bidding requires a 13-card hand');
  }

  const suitCounts = Object.fromEntries(SUITS.map(suit => [suit, 0]));
  const suitPower = Object.fromEntries(SUITS.map(suit => [suit, 0]));

  for (const card of hand) {
    suitCounts[card.suit] += 1;
    if (card.rank >= 11) suitPower[card.suit] += card.rank - 10;
  }

  let bestSuit = SUITS[0];
  let bestScore = -Infinity;
  for (const suit of SUITS) {
    const score = suitCounts[suit] * 2.2 + suitPower[suit];
    if (score > bestScore) {
      bestScore = score;
      bestSuit = suit;
    }
  }

  let estimatedTricks = Math.max(0, suitCounts[bestSuit] - 2.2) +
    suitPower[bestSuit] * 0.35;

  for (const card of hand) {
    if (card.suit === bestSuit) continue;
    if (card.rank === 14) estimatedTricks += 1;
    else if (card.rank === 13 && suitCounts[card.suit] >= 2) estimatedTricks += 0.65;
  }

  // A practical partnership estimate; this is a heuristic, not a guarantee.
  estimatedTricks += 1.7;

  return {
    bestSuit,
    estimatedTricks,
    maxBid: Math.min(13, Math.floor(estimatedTricks)),
    suitCounts,
    suitPower,
  };
}

function chooseBid({ hand, seat, dealerSeat, currentBid, currentBidderSeat, passedSeats = [] }) {
  if (!Number.isInteger(seat) || seat < 0 || seat > 3) throw new RangeError('invalid seat');
  if (!Number.isInteger(dealerSeat) || dealerSeat < 0 || dealerSeat > 3) throw new RangeError('invalid dealer seat');
  if (!Array.isArray(passedSeats)) throw new TypeError('passedSeats must be an array');

  const evaluation = evaluateHandForBid(hand);
  const activeWithoutDealer = [0, 1, 2, 3]
    .filter(other => other !== dealerSeat)
    .every(other => passedSeats.includes(other));

  if (!currentBid && seat === dealerSeat && activeWithoutDealer) {
    return { pass: false, amount: 7, suit: evaluation.bestSuit, forced: true };
  }

  const nextBid = currentBid ? currentBid.amount + 1 : 7;
  const partnerSeat = (seat + 2) % 4;
  const partnerHoldsBid = !!currentBid && currentBid.seat === partnerSeat;
  const hasEnoughStrength = evaluation.maxBid >= nextBid;
  const partnershipOverbidThreshold = !partnerHoldsBid || evaluation.maxBid >= nextBid + 1;

  if (hasEnoughStrength && partnershipOverbidThreshold) {
    return { pass: false, amount: nextBid, suit: evaluation.bestSuit, forced: false };
  }
  return { pass: true };
}

function cardBeats(candidate, current, ledSuit, trumpSuit) {
  if (candidate.suit === trumpSuit && current.suit !== trumpSuit) return true;
  if (candidate.suit !== trumpSuit && current.suit === trumpSuit) return false;
  if (candidate.suit === current.suit) return candidate.rank > current.rank;
  return candidate.suit === ledSuit && current.suit !== ledSuit;
}

function getLegalCards(hand, trick) {
  if (!Array.isArray(hand) || !Array.isArray(trick)) throw new TypeError('hand and trick must be arrays');
  if (trick.length === 0) return [...hand];
  const leadSuit = trick[0].card.suit;
  const following = hand.filter(card => card.suit === leadSuit);
  return following.length ? following : [...hand];
}

function currentWinner(trick, trumpSuit) {
  const leadSuit = trick[0].card.suit;
  let best = trick[0];
  for (const play of trick.slice(1)) {
    if (cardBeats(play.card, best.card, leadSuit, trumpSuit)) best = play;
  }
  return best;
}

function chooseCard({ hand, trick = [], trumpSuit, seat, partnerSeat, bidderSeat, allHands = [] }) {
  if (!Array.isArray(hand) || hand.length === 0 || hand.some(card => !validateCard(card))) {
    throw new TypeError('AI card selection requires a non-empty valid hand');
  }
  if (!SUITS.includes(trumpSuit)) throw new TypeError('trumpSuit is required');
  if (!Number.isInteger(seat) || seat < 0 || seat > 3) throw new RangeError('invalid seat');

  const legal = getLegalCards(hand, trick);
  if (legal.length === 1) return legal[0];

  const isBidderTeam = Number.isInteger(bidderSeat) && (seat % 2) === (bidderSeat % 2);

  if (trick.length === 0) {
    if (isBidderTeam) {
      const trumps = legal.filter(card => card.suit === trumpSuit).sort((a, b) => b.rank - a.rank);
      const enemyTrumpCount = Array.isArray(allHands)
        ? allHands.reduce((sum, otherHand, otherSeat) =>
            (otherSeat % 2) !== (seat % 2)
              ? sum + (Array.isArray(otherHand) ? otherHand.filter(card => card.suit === trumpSuit).length : 0)
              : sum, 0)
        : 0;
      if (trumps.length && enemyTrumpCount > 0 && trumps[0].rank >= 12) return trumps[0];
    }

    const sideWinners = legal.filter(card =>
      card.suit !== trumpSuit &&
      (card.rank === 14 || (card.rank === 13 && hand.filter(other => other.suit === card.suit).length >= 2))
    ).sort((a, b) => b.rank - a.rank);
    if (sideWinners.length) return sideWinners[0];

    return [...legal].sort((a, b) => a.rank - b.rank)[0];
  }

  const leadSuit = trick[0].card.suit;
  const winner = currentWinner(trick, trumpSuit);
  const winningOptions = legal.filter(card => cardBeats(card, winner.card, leadSuit, trumpSuit));
  const isLastToPlay = trick.length === 3;
  const teammateIsWinning = winner.seat === partnerSeat;

  if (teammateIsWinning) {
    return [...legal].sort((a, b) => {
      const aCost = a.rank + (a.suit === trumpSuit ? 100 : 0);
      const bCost = b.rank + (b.suit === trumpSuit ? 100 : 0);
      return aCost - bCost;
    })[0];
  }

  if (winningOptions.length) {
    const cost = card => card.rank + (card.suit === trumpSuit ? 100 : 0);
    winningOptions.sort((a, b) => cost(a) - cost(b));
    return isLastToPlay ? winningOptions[0] : winningOptions[winningOptions.length - 1];
  }

  const discards = legal.filter(card => card.suit !== trumpSuit).sort((a, b) => a.rank - b.rank);
  if (discards.length) return discards[0];
  return [...legal].sort((a, b) => a.rank - b.rank)[0];
}

module.exports = { evaluateHandForBid, chooseBid, getLegalCards, cardBeats, chooseCard };
