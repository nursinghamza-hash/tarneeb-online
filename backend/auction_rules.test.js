'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  minimumBid,
  isValidBidAmount,
  createBidRecord,
  prepareTrumpSelection,
  chooseTrump,
} = require('./auction_rules');

test('auction bids begin at 7 and each new bid must be higher', () => {
  assert.equal(minimumBid(null), 7);
  assert.equal(minimumBid({ amount: 8 }), 9);
  assert.equal(isValidBidAmount(7, null), true);
  assert.equal(isValidBidAmount(13, { amount: 12 }), true);
  assert.equal(isValidBidAmount(8, { amount: 8 }), false);
  assert.equal(isValidBidAmount(7, { amount: 8 }), false);
  assert.equal(isValidBidAmount(14, { amount: 12 }), false);
  assert.equal(isValidBidAmount(7.5, null), false);
});

test('human bidder enters a separate trump-selection phase after winning the auction', () => {
  const result = prepareTrumpSelection({
    bid: { seat: 2, amount: 9, suit: null, symbol: null },
    bidderIsBot: false,
  });
  assert.equal(result.phase, 'trump_selection');
  assert.equal(result.turnSeat, 2);
  assert.equal(result.bid.suit, null);
  assert.equal(result.bid.symbol, null);
});

test('only the winning bidder can select one of the four trump suits', () => {
  const bid = { seat: 2, amount: 9, suit: null, symbol: null };
  assert.equal(chooseTrump({ phase: 'bidding', bid, seat: 2, suit: 'SPADES' }), null);
  assert.equal(chooseTrump({ phase: 'trump_selection', bid, seat: 1, suit: 'SPADES' }), null);
  assert.equal(chooseTrump({ phase: 'trump_selection', bid, seat: 2, suit: 'JOKER' }), null);
  const result = chooseTrump({ phase: 'trump_selection', bid, seat: 2, suit: 'DIAMONDS' });
  assert.equal(result.phase, 'playing');
  assert.equal(result.turnSeat, 2);
  assert.equal(result.bid.suit, 'DIAMONDS');
  assert.equal(result.bid.symbol, '♦');
});

test('bot winner automatically uses its evaluated trump suit', () => {
  const result = prepareTrumpSelection({
    bid: { seat: 3, amount: 10, suit: null, symbol: null },
    bidderIsBot: true,
    pendingBotTrumpSuit: 'HEARTS',
  });
  assert.equal(result.phase, 'playing');
  assert.equal(result.turnSeat, 3);
  assert.equal(result.bid.suit, 'HEARTS');
  assert.equal(result.bid.symbol, '♥');
  assert.equal(result.pendingBotTrumpSuit, null);
});

test('bot winner falls back to a valid suit if the preference is unavailable', () => {
  const result = prepareTrumpSelection({
    bid: { seat: 1, amount: 7 },
    bidderIsBot: true,
    pendingBotTrumpSuit: 'INVALID',
  });
  assert.equal(result.phase, 'playing');
  assert.equal(result.bid.suit, 'SPADES');
});
