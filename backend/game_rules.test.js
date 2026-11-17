'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  seatToRight,
  seatToLeft,
  dealSeatForCard,
  bidderSeatAfter,
  teamForSeat,
  scoreRound,
} = require('./game_rules');

test('seats to the right and left match the visual table positions', () => {
  assert.equal(seatToRight(0), 3);
  assert.equal(seatToLeft(0), 1);
  assert.equal(seatToRight(3), 2);
  assert.equal(seatToLeft(3), 0);
});

test('deal starts to the dealer right and proceeds counterclockwise', () => {
  for (let dealer = 0; dealer < 4; dealer += 1) {
    const order = Array.from({ length: 4 }, (_, index) => dealSeatForCard(dealer, index));
    assert.deepEqual(order, [
      seatToRight(dealer),
      (dealer + 2) % 4,
      seatToLeft(dealer),
      dealer,
    ]);

    const counts = [0, 0, 0, 0];
    for (let cardIndex = 0; cardIndex < 52; cardIndex += 1) {
      counts[dealSeatForCard(dealer, cardIndex)] += 1;
    }
    assert.deepEqual(counts, [13, 13, 13, 13]);
  }
});

test('bidding order moves counterclockwise from the dealer right', () => {
  assert.deepEqual(
    [1, 2, 3, 4].map(step => bidderSeatAfter(0, step)),
    [3, 2, 1, 0],
  );
});

test('selected partner determines the two teams for every seat', () => {
  assert.deepEqual(
    [0, 1, 2, 3].map(seat => teamForSeat(2, seat)),
    [0, 1, 0, 1],
  );
  assert.deepEqual(
    [0, 1, 2, 3].map(seat => teamForSeat(3, seat)),
    [0, 1, 1, 0],
  );
});

test('successful normal bid scores the bid team actual tricks only', () => {
  assert.deepEqual(scoreRound([0, 0], [8, 5], 0, 8), {
    scores: [8, 0],
    bidMet: true,
  });
});

test('failed normal bid deducts the bid and awards opponents their tricks', () => {
  assert.deepEqual(scoreRound([0, 0], [7, 6], 0, 8), {
    scores: [-8, 6],
    bidMet: false,
  });
});

test('successful 13 bid scores 26 points', () => {
  assert.deepEqual(scoreRound([10, 0], [13, 0], 0, 13), {
    scores: [36, 0],
    bidMet: true,
  });
});

test('failed 13 bid deducts 16 points', () => {
  assert.deepEqual(scoreRound([0, 0], [12, 1], 0, 13), {
    scores: [-16, 1],
    bidMet: false,
  });
});

test('a 13-trick sweep without a 13 bid scores 16 points', () => {
  assert.deepEqual(scoreRound([0, 0], [13, 0], 0, 7), {
    scores: [16, 0],
    bidMet: true,
  });
  assert.deepEqual(scoreRound([0, 0], [0, 13], 0, 7), {
    scores: [-7, 16],
    bidMet: false,
  });
});

test('rejects invalid trick totals and invalid team selections', () => {
  assert.throws(() => scoreRound([0, 0], [8, 4], 0, 7), RangeError);
  assert.throws(() => teamForSeat(null, 0), RangeError);
});
