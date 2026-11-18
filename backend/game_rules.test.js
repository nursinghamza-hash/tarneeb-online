'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
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
  canBid,
  scoreRound,
} = require('./game_rules');

function deck() {
  const suits = ['SPADES', 'HEARTS', 'DIAMONDS', 'CLUBS'];
  const cards = [];
  for (const suit of suits) for (let rank = 2; rank <= 14; rank += 1) {
    cards.push({ code: rank + '-' + suit, suit, rank });
  }
  return cards;
}

test('seat geometry matches south/east/north/west positions', () => {
  assert.equal(seatToRight(0), 1);
  assert.equal(seatToLeft(0), 3);
  assert.equal(seatToRight(3), 0);
  assert.equal(seatToLeft(3), 2);
});

test('deal starts to dealer right and proceeds counterclockwise', () => {
  for (let dealer = 0; dealer < 4; dealer += 1) {
    assert.deepEqual(
      [0, 1, 2, 3].map(index => dealSeatForCard(dealer, index)),
      [(dealer + 1) % 4, (dealer + 2) % 4, (dealer + 3) % 4, dealer],
    );
    const hands = dealHands(deck(), dealer, 'one');
    assert.deepEqual(hands.map(hand => hand.length), [13, 13, 13, 13]);
  }
});

test('batch dealing 4-3-3-3 gives every player 13 cards and conserves the deck', () => {
  const source = deck();
  const hands = dealHands(source, 0, '4333');
  assert.deepEqual(hands.map(hand => hand.length), [13, 13, 13, 13]);
  const allCodes = hands.flat().map(card => card.code);
  assert.equal(new Set(allCodes).size, 52);
  assert.deepEqual(allCodes.sort(), source.map(card => card.code).sort());
  assert.deepEqual(hands[1].slice(0, 4).map(card => card.code), source.slice(0, 4).map(card => card.code));
});

test('bidding order starts at dealer right and advances counterclockwise', () => {
  assert.deepEqual([1, 2, 3, 4].map(step => bidderSeatAfter(0, step)), [1, 2, 3, 0]);
});

test('selected partner determines opposing teams', () => {
  assert.deepEqual([0, 1, 2, 3].map(seat => teamForSeat(2, seat)), [0, 1, 0, 1]);
  assert.deepEqual([0, 1, 2, 3].map(seat => teamForSeat(3, seat)), [0, 1, 1, 0]);
});

test('each partnership always receives one shared team score index', () => {
  for (const partnerSeat of [1, 2, 3]) {
    const teams = [0, 1, 2, 3].map(seat => teamForSeat(partnerSeat, seat));
    assert.equal(teams[0], teams[partnerSeat]);
    const opponents = [0, 1, 2, 3].filter(seat => seat !== 0 && seat !== partnerSeat);
    assert.equal(teams[opponents[0]], teams[opponents[1]]);
    assert.notEqual(teams[0], teams[opponents[0]]);
  }
});

test('dealer is forced to open at seven only after all other three seats passed', () => {
  assert.equal(mustDealerOpenBid(0, 0, [1, 2, 3], null), true);
  assert.equal(mustDealerOpenBid(0, 0, [1, 2], null), false);
  assert.equal(mustDealerOpenBid(0, 0, [1, 2, 3], { amount: 8 }), false);
  assert.equal(mustDealerOpenBid(0, 1, [0, 2, 3], null), false);
});

test('passing permanently removes a player from bidding for the round', () => {
  assert.equal(canBid(0, [1, 2]), true);
  assert.equal(canBid(1, [1, 2]), false);
  assert.throws(() => canBid(4, []), RangeError);
});

test('follow-suit rule disallows off-suit while led suit is available', () => {
  const hand = [
    { code: 'A-SPADES', suit: 'SPADES', rank: 14 },
    { code: '2-HEARTS', suit: 'HEARTS', rank: 2 },
  ];
  const trick = [{ seat: 1, card: { code: 'K-SPADES', suit: 'SPADES', rank: 13 } }];
  assert.deepEqual(getLegalCards(hand, trick).map(card => card.code), ['A-SPADES']);
  assert.deepEqual(getLegalCards([{ code: '2-HEARTS', suit: 'HEARTS', rank: 2 }], trick).map(card => card.code), ['2-HEARTS']);
});

test('a player with no card in the led suit may legally play any card', () => {
  const hand = [
    { code: '2-HEARTS', suit: 'HEARTS', rank: 2 },
    { code: 'A-DIAMONDS', suit: 'DIAMONDS', rank: 14 },
    { code: '7-CLUBS', suit: 'CLUBS', rank: 7 },
  ];
  const trick = [{ seat: 1, card: { code: 'K-SPADES', suit: 'SPADES', rank: 13 } }];
  assert.deepEqual(getLegalCards(hand, trick).map(card => card.code), [
    '2-HEARTS', 'A-DIAMONDS', '7-CLUBS',
  ]);
});

test('trick winner respects led suit, trump and card rank', () => {
  const trick = [
    { seat: 0, card: { suit: 'HEARTS', rank: 14 } },
    { seat: 1, card: { suit: 'HEARTS', rank: 12 } },
    { seat: 2, card: { suit: 'SPADES', rank: 2 } },
    { seat: 3, card: { suit: 'SPADES', rank: 14 } },
  ];
  assert.equal(trickWinner(trick, 'SPADES').seat, 3);
  assert.equal(trickWinner(trick.slice(0, 2).concat([
    { seat: 2, card: { suit: 'DIAMONDS', rank: 14 } },
    { seat: 3, card: { suit: 'HEARTS', rank: 13 } },
  ]), 'SPADES').seat, 0);
  assert.equal(cardBeats({ suit: 'HEARTS', rank: 2 }, { suit: 'HEARTS', rank: 3 }, 'HEARTS', 'SPADES'), false);
  assert.equal(cardBeats({ suit: 'HEARTS', rank: 4 }, { suit: 'HEARTS', rank: 3 }, 'HEARTS', 'SPADES'), true);
});

test('normal bid success scores the bid team actual tricks only', () => {
  assert.deepEqual(scoreRound([0, 0], [8, 5], 0, 8), { scores: [8, 0], bidMet: true });
});

test('failed normal bid deducts the bid and awards defenders their actual tricks', () => {
  assert.deepEqual(scoreRound([0, 0], [7, 6], 0, 8), { scores: [-8, 6], bidMet: false });
});

test('Jawaker declared Kaboot scores 26 and failed Kaboot loses 16', () => {
  assert.deepEqual(scoreRound([10, 0], [13, 0], 0, 13), { scores: [36, 0], bidMet: true });
  assert.deepEqual(scoreRound([0, 0], [12, 1], 0, 13), { scores: [-16, 1], bidMet: false });
  assert.deepEqual(scoreRound([0, 0], [0, 13], 0, 13), { scores: [-16, 13], bidMet: false });
});

test('custom house rule can score declared Kaboot as 16', () => {
  assert.deepEqual(scoreRound([0, 0], [13, 0], 0, 13, { declaredKabootPoints: 16 }), {
    scores: [16, 0], bidMet: true,
  });
});

test('custom house preset scores declared Kaboot 16 and unannounced sweep 14', () => {
  assert.deepEqual(scoreRound([0, 0], [13, 0], 0, 13, {
    declaredKabootPoints: 16, sweepPoints: 14,
  }), { scores: [16, 0], bidMet: true });
  assert.deepEqual(scoreRound([0, 0], [13, 0], 0, 7, {
    declaredKabootPoints: 16, sweepPoints: 14,
  }), { scores: [14, 0], bidMet: true });
  assert.deepEqual(scoreRound([0, 0], [0, 13], 0, 13, {
    declaredKabootPoints: 16, sweepPoints: 14,
  }), { scores: [-16, 13], bidMet: false });
});

test('an unannounced 13-trick sweep scores 16 points', () => {
  assert.deepEqual(scoreRound([0, 0], [13, 0], 0, 7), { scores: [16, 0], bidMet: true });
  assert.deepEqual(scoreRound([0, 0], [0, 13], 0, 7), { scores: [-7, 16], bidMet: false });
});

test('rejects invalid card patterns, trick totals, teams and seats', () => {
  assert.throws(() => dealHands(deck().slice(1), 0), TypeError);
  assert.throws(() => dealHands(deck(), 0, '433'), RangeError);
  assert.throws(() => scoreRound([0, 0], [8, 4], 0, 7), RangeError);
  assert.throws(() => teamForSeat(null, 0), RangeError);
  assert.throws(() => dealSeatForCard(0, 52), RangeError);
});
