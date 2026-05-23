import { createServer } from 'node:http';
import { Server, Socket } from 'socket.io';

const PORT = Number(process.env.PORT ?? 4001);
const ROOM_TTL_MS = 10 * 60 * 1000; // รหัสหมดอายุ 10 นาที

// ---- Types ----

interface RoomInfo {
  members: Set<string>; // socket IDs
  createdAt: number;
}

// ---- State (in-memory) ----

const rooms = new Map<string, RoomInfo>();

// ลบ room ที่หมดอายุทุก 2 นาที
setInterval(() => {
  const now = Date.now();
  for (const [code, room] of rooms) {
    if (now - room.createdAt > ROOM_TTL_MS) {
      rooms.delete(code);
    }
  }
}, 2 * 60 * 1000);

// ---- Server ----

const httpServer = createServer((_req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ status: 'ok', rooms: rooms.size }));
});

const io = new Server(httpServer, {
  cors: { origin: '*' },
});

io.on('connection', (socket: Socket) => {
  let currentRoom: string | null = null;

  // camera_app หรือ viewer_app เข้า room ด้วยรหัส
  socket.on('join', (code: string) => {
    if (typeof code !== 'string' || code.length !== 6) {
      socket.emit('error', 'รหัสต้องมี 6 หลัก');
      return;
    }

    const roomCode = code.toUpperCase();

    if (!rooms.has(roomCode)) {
      rooms.set(roomCode, { members: new Set(), createdAt: Date.now() });
    }

    const room = rooms.get(roomCode)!;
    if (room.members.size >= 2) {
      socket.emit('error', 'room เต็มแล้ว');
      return;
    }

    room.members.add(socket.id);
    socket.join(roomCode);
    currentRoom = roomCode;

    console.log(`[join] ${socket.id} → room ${roomCode} (${room.members.size}/2)`);

    // แจ้งอีกฝั่งว่ามีคนเข้ามาแล้ว
    if (room.members.size === 2) {
      socket.to(roomCode).emit('peer-joined');
    }
  });

  // WebRTC signaling relay
  socket.on('offer', (payload: unknown) => {
    if (currentRoom) socket.to(currentRoom).emit('offer', payload);
  });

  socket.on('answer', (payload: unknown) => {
    if (currentRoom) socket.to(currentRoom).emit('answer', payload);
  });

  socket.on('ice-candidate', (payload: unknown) => {
    if (currentRoom) socket.to(currentRoom).emit('ice-candidate', payload);
  });

  socket.on('disconnect', () => {
    if (!currentRoom) return;
    const room = rooms.get(currentRoom);
    if (room) {
      room.members.delete(socket.id);
      socket.to(currentRoom).emit('peer-left');
      if (room.members.size === 0) rooms.delete(currentRoom);
    }
    console.log(`[disconnect] ${socket.id} left room ${currentRoom}`);
  });
});

httpServer.listen(PORT, () => {
  console.log(`CamConnect signaling server running on :${PORT}`);
});
