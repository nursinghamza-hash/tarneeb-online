'use strict';

const SUITS = Object.freeze(['SPADES', 'HEARTS', 'DIAMONDS', 'CLUBS']);
const SUIT_SYMBOLS = Object.freeze({
  SPADES: '♠',
  HEARTS: '♥',
  DIAMONDS: '♦',
  CLUBS: '♣',
});

function minimumBid(currentBid) {
  return currentBid ? currentBid.amount + 1 : 7;
}

function isValidBidAmount(amount, currentBid) {
  return Number.isInteger(amount) && amount >= minimumBid(currentBid) && amount <= 13;
}

function createBidRecord({ seat, amount, isBot = false, suggestedSuit = null }) {
  if (!Number.isInteger(seat) || seat < 0 || seat > 3) throw new RangeError('invalid bidder seat');
  if (!Number.isInteger(amount) || amount < 7 || amount > 13) throw new RangeError('invalid bid amount');
  return {
    bid: { seat, amount, suit: null, symbol: null },
    pendingBotTrumpSuit: isBot && SUITS.includes(suggestedSuit) ? suggestedSuit : null,
  };
}

function prepareTrumpSelection({ bid, bidderIsBot = false, pendingBotTrumpSuit = null }) {
  if (!bid || !Number.isInteger(bid.seat) || bid.seat < 0 || bid.seat > 3) {
    throw new TypeError('a valid winning bid is required');
  }

  if (bidderIsBot) {
    const suit = SUITS.includes(pendingBotTrumpSuit) ? pendingBotTrumpSuit : SUITS[0];
    return {
      phase: 'playing',
      turnSeat: bid.seat,
      bid: { ...bid, suit, symbol: SUIT_SYMBOLS[suit] },
      pendingBotTrumpSuit: null,
    };
  }

  return {
    phase: 'trump_selection',
    turnSeat: bid.seat,
    bid: { ...bid, suit: null, symbol: null },
    pendingBotTrumpSuit,
  };
}

function chooseTrump({ phase, bid, seat, suit }) {
  if (phase !== 'trump_selection' || !bid || seat !== bid.seat || !SUITS.includes(suit)) {
    return null;
  }
  return {
    phase: 'playing',
    turnSeat: seat,
    bid: { ...bid, suit, symbol: SUIT_SYMBOLS[suit] },
    pendingBotTrumpSuit: null,
  };
}

module.exports = {
  SUITS,
  SUIT_SYMBOLS,
  minimumBid,
  isValidBidAmount,
  createBidRecord,
  prepareTrumpSelection,
  chooseTrump,
};
