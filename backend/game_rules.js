'use strict';

function assertSeat(seat) {
  if (!Number.isInteger(seat) || seat < 0 || seat > 3) {
    throw new RangeError('seat must be an integer from 0 to 3');
  }
}

function seatToRight(seat) {
  assertSeat(seat);
  return (seat + 3) % 4;
}

function seatToLeft(seat) {
  assertSeat(seat);
  return (seat + 1) % 4;
}

function dealSeatForCard(dealerSeat, cardIndex) {
  assertSeat(dealerSeat);
  if (!Number.isInteger(cardIndex) || cardIndex < 0 || cardIndex >= 52) {
    throw new RangeError('cardIndex must be an integer from 0 to 51');
  }
  return (dealerSeat + 3 * (cardIndex + 1)) % 4;
}

function bidderSeatAfter(fromSeat, step) {
  assertSeat(fromSeat);
  if (!Number.isInteger(step) || step < 1 || step > 4) {
    throw new RangeError('step must be an integer from 1 to 4');
  }
  return (fromSeat + 4 - step) % 4;
}

function teamForSeat(partnerSeat, seat) {
  assertSeat(seat);
  if (![1, 2, 3].includes(partnerSeat)) {
    throw new RangeError('partnerSeat must be one of the other three seats');
  }
  return seat === 0 || seat === partnerSeat ? 0 : 1;
}

function scoreRound(scores, tricks, bidTeam, bidAmount) {
  if (!Array.isArray(scores) || scores.length !== 2 ||
      !scores.every(Number.isFinite)) {
    throw new TypeError('scores must contain two finite numbers');
  }
  if (!Array.isArray(tricks) || tricks.length !== 2 ||
      !tricks.every(Number.isInteger) ||
      tricks.some(value => value < 0 || value > 13) ||
      tricks[0] + tricks[1] !== 13) {
    throw new RangeError('tricks must be two non-negative integers totaling 13');
  }
  if (bidTeam !== 0 && bidTeam !== 1) {
    throw new RangeError('bidTeam must be 0 or 1');
  }
  if (!Number.isInteger(bidAmount) || bidAmount < 7 || bidAmount > 13) {
    throw new RangeError('bidAmount must be an integer from 7 to 13');
  }

  const result = [...scores];
  const otherTeam = 1 - bidTeam;
  const bidMet = tricks[bidTeam] >= bidAmount;
  const allTricksTeam = tricks[0] === 13 ? 0 : (tricks[1] === 13 ? 1 : null);

  if (bidAmount === 13) {
    if (bidMet) {
      result[bidTeam] += 26;
    } else {
      result[bidTeam] -= 16;
      result[otherTeam] += allTricksTeam === otherTeam ? 16 : tricks[otherTeam];
    }
  } else if (allTricksTeam !== null) {
    result[allTricksTeam] += 16;
    if (allTricksTeam === otherTeam) result[bidTeam] -= bidAmount;
  } else if (bidMet) {
    result[bidTeam] += tricks[bidTeam];
  } else {
    result[bidTeam] -= bidAmount;
    result[otherTeam] += tricks[otherTeam];
  }

  return { scores: result, bidMet };
}

module.exports = {
  seatToRight,
  seatToLeft,
  dealSeatForCard,
  bidderSeatAfter,
  teamForSeat,
  scoreRound,
};
