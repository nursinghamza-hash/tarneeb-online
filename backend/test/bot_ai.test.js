'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  evaluateHandForBid,
  chooseBid,
  getLegalCards,
  chooseCard,
} = require('../bot_ai');

function card(rank, suit) {
  return { rank, suit, code: rank + '-' + suit };
}

test('AI bidding recognises a long, strong trump suit', () => {
  const hand = [
    card(14, 'HEARTS'), card(13, 'HEARTS'), card(12, 'HEARTS'),
    card(11, 'HEARTS'), card(10, 'HEARTS'), card(9, 'HEARTS'),
    card(14, 'SPADES'), card(13, 'SPADES'),
    card(2, 'DIAMONDS'), card(3, 'DIAMONDS'), card(4, 'DIAMONDS'),
    card(2, 'CLUBS'), card(3, 'CLUBS'),
  ];
  const evaluation = evaluateHandForBid(hand);
  assert.equal(evaluation.bestSuit, 'HEARTS');
  assert.ok(evaluation.maxBid >= 7);

  const decision = chooseBid({
    hand, seat: 0, dealerSeat: 2, currentBid: null, passedSeats: [],
  });
  assert.equal(decision.pass, false);
  assert.equal(decision.amount, 7);
});

test('AI passes with a very weak hand', () => {
  const hand = [
    card(2, 'SPADES'), card(4, 'SPADES'), card(6, 'SPADES'),
    card(3, 'HEARTS'), card(5, 'HEARTS'), card(7, 'HEARTS'),
    card(2, 'DIAMONDS'), card(4, 'DIAMONDS'), card(6, 'DIAMONDS'),
    card(3, 'CLUBS'), card(5, 'CLUBS'), card(7, 'CLUBS'), card(9, 'CLUBS'),
  ];
  const decision = chooseBid({
    hand, seat: 0, dealerSeat: 2, currentBid: null, passedSeats: [],
  });
  assert.equal(decision.pass, true);
});

test('dealer makes the forced opening bid after all other seats pass', () => {
  const hand = [
    card(2, 'SPADES'), card(4, 'SPADES'), card(6, 'SPADES'),
    card(3, 'HEARTS'), card(5, 'HEARTS'), card(7, 'HEARTS'),
    card(2, 'DIAMONDS'), card(4, 'DIAMONDS'), card(6, 'DIAMONDS'),
    card(3, 'CLUBS'), card(5, 'CLUBS'), card(7, 'CLUBS'), card(9, 'CLUBS'),
  ];
  const decision = chooseBid({
    hand, seat: 3, dealerSeat: 3, currentBid: null, passedSeats: [0, 1, 2],
  });
  assert.equal(decision.pass, false);
  assert.equal(decision.amount, 7);
  assert.equal(decision.forced, true);
});

test('AI follows the led suit whenever it has a card in that suit', () => {
  const hand = [
    card(4, 'HEARTS'),
    card(14, 'SPADES'),
    card(3, 'DIAMONDS'),
  ];
  const trick = [{ seat: 1, card: card(13, 'HEARTS') }];
  const legal = getLegalCards(hand, trick);
  assert.deepEqual(legal.map(item => item.code), ['4-HEARTS']);

  const selected = chooseCard({
    hand, trick, trumpSuit: 'CLUBS', seat: 0, partnerSeat: 2, bidderSeat: 1,
  });
  assert.equal(selected.code, '4-HEARTS');
});

test('AI does not overtake a winning partner when a cheap legal card is available', () => {
  const hand = [
    card(2, 'HEARTS'),
    card(14, 'SPADES'),
    card(3, 'DIAMONDS'),
  ];
  const trick = [
    { seat: 1, card: card(13, 'HEARTS') },
    { seat: 2, card: card(14, 'HEARTS') },
  ];
  const selected = chooseCard({
    hand, trick, trumpSuit: 'CLUBS', seat: 0, partnerSeat: 2, bidderSeat: 1,
  });
  assert.equal(selected.code, '2-HEARTS');
});

test('AI selected cards remain legal', () => {
  const hand = [
    card(2, 'HEARTS'),
    card(14, 'SPADES'),
    card(3, 'DIAMONDS'),
  ];
  const trick = [{ seat: 1, card: card(13, 'HEARTS') }];
  const legal = getLegalCards(hand, trick);
  const selected = chooseCard({
    hand, trick, trumpSuit: 'CLUBS', seat: 0, partnerSeat: 2, bidderSeat: 1,
  });
  assert.ok(legal.some(item => item.code === selected.code));
});
