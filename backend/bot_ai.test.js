'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { evaluateHandForBid, chooseBid, getLegalCards, chooseCard } = require('./bot_ai');

function makeHand(suit, ranks) {
  return ranks.map(rank => ({ code: rank + '-' + suit, suit, rank }));
}

test('AI bidding evaluates a valid 13-card hand and chooses a strongest suit', () => {
  const hand = [
    ...makeHand('SPADES', [14, 13, 12, 11, 10, 9]),
    ...makeHand('HEARTS', [14, 8, 4]),
    ...makeHand('DIAMONDS', [13, 7]),
    ...makeHand('CLUBS', [2, 3]),
  ];
  const result = evaluateHandForBid(hand);
  assert.equal(result.bestSuit, 'SPADES');
  assert.ok(result.maxBid >= 7 && result.maxBid <= 13);
});

test('AI partner does not overbid the current contract without extra strength', () => {
  const hand = [
    ...makeHand('SPADES', [14, 13, 12, 11, 10, 9]),
    ...makeHand('HEARTS', [14, 8, 4]),
    ...makeHand('DIAMONDS', [13, 7]),
    ...makeHand('CLUBS', [2, 3]),
  ];
  const decision = chooseBid({
    hand, seat: 2, dealerSeat: 0, currentBid: { amount: 9, seat: 0 },
    currentBidderSeat: 0, passedSeats: [],
  });
  assert.equal(decision.pass, true);
});

test('dealer AI is forced to open at seven after the other three players pass', () => {
  const hand = [
    ...makeHand('SPADES', [14, 13, 12, 11, 10, 9]),
    ...makeHand('HEARTS', [14, 8, 4]),
    ...makeHand('DIAMONDS', [13, 7]),
    ...makeHand('CLUBS', [2, 3]),
  ];
  const decision = chooseBid({
    hand, seat: 0, dealerSeat: 0, currentBid: null,
    currentBidderSeat: null, passedSeats: [1, 2, 3],
  });
  assert.deepEqual(decision, { pass: false, amount: 7, suit: 'SPADES', forced: true });
});

test('AI always follows suit when it has a card in that suit', () => {
  const hand = [
    { code: '2-HEARTS', suit: 'HEARTS', rank: 2 },
    { code: 'A-SPADES', suit: 'SPADES', rank: 14 },
  ];
  const trick = [{ seat: 1, card: { code: 'K-HEARTS', suit: 'HEARTS', rank: 13 } }];
  assert.deepEqual(getLegalCards(hand, trick).map(card => card.code), ['2-HEARTS']);
});

test('AI uses the lowest card when its partner is already winning', () => {
  const hand = [
    { code: 'A-HEARTS', suit: 'HEARTS', rank: 14 },
    { code: '3-HEARTS', suit: 'HEARTS', rank: 3 },
    { code: '2-CLUBS', suit: 'CLUBS', rank: 2 },
  ];
  const trick = [
    { seat: 1, card: { code: 'K-HEARTS', suit: 'HEARTS', rank: 13 } },
    { seat: 2, card: { code: 'A-HEARTS', suit: 'HEARTS', rank: 14 } },
  ];
  const card = chooseCard({ hand, trick, trumpSuit: 'SPADES', seat: 0, partnerSeat: 2, bidderSeat: 0 });
  assert.equal(card.code, '3-HEARTS');
});

test('AI can choose a winning trump when unable to follow suit', () => {
  const hand = [
    { code: '2-SPADES', suit: 'SPADES', rank: 2 },
    { code: '3-CLUBS', suit: 'CLUBS', rank: 3 },
  ];
  const trick = [
    { seat: 1, card: { code: 'A-HEARTS', suit: 'HEARTS', rank: 14 } },
    { seat: 2, card: { code: '2-HEARTS', suit: 'HEARTS', rank: 2 } },
  ];
  const card = chooseCard({ hand, trick, trumpSuit: 'SPADES', seat: 3, partnerSeat: 1, bidderSeat: 0 });
  assert.equal(card.code, '2-SPADES');
});
