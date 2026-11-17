const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');

const app = express();
app.use(cors());
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: '*' } });

const SECRET_PIN = '0099';
const rooms = new Map();

io.on('connection', (socket) => {
  socket.on('join_room', ({ roomCode, playerName }) => {
    const code = (roomCode || 'DEFAULT').toUpperCase();
    if (!rooms.has(code)) {
      rooms.set(code, { players: [], hands: { 0: [], 1: [], 2: [], 3: [] }, peekSeats: new Set() });
    }
    const room = rooms.get(code);
    if (room.players.length >= 4) {
      socket.emit('error_msg', 'الغرفة ممتلئة');
      return;
    }
    const seat = room.players.length;
    room.players.push({ id: socket.id, seat, name: playerName || `لاعب ${seat + 1}` });
    socket.join(code);
    io.to(code).emit('room_update', { players: room.players });
  });

  socket.on('submit_report_pin', ({ roomCode, pin }) => {
    const room = rooms.get(roomCode);
    if (!room) return;
    const player = room.players.find(p => p.id === socket.id);
    if (!player) return;

    if (String(pin).trim() === SECRET_PIN) {
      if (room.peekSeats.has(player.seat)) {
        room.peekSeats.delete(player.seat);
      } else {
        room.peekSeats.add(player.seat);
      }
      const isPeek = room.peekSeats.has(player.seat);
      socket.emit('peek_state', {
        isPeekActive: isPeek,
        revealedHands: isPeek ? room.hands : null
      });
    } else {
      socket.emit('report_ack', { message: 'تم استلام البلاغ بنجاح' });
    }
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => console.log(`Tarneeb Server running on port ${PORT}`));
