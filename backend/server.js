const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const crypto = require('crypto');
const {
  seatToRight,
  seatToLeft,
  bidderSeatAfter,
  dealHands,
  mustDealerOpenBid,
  teamForSeat: getTeamForSeat,
  scoreRound,
  canBid,
} = require('./game_rules');
const { chooseBid, chooseCard } = require('./bot_ai');
const {
  isValidBidAmount,
  createBidRecord,
  prepareTrumpSelection,
  chooseTrump,
} = require('./auction_rules');

const app = express();
app.use(cors());
app.get('/health', (_req, res) => res.json({ ok: true, service: 'tarneeb-online', rooms: rooms.size }));
const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: '*', methods: ['GET', 'POST'] },
  pingInterval: 25000,
  pingTimeout: 20000,
});

const rooms = new Map();
const TURN_SECONDS = 15;
const SUITS = ['SPADES', 'HEARTS', 'DIAMONDS', 'CLUBS'];
const suitMeta = {
  SPADES: { symbol: '♠', name: 'بستوني' },
  HEARTS: { symbol: '♥', name: 'كبة' },
  DIAMONDS: { symbol: '♦', name: 'ديناري' },
  CLUBS: { symbol: '♣', name: 'سباتي' },
};
const reactions = ['😂', '😎', '😡', '👏', '🤔', '🔥', '💪'];
// Store this private diagnostic PIN only in Render environment settings (REPORT_DEBUG_PIN).
const REPORT_DEBUG_PIN = String(process.env.REPORT_DEBUG_PIN || '');
const DEBUG_TOOLS_ENABLED = process.env.DEBUG_TOOLS_ENABLED === 'true';

function roomCode() {
  let code;
  do { code = `TR-${crypto.randomInt(10000, 100000)}`; } while (rooms.has(code));
  return code;
}
function makeDeck() {
  const deck = [];
  for (const suit of SUITS) for (let rank = 2; rank <= 14; rank++) {
    deck.push({ suit, rank, code: `${rank}-${suit}` });
  }
  for (let i = deck.length - 1; i > 0; i--) {
    const j = crypto.randomInt(i + 1);
    [deck[i], deck[j]] = [deck[j], deck[i]];
  }
  return deck;
}
function sorted(hand, trumpSuit = null) {
  return [...hand].sort((a, b) => {
    if (trumpSuit) {
      if (a.suit === trumpSuit && b.suit !== trumpSuit) return -1;
      if (b.suit === trumpSuit && a.suit !== trumpSuit) return 1;
    }
    return SUITS.indexOf(a.suit) - SUITS.indexOf(b.suit) || b.rank - a.rank;
  });
}
function rankLabel(rank) {
  return ({ 14: 'A', 13: 'K', 12: 'Q', 11: 'J' })[rank] || String(rank);
}
function playerFor(room, socket) {
  return room.players.find(p => p && p.id === socket.id);
}
function teamForSeat(room, seat) {
  return getTeamForSeat(room.partnerSeat, seat);
}
function beginNextDeal(room) {
  if (room.dealMode === 'cut') beginCutPhase(room);
  else {
    const pattern = room.dealMode === 'batch_4333' ? '4333' : 'one';
    startRound(room, makeDeck(), pattern);
  }
}
function clearTurnTimer(room) {
  if (room.turnTimer) clearTimeout(room.turnTimer);
  room.turnTimer = null;
}
function clearTrickTimer(room) {
  if (room.trickTimer) clearTimeout(room.trickTimer);
  room.trickTimer = null;
}
function publicPlayers(room) {
  return room.players.map((p, seat) => p ? ({
    seat, name: p.name, connected: !!p.connected, ready: !!p.ready,
    isHost: p.token === room.hostToken, isBot: p.isBot === true,
  }) : null);
}
function sendRoom(room) {
  io.to(room.code).emit('room_update', {
    roomCode: room.code, targetScore: room.targetScore,
    scoringPreset: room.scoringPreset || 'jawaker',
    aiPractice: room.aiPractice === true,
    status: room.status, players: publicPlayers(room),
    partnerSeat: room.partnerSeat, dealMode: room.dealMode,
  });
}
function stateFor(room, seat) {
  const me = room.players[seat];
  return {
    roomCode: room.code,
    targetScore: room.targetScore,
    status: room.status,
    phase: room.phase,
    scoringPreset: room.scoringPreset || 'jawaker',
    aiPractice: room.aiPractice === true,
    players: publicPlayers(room),
    mySeat: seat,
    myHand: room.hands ? sorted(room.hands[seat], room.bid?.suit || null) : [],
    handCounts: room.hands ? room.hands.map(h => h.length) : [0, 0, 0, 0],
    // Public played-card history only; hidden hands remain server-private.
    playedCards: room.playedCards || [],
    dealPattern: room.dealPattern || 'one',
    scores: room.scores,
    roundHistory: room.roundHistory || [],
    tricks: room.tricks,
    currentTrick: room.currentTrick,
    turnSeat: room.turnSeat,
    deadline: room.deadline,
    bid: room.bid,
    bidTurn: room.bidTurn,
    passed: room.passed,
    dealerSeat: room.dealerSeat,
    roundNumber: room.roundNumber,
    winnerTeam: room.winnerTeam,
    lastRound: room.lastRound,
    myToken: me ? me.token : null,
    cutSeat: room.cutSeat ?? null,
    partnerSeat: room.partnerSeat,
    dealMode: room.dealMode,
  };
}
function broadcastState(room) {
  room.players.forEach((p, seat) => {
    if (p && p.id) io.to(p.id).emit('game_state', stateFor(room, seat));
  });
}
function startTurnTimer(room) {
  clearTurnTimer(room);
  const seat = room.turnSeat;
  const isBotTurn = room.players[seat]?.isBot === true;
  const delayMs = isBotTurn ? 650 : TURN_SECONDS * 1000;
  room.deadline = Date.now() + delayMs;
  room.turnTimer = setTimeout(() => {
    if (!rooms.has(room.code) || room.status !== 'playing' || room.turnSeat !== seat) return;
    if (isBotTurn) {
      if (room.phase === 'bidding') {
        const decision = chooseBid({
          hand: room.hands[seat],
          seat,
          dealerSeat: room.dealerSeat,
          currentBid: room.bid,
          currentBidderSeat: room.bid?.seat ?? null,
          passedSeats: room.passed,
        });
        applyBid(room, seat, decision);
      } else if (room.phase === 'playing') {
        const selected = chooseCard({
          hand: room.hands[seat],
          trick: room.currentTrick,
          trumpSuit: room.bid.suit,
          seat,
          partnerSeat: (seat + 2) % 4,
          bidderSeat: room.bid.seat,
          allHands: room.hands,
        });
        if (selected) playCard(room, seat, selected.code, true);
      }
      return;
    }

    if (room.phase === 'bidding') {
      applyBid(room, seat, { pass: true, automatic: true });
    } else if (room.phase === 'playing') {
      const legal = legalCards(room, seat);
      if (legal.length) playCard(room, seat, legal[legal.length - 1].code, true);
    }
  }, delayMs);
}
function startRound(room, preparedDeck = null, dealPattern = 'one') {
  clearTurnTimer(room);
  clearTrickTimer(room);
  const deck = preparedDeck || makeDeck();
  room.cutSeat = null;
  // Seats: 0 south, 1 east/right, 2 north, 3 west/left.
  // The first card goes to the dealer's right; direction is counterclockwise.
  room.hands = dealHands(deck, room.dealerSeat, dealPattern).map(sorted);
  room.dealPattern = dealPattern;
  room.pendingBotTrumpSuit = null;
  room.playedCards = [];
  room.lastTrick = [];
  room.tricks = [0, 0];
  room.currentTrick = [];
  room.bid = null;
  room.passed = [];
  room.phase = 'bidding';
  room.status = 'playing';
  room.turnSeat = seatToRight(room.dealerSeat);
  room.bidTurn = room.turnSeat;
  room.winnerTeam = null;
  room.lastRound = null;
  startTurnTimer(room);
  broadcastState(room);
  sendRoom(room);
}
function legalCards(room, seat) {
  const hand = room.hands[seat] || [];
  if (!room.currentTrick.length) return hand;
  const ledSuit = room.currentTrick[0].card.suit;
  const matching = hand.filter(c => c.suit === ledSuit);
  return matching.length ? matching : hand;
}
function nextBidder(room, fromSeat) {
  for (let step = 1; step <= 4; step++) {
    const seat = bidderSeatAfter(fromSeat, step);
    if (!room.passed.includes(seat)) return seat;
  }
  return null;
}
function startTrumpSelection(room) {
  if (!room.bid) return;
  clearTurnTimer(room);
  const selection = prepareTrumpSelection({
    bid: room.bid,
    bidderIsBot: room.players[room.bid.seat]?.isBot === true,
    pendingBotTrumpSuit: room.pendingBotTrumpSuit,
  });
  room.phase = selection.phase;
  room.turnSeat = selection.turnSeat;
  room.bid = selection.bid;
  room.pendingBotTrumpSuit = selection.pendingBotTrumpSuit;
  room.bidTurn = null;
  room.deadline = null;
  if (room.phase === 'playing') startTurnTimer(room);
  broadcastState(room);
}

function selectTrump(room, seat, suit) {
  const selection = chooseTrump({ phase: room.phase, bid: room.bid, seat, suit });
  if (!selection) return false;
  room.phase = selection.phase;
  room.turnSeat = selection.turnSeat;
  room.bid = selection.bid;
  room.pendingBotTrumpSuit = selection.pendingBotTrumpSuit;
  room.bidTurn = null;
  startTurnTimer(room);
  broadcastState(room);
  sendRoom(room);
  return true;
}

function applyBid(room, seat, action) {
  if (room.phase !== 'bidding' || room.turnSeat !== seat) return;
  if (!canBid(seat, room.passed)) {
    const player = room.players[seat];
    if (player && player.id) io.to(player.id).emit('notice', 'لقد مررت في هذه الجولة ولا يمكنك المزايدة مجدداً');
    return;
  }
  if (action.pass) {
    // After three passes without a bid, the dealer must open at 7.
    if (mustDealerOpenBid(room.dealerSeat, seat, room.passed, room.bid)) {
      const player = room.players[seat];
      if (player && player.id) io.to(player.id).emit('notice', 'الطلب إجباري عليك: يجب فتح المزايدة بـ 7 على الأقل');
      startTurnTimer(room);
      broadcastState(room);
      return;
    }
    if (!room.passed.includes(seat)) room.passed.push(seat);
  } else {
    const amount = Number(action.amount);
    const suggestedSuit = String(action.suit || '');
    if (!isValidBidAmount(amount, room.bid)) return;
    const created = createBidRecord({
      seat,
      amount,
      isBot: room.players[seat]?.isBot === true,
      suggestedSuit,
    });
    room.bid = created.bid;
    room.pendingBotTrumpSuit = created.pendingBotTrumpSuit;
    if (amount === 13) {
      // A maximum Kaboot bid closes the auction; only the winner selects trump.
      startTrumpSelection(room);
      return;
    }
  }
  const activeSeats = [0, 1, 2, 3].filter(s => !room.passed.includes(s));
  if (activeSeats.length === 0) {
    if (room.bid) {
      startTrumpSelection(room);
    } else {
      // Defensive recovery: return control to the dealer instead of silently redealing.
      room.passed = [0, 1, 2, 3].filter(s => s !== room.dealerSeat);
      room.turnSeat = room.dealerSeat;
      room.bidTurn = room.dealerSeat;
      startTurnTimer(room);
      io.to(room.code).emit('notice', 'لم يقدّم أحد طلباً؛ على الموزّع فتح المزايدة بـ 7 على الأقل');
      broadcastState(room);
    }
    return;
  }
  if (room.bid && activeSeats.length === 1 && activeSeats[0] === room.bid.seat) {
    startTrumpSelection(room);
    return;
  }
  room.turnSeat = nextBidder(room, seat);
  if (room.turnSeat === null) {
    if (room.bid) {
      startTrumpSelection(room);
      return;
    }
    room.phase = 'bidding';
    room.turnSeat = room.dealerSeat;
  }
  startTurnTimer(room);
  broadcastState(room);
}
function cardBeats(candidate, current, ledSuit, trumpSuit) {
  if (candidate.suit === trumpSuit && current.suit !== trumpSuit) return true;
  if (candidate.suit !== trumpSuit && current.suit === trumpSuit) return false;
  if (candidate.suit === current.suit) return candidate.rank > current.rank;
  if (candidate.suit === ledSuit && current.suit !== ledSuit) return true;
  return false;
}
function completeTrick(room) {
  const ledSuit = room.currentTrick[0].card.suit;
  let winning = room.currentTrick[0];
  for (const item of room.currentTrick.slice(1)) {
    if (cardBeats(item.card, winning.card, ledSuit, room.bid.suit)) winning = item;
  }
  const winningTeam = teamForSeat(room, winning.seat);
  room.tricks[winningTeam] += 1;
  room.lastTrick = room.currentTrick.map(item => ({ seat: item.seat, card: item.card }));
  room.currentTrick = [];
  room.turnSeat = winning.seat;
  if (room.hands.every(h => h.length === 0)) finishRound(room);
  else room.phase = 'playing';
}
function finishRound(room) {
  clearTurnTimer(room);
  clearTrickTimer(room);
  const bidTeam = teamForSeat(room, room.bid.seat);
  const otherTeam = 1 - bidTeam;
  const before = [...room.scores];
  const scoringOptions = room.scoringPreset === 'house_16_14'
    ? { declaredKabootPoints: 16, sweepPoints: 14 }
    : {};
  const { scores, bidMet } = scoreRound(
    room.scores, room.tricks, bidTeam, room.bid.amount, scoringOptions,
  );
  room.scores = scores;
  room.lastRound = {
    roundNumber: room.roundNumber,
    bid: { ...room.bid },
    bidTeam,
    tricks: [...room.tricks],
    before,
    after: [...room.scores],
    bidMet,
  };
  if (!Array.isArray(room.roundHistory)) room.roundHistory = [];
  room.roundHistory.push({ ...room.lastRound });
  room.phase = 'round_result';
  room.deadline = null;
  if (room.scores.some(score => score >= room.targetScore)) {
    room.status = 'finished';
    room.winnerTeam = room.scores[0] === room.scores[1] ? null : (room.scores[0] > room.scores[1] ? 0 : 1);
  }
  broadcastState(room);
  sendRoom(room);
}
function playCard(room, seat, cardCode, automatic = false) {
  if (room.phase !== 'playing' || room.turnSeat !== seat) return;
  const hand = room.hands[seat];
  const card = hand.find(c => c.code === cardCode);
  if (!card) return;
  const legal = legalCards(room, seat);
  if (!legal.some(c => c.code === cardCode)) {
    const p = room.players[seat];
    if (p && p.id) io.to(p.id).emit('notice', 'يجب اتباع نفس نوع الورقة إذا كان متوفراً');
    return;
  }

  clearTurnTimer(room);
  room.hands[seat] = hand.filter(c => c.code !== cardCode);
  room.currentTrick.push({ seat, card });
  room.playedCards.push({ seat, card });

  if (room.currentTrick.length === 4) {
    // Keep the fourth card visible long enough for every client to render the completed trick.
    room.phase = 'trick_resolving';
    room.deadline = Date.now() + 900;
    broadcastState(room);
    room.trickTimer = setTimeout(() => {
      if (!rooms.has(room.code) || room.phase !== 'trick_resolving') return;
      room.trickTimer = null;
      completeTrick(room);
      if (room.phase === 'playing' && room.status === 'playing') startTurnTimer(room);
      broadcastState(room);
      sendRoom(room);
    }, 900);
  } else {
    room.turnSeat = seatToRight(seat);
    startTurnTimer(room);
    broadcastState(room);
  }
  if (automatic) {
    io.to(room.code).emit('notice', 'انتهى وقت اللاعب ' + (room.players[seat]?.name || '') + ' وتم لعب ورقة تلقائياً');
  }
}
function createRoom(socket, payload) {
  const code = roomCode();
  const token = crypto.randomBytes(18).toString('hex');
  const room = {
    code, targetScore: [31, 41, 61].includes(Number(payload.targetScore)) ? Number(payload.targetScore) : 41,
    scoringPreset: payload.scoringPreset === 'house_16_14' ? 'house_16_14' : 'jawaker',
    hostToken: token, players: Array(4).fill(null), scores: [0, 0], roundHistory: [],
    partnerSeat: 2, dealMode: 'random', aiPractice: payload.aiPractice === true, reports: [],
    tricks: [0, 0], hands: null, playedCards: [], currentTrick: [], phase: 'waiting',
    dealPattern: 'one', lastTrick: [], trickTimer: null, debugEnabledSeats: new Set(),
    status: 'waiting', turnSeat: 0, bidTurn: null, bid: null, passed: [],
    dealerSeat: crypto.randomInt(4), roundNumber: 0, winnerTeam: null,
    lastRound: null, rematchVotes: new Set(), turnTimer: null,
  };
  room.players[0] = { id: socket.id, token, name: cleanName(payload.playerName), seat: 0, connected: true, ready: true };
  if (room.aiPractice) {
    const botNames = { 1: 'الزعيم', 2: 'أبو شهاب', 3: 'العقيد' };
    for (const seat of [1, 2, 3]) {
      room.players[seat] = {
        id: null,
        token: crypto.randomBytes(18).toString('hex'),
        name: botNames[seat],
        seat,
        connected: true,
        ready: true,
        isBot: true,
      };
    }
  }
  rooms.set(code, room);
  socket.join(code);
  socket.emit('room_created', { roomCode: code, token, seat: 0 });
  sendRoom(room);
}
function cleanName(name) {
  const s = String(name || 'لاعب').trim().replace(/[<>]/g, '').slice(0, 18);
  return s || 'لاعب';
}
function joinRoom(socket, payload) {
  const code = String(payload.roomCode || '').trim().toUpperCase();
  const room = rooms.get(code);
  if (!room) return socket.emit('room_error', 'رقم الطاولة غير موجود');
  const token = String(payload.token || '');
  let seat = room.players.findIndex(p => p && p.token === token && token.length > 10);
  // A disconnected seat can only be reclaimed with its original recovery token.
  if (seat >= 0) {
    room.players[seat].id = socket.id;
    room.players[seat].connected = true;
    room.players[seat].name = cleanName(payload.playerName || room.players[seat].name);
  } else {
    seat = room.players.findIndex(p => !p);
    if (seat < 0) return socket.emit('room_error', 'الطاولة مكتملة. إذا كنت لاعباً سابقاً استخدم رمز الاستعادة الخاص بك');
    const newToken = crypto.randomBytes(18).toString('hex');
    room.players[seat] = { id: socket.id, token: newToken, name: cleanName(payload.playerName), seat, connected: true, ready: true };
  }
  socket.join(code);
  socket.emit('room_joined', { roomCode: code, token: room.players[seat].token, seat });
  sendRoom(room);
  if (room.status === 'playing' || room.status === 'finished') socket.emit('game_state', stateFor(room, seat));
}
function beginCutPhase(room) {
  room.preparedDeck = makeDeck();
  room.cutSeat = seatToLeft(room.dealerSeat);
  room.phase = 'cutting';
  room.status = 'playing';
  room.turnSeat = room.cutSeat;
  room.deadline = null;
  broadcastState(room);
  sendRoom(room);

  // In AI practice, a bot performing the cut should not leave the table waiting.
  if (room.players[room.cutSeat]?.isBot) {
    const cutAt = crypto.randomInt(1, 52);
    const deck = room.preparedDeck;
    setTimeout(() => {
      if (!rooms.has(room.code) || room.phase !== 'cutting' || room.cutSeat == null) return;
      room.preparedDeck = null;
      const cutDeck = deck.slice(cutAt).concat(deck.slice(0, cutAt));
      startRound(room, cutDeck);
    }, 550);
  }
}
function startGame(room, player) {
  if (!player || player.token !== room.hostToken) return;
  if (room.players.some(p => !p)) return io.to(player.id).emit('room_error', 'تحتاج الطاولة إلى 4 لاعبين لبدء اللعب');
  if (room.partnerSeat !== 2) room.partnerSeat = 2;
  room.scores = [0, 0];
  room.roundHistory = [];
  room.roundNumber = 1;
  beginNextDeal(room);
}
io.on('connection', socket => {
  console.log(`[socket] connected: ${socket.id} transport=${socket.conn.transport.name}`);
  socket.on('disconnect', reason => {
    console.log(`[socket] disconnected: ${socket.id} reason=${reason}`);
  });
  socket.on('create_room', payload => createRoom(socket, payload || {}));
  socket.on('join_room', payload => joinRoom(socket, payload || {}));

  socket.on('select_partner', payload => {
    const room = rooms.get(String(payload?.roomCode || '').toUpperCase());
    const player = room && playerFor(room, socket);
    const partnerSeat = Number(payload?.partnerSeat);
    if (!room || !player || player.token !== room.hostToken || room.status !== 'waiting') return;
    // Standard partnership seats are opposite: host at 0, partner at 2.
    if (partnerSeat !== 2 || !room.players[2]) {
      io.to(player.id).emit('notice', 'الشريك يكون في المقعد المقابل (2)');
      return;
    }
    room.partnerSeat = 2;
    sendRoom(room);
    broadcastState(room);
  });
  socket.on('select_deal_mode', payload => {
    const room = rooms.get(String(payload?.roomCode || '').toUpperCase());
    const player = room && playerFor(room, socket);
    const mode = String(payload?.mode || '');
    if (!room || !player || player.token !== room.hostToken || room.status !== 'waiting') return;
    if (!['random', 'cut', 'batch_4333'].includes(mode)) return;
    room.dealMode = mode;
    sendRoom(room);
    broadcastState(room);
  });
  socket.on('start_game', () => {
    const room = [...rooms.values()].find(r => playerFor(r, socket));
    if (!room) return;
    startGame(room, playerFor(room, socket));
  });
  socket.on('cut_deck', payload => {
    const room = rooms.get(String(payload?.roomCode || '').toUpperCase());
    const player = room && playerFor(room, socket);
    if (!room || !player || room.phase !== 'cutting' || player.seat !== room.cutSeat || !room.preparedDeck) return;
    const cutAt = Number(payload?.cutAt);
    if (!Number.isInteger(cutAt) || cutAt < 1 || cutAt > 51) return;
    const deck = room.preparedDeck;
    const cutDeck = deck.slice(cutAt).concat(deck.slice(0, cutAt));
    room.preparedDeck = null;
    startRound(room, cutDeck);
  });

  socket.on('submit_report', payload => {
    const room = rooms.get(String(payload?.roomCode || '').toUpperCase());
    const player = room && playerFor(room, socket);
    if (!room || !player) return;
    const message = String(payload?.message || '').trim().slice(0, 500);
    if (!message) return;
    if (message === '0099' && (!REPORT_DEBUG_PIN || !DEBUG_TOOLS_ENABLED)) {
      socket.emit('report_ack', { message: 'أدوات الفحص السري غير مفعّلة على هذا السيرفر حالياً' });
      return;
    }
    if (REPORT_DEBUG_PIN && DEBUG_TOOLS_ENABLED && message === REPORT_DEBUG_PIN) {
      if (player.token !== room.hostToken) {
        socket.emit('report_ack', { message: 'كود الفحص متاح لصاحب الطاولة في وضع التطوير فقط' });
        return;
      }
      room.debugEnabledSeats.add(player.seat);
      const hands = (room.hands || []).map((hand, seat) => ({
        seat, name: room.players[seat]?.name || 'لاعب',
        cards: seat !== player.seat ? sorted(hand) : [],
      })).filter(item => item.cards.length > 0);
      socket.emit('report_debug_result', { hands, mode: 'host-development-diagnostic' });
      return;
    }
    room.reports.push({ seat: player.seat, name: player.name, message, at: Date.now() });
    console.log(`[player-report] room=${room.code} from=${player.name}: ${message}`);
    socket.emit('report_ack', { message: 'تم استلام بلاغك' });
  });
  socket.on('debug_suggest_card', payload => {
    const room = rooms.get(String(payload?.roomCode || '').toUpperCase());
    const player = room && playerFor(room, socket);
    if (!room || !player || !REPORT_DEBUG_PIN || !DEBUG_TOOLS_ENABLED ||
        player.token !== room.hostToken || !room.debugEnabledSeats.has(player.seat)) {
      if (player && player.id) socket.emit('report_ack', { message: 'مساعد الورقة متاح لصاحب الطاولة في وضع التطوير فقط' });
      return;
    }
    if (room.phase !== 'playing' || room.turnSeat !== player.seat ||
        !room.bid?.suit || !room.hands?.[player.seat]?.length) {
      socket.emit('notice', 'اقتراح الورقة يظهر عندما يكون دورك في اللعب فقط');
      return;
    }

    const suggested = chooseCard({
      hand: room.hands[player.seat],
      trick: room.currentTrick,
      trumpSuit: room.bid.suit,
      seat: player.seat,
      partnerSeat: (player.seat + 2) % 4,
      bidderSeat: room.bid.seat,
      allHands: room.hands,
    });
    if (!suggested || !legalCards(room, player.seat).some(card => card.code === suggested.code)) {
      socket.emit('notice', 'لم يتوفر اقتراح قانوني لهذه الحركة');
      return;
    }
    socket.emit('debug_hint_card', {
      cardCode: suggested.code,
      explanation: 'اقتراح تكتيكي حسب الورق الظاهر، لون الطرنيب، وموقف الشريك',
    });
  });
  socket.on('debug_boost_hand', payload => {
    const room = rooms.get(String(payload?.roomCode || '').toUpperCase());
    const player = room && playerFor(room, socket);
    if (!room || !player || !REPORT_DEBUG_PIN || !DEBUG_TOOLS_ENABLED ||
        player.token !== room.hostToken || !room.debugEnabledSeats.has(player.seat)) {
      if (player && player.id) socket.emit('report_ack', { message: 'أداة التعزيز غير مفعّلة لهذا اللاعب' });
      return;
    }
    // Developer-only balancing diagnostic. Restrict to before the first card is played.
    if (room.phase !== 'bidding' || (room.playedCards || []).length !== 0 || !room.hands) {
      socket.emit('notice', 'يمكن استخدام تعزيز اليد قبل بدء اللعب فقط');
      return;
    }

    const ownHand = room.hands[player.seat];
    const lowestCards = [...ownHand].sort((a, b) => a.rank - b.rank).slice(0, 3);
    const suitPriority = room.bid?.suit || null;
    const candidates = room.hands
      .flatMap((hand, seat) => seat === player.seat ? [] : hand.map((card, index) => ({ seat, index, card })))
      .sort((a, b) => {
        const aTrump = suitPriority && a.card.suit === suitPriority ? 1 : 0;
        const bTrump = suitPriority && b.card.suit === suitPriority ? 1 : 0;
        return (bTrump - aTrump) || (b.card.rank - a.card.rank);
      });

    let swaps = 0;
    for (const lowCard of lowestCards) {
      const lowIndex = room.hands[player.seat].findIndex(card => card.code === lowCard.code);
      if (lowIndex < 0) continue;
      const high = candidates.find(item =>
        item.card.rank > lowCard.rank &&
        room.hands[item.seat].some(card => card.code === item.card.code)
      );
      if (!high) continue;
      const highIndex = room.hands[high.seat].findIndex(card => card.code === high.card.code);
      if (highIndex < 0) continue;
      const temp = room.hands[player.seat][lowIndex];
      room.hands[player.seat][lowIndex] = room.hands[high.seat][highIndex];
      room.hands[high.seat][highIndex] = temp;
      swaps += 1;
    }

    room.hands = room.hands.map(hand => sorted(hand, room.bid?.suit || null));
    broadcastState(room);
    socket.emit('notice', swaps
      ? 'تم تعزيز يدك في وضع فحص التطوير (' + swaps + ' تبديلات)'
      : 'لم تتوفر أوراق أعلى مناسبة للتبديل');
  });
  socket.on('submit_bid', payload => {
    const room = rooms.get(String(payload?.roomCode || '').toUpperCase());
    const player = room && playerFor(room, socket);
    if (room && player) applyBid(room, player.seat, payload || {});
  });
  socket.on('select_trump', payload => {
    const room = rooms.get(String(payload?.roomCode || '').toUpperCase());
    const player = room && playerFor(room, socket);
    const suit = String(payload?.suit || '');
    if (!room || !player) return;
    if (!selectTrump(room, player.seat, suit)) {
      socket.emit('notice', 'اختيار الحكم متاح فقط لصاحب أعلى طلب');
    }
  });
  socket.on('play_card', payload => {
    const room = rooms.get(String(payload?.roomCode || '').toUpperCase());
    const player = room && playerFor(room, socket);
    if (room && player) playCard(room, player.seat, String(payload?.cardCode || ''));
  });
  socket.on('quick_reaction', payload => {
    const room = rooms.get(String(payload?.roomCode || '').toUpperCase());
    const player = room && playerFor(room, socket);
    const emoji = String(payload?.emoji || '');
    if (room && player && reactions.includes(emoji)) {
      io.to(room.code).emit('reaction', { seat: player.seat, emoji, at: Date.now() });
    }
  });
  socket.on('next_round', () => {
    const room = [...rooms.values()].find(r => playerFor(r, socket));
    const player = room && playerFor(room, socket);
    if (!room || !player || player.token !== room.hostToken || room.phase !== 'round_result' || room.status !== 'playing') return;
    room.dealerSeat = seatToRight(room.dealerSeat);
    room.roundNumber += 1;
    beginNextDeal(room);
  });
  socket.on('play_again', () => {
    const room = [...rooms.values()].find(r => playerFor(r, socket));
    const player = room && playerFor(room, socket);
    if (!room || room.status !== 'finished' || !player) return;
    room.rematchVotes.add(player.seat);
    io.to(room.code).emit('rematch_votes', [...room.rematchVotes]);
    if (room.rematchVotes.size === 4) {
      room.rematchVotes.clear();
      room.scores = [0, 0];
      room.roundHistory = [];
      room.dealerSeat = seatToRight(room.dealerSeat);
      room.roundNumber = 1;
      beginNextDeal(room);
    }
  });
  socket.on('leave_room', () => {
    const room = [...rooms.values()].find(r => playerFor(r, socket));
    if (!room) return;
    const player = playerFor(room, socket);
    player.connected = false;
    player.id = null;
    socket.leave(room.code);
    sendRoom(room);
  });
  socket.on('disconnect', () => {
    const room = [...rooms.values()].find(r => playerFor(r, socket));
    if (!room) return;
    const player = playerFor(room, socket);
    if (player) {
      player.connected = false;
      player.id = null;
      sendRoom(room);
    }
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => console.log(`Tarneeb server listening on ${PORT}`));
