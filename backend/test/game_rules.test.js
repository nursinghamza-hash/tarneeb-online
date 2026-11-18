'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { dealHands } = require('../game_rules');

const SUITS = ['SPADES', 'HEARTS', 'DIAMONDS', 'CLUBS'];

function makeTestDeck() {
  const deck = [];
  for (const suit of SUITS) {
    for (let rank = 2; rank <= 14; rank += 1) {
      deck.push({ suit, rank, code: rank + '-' + suit });
    }
  }
  return deck;
}

for (const pattern of ['one', '4333']) {
  test('fair deal: ' + pattern + ' gives 13 unique cards to each seat for every dealer', () => {
    for (let dealerSeat = 0; dealerSeat < 4; dealerSeat += 1) {
      const deck = makeTestDeck();
      const hands = dealHands(deck, dealerSeat, pattern);
      const dealt = hands.flat();

      assert.equal(hands.length, 4);
      assert.deepEqual(hands.map(hand => hand.length), [13, 13, 13, 13]);
      assert.equal(dealt.length, 52);
      assert.equal(new Set(dealt.map(card => card.code)).size, 52);
      assert.equal(dealt.map(card => card.code).sort().join('|'),
        deck.map(card => card.code).sort().join('|'));
      assert.equal(hands[(dealerSeat + 1) % 4][0].code, deck[0].code);
    }
  });
}

test('fair deal rejects a deck containing duplicate cards', () => {
  const deck = makeTestDeck();
  deck[51] = { ...deck[0] };
  assert.throws(() => dealHands(deck, 0, 'one'), /52 unique cards/);
});
