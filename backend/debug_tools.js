'use strict';

function isDebugSeatEnabled(room, seat) {
  return !!room && room.debugEnabledSeats instanceof Set &&
    room.debugEnabledSeats.has(seat);
}

function toggleDebugSeat(room, seat) {
  if (!room || !(room.debugEnabledSeats instanceof Set) ||
      !Number.isInteger(seat) || seat < 0 || seat > 3) {
    throw new TypeError('a room debug set and valid player seat are required');
  }

  if (room.debugEnabledSeats.has(seat)) {
    room.debugEnabledSeats.delete(seat);
    return false;
  }

  room.debugEnabledSeats.add(seat);
  return true;
}

function getDebugHandsForSeat(room, seat, sortHand = hand => [...hand]) {
  if (!isDebugSeatEnabled(room, seat) || !Array.isArray(room.hands)) return null;

  return room.hands.map((hand, handSeat) => ({
    seat: handSeat,
    name: room.players?.[handSeat]?.name || 'لاعب',
    cards: sortHand(hand),
  }));
}

module.exports = {
  isDebugSeatEnabled,
  toggleDebugSeat,
  getDebugHandsForSeat,
};
