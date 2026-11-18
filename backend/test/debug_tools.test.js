'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  isDebugSeatEnabled,
  toggleDebugSeat,
  getDebugHandsForSeat,
} = require('../debug_tools');

function makeRoom() {
  const players = Array.from({ length: 4 }, (_, seat) => ({ name: 'Player ' + seat }));
  const hands = Array.from({ length: 4 }, (_, seat) =>
    Array.from({ length: 13 }, (_, index) => ({
      code: index + '-' + seat,
      rank: 2 + index,
      suit: 'SPADES',
    })),
  );
  return { players, hands, debugEnabledSeats: new Set() };
}

test('0099 diagnostic is hidden until explicitly toggled on for a seat', () => {
  const room = makeRoom();
  assert.equal(isDebugSeatEnabled(room, 0), false);
  assert.equal(getDebugHandsForSeat(room, 0), null);
});

test('0099 toggle on exposes all four hands, including the host hand', () => {
  const room = makeRoom();
  assert.equal(toggleDebugSeat(room, 0), true);
  assert.equal(isDebugSeatEnabled(room, 0), true);

  const hands = getDebugHandsForSeat(room, 0);
  assert.equal(hands.length, 4);
  assert.deepEqual(hands.map(hand => hand.seat), [0, 1, 2, 3]);
  assert.deepEqual(hands.map(hand => hand.cards.length), [13, 13, 13, 13]);
  assert.equal(hands[0].cards[0].code, '0-0');
});

test('0099 toggle off hides every hand from the host state again', () => {
  const room = makeRoom();
  assert.equal(toggleDebugSeat(room, 0), true);
  assert.equal(toggleDebugSeat(room, 0), false);
  assert.equal(isDebugSeatEnabled(room, 0), false);
  assert.equal(getDebugHandsForSeat(room, 0), null);
});

test('diagnostic state is isolated to the seat that enabled it', () => {
  const room = makeRoom();
  toggleDebugSeat(room, 0);
  assert.ok(getDebugHandsForSeat(room, 0));
  assert.equal(getDebugHandsForSeat(room, 1), null);
  assert.equal(isDebugSeatEnabled(room, 1), false);
});

test('diagnostic toggle rejects an invalid seat', () => {
  const room = makeRoom();
  assert.throws(() => toggleDebugSeat(room, 4), TypeError);
});

test('enabled diagnostics wait safely until cards have been dealt', () => {
  const room = makeRoom();
  room.hands = null;
  toggleDebugSeat(room, 0);
  assert.equal(getDebugHandsForSeat(room, 0), null);
});
