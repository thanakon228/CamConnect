import { createServer } from 'node:http';
import { Server, Socket } from 'socket.io';

const PORT = Number(process.env.PORT ?? 4001);
const PAIR_CODE_TTL_MS = 10 * 60 * 1000; // pair code หมดอายุ 10 นาที

// ---- Types ----

interface RoomInfo {
  members: Set<string>; // socket IDs
  createdAt: number;
}

interface PairCodeInfo {
  deviceId: string;
  createdAt: number;
}

interface CameraInfo {
  socketId: string;
}

// ---- State (in-memory) ----

// room = device_id ของกล้อง (สำหรับ pairing ถาวร)
// หรือ room = pair-code 6 หลัก (สำหรับ backward compat ถ้าไม่ pair)
const rooms = new Map<string, RoomInfo>();

// pair-code ชั่วคราว 6 หลัก map ไป device_id ของกล้อง
const pairCodes = new Map<string, PairCodeInfo>();

// กล้องที่ online ตอนนี้
const cameras = new Map<string, CameraInfo>();

// ลบ pair code ที่หมดอายุทุก 2 นาที
setInterval(() => {
  const now = Date.now();
  for (const [code, info] of pairCodes) {
    if (now - info.createdAt > PAIR_CODE_TTL_MS) {
      pairCodes.delete(code);
    }
  }
}, 2 * 60 * 1000);

// ---- Server ----

const httpServer = createServer((_req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    status: 'ok',
    rooms: rooms.size,
    pairCodes: pairCodes.size,
    cameras: cameras.size,
  }));
});

const io = new Server(httpServer, {
  cors: { origin: '*' },
});

io.on('connection', (socket: Socket) => {
  let currentRoom: string | null = null;
  let currentDeviceId: string | null = null; // ถ้า socket นี้เป็นกล้อง

  // ----- Phase A: Pairing API -----

  // camera แจ้งตัวตน: ส่ง device_id + pair code (รหัส 6 หลัก ชั่วคราว)
  // server เก็บไว้เพื่อให้ viewer แลกรหัสเป็น device_id ได้
  socket.on('register-camera', (payload: { deviceId?: string; code?: string }) => {
    const deviceId = payload?.deviceId;
    const code = payload?.code;

    if (typeof deviceId !== 'string' || deviceId.length < 8) {
      socket.emit('error', 'device_id ไม่ถูกต้อง');
      return;
    }

    cameras.set(deviceId, { socketId: socket.id });
    currentDeviceId = deviceId;

    if (typeof code === 'string' && code.length === 6) {
      pairCodes.set(code.toUpperCase(), { deviceId, createdAt: Date.now() });
      console.log(`[register-camera] device=${deviceId.slice(0, 8)}… code=${code}`);
    } else {
      console.log(`[register-camera] device=${deviceId.slice(0, 8)}… (no code)`);
    }

    socket.emit('register-camera-ok');
  });

  // viewer แลกรหัสจับคู่เป็น device_id
  socket.on('pair-viewer', (payload: { code?: string }) => {
    const code = payload?.code;
    if (typeof code !== 'string' || code.length !== 6) {
      socket.emit('pair-viewer-error', 'รหัสต้องมี 6 หลัก');
      return;
    }

    const info = pairCodes.get(code.toUpperCase());
    if (!info) {
      socket.emit('pair-viewer-error', 'ไม่พบรหัสนี้ หรือรหัสหมดอายุแล้ว');
      return;
    }

    console.log(`[pair-viewer] code=${code} → device=${info.deviceId.slice(0, 8)}…`);
    socket.emit('pair-viewer-ok', { deviceId: info.deviceId });
  });

  // ----- Room join (รองรับทั้ง device_id และ pair code) -----

  socket.on('join', (input: string) => {
    if (typeof input !== 'string') {
      socket.emit('error', 'join ต้องส่ง string');
      return;
    }

    // ถ้าเป็น pair code 6 หลัก → resolve เป็น device_id ก่อน
    let roomKey: string;
    if (input.length === 6) {
      const info = pairCodes.get(input.toUpperCase());
      if (!info) {
        socket.emit('error', 'ไม่พบรหัสนี้ หรือรหัสหมดอายุแล้ว');
        return;
      }
      roomKey = info.deviceId;
    } else {
      // ถือว่าเป็น device_id ตรงๆ
      roomKey = input;
    }

    if (!rooms.has(roomKey)) {
      rooms.set(roomKey, { members: new Set(), createdAt: Date.now() });
    }

    const room = rooms.get(roomKey)!;
    if (room.members.size >= 2) {
      socket.emit('error', 'room เต็มแล้ว');
      return;
    }

    room.members.add(socket.id);
    socket.join(roomKey);
    currentRoom = roomKey;

    console.log(`[join] ${socket.id} → room ${roomKey.slice(0, 8)}… (${room.members.size}/2)`);

    if (room.members.size === 2) {
      socket.to(roomKey).emit('peer-joined');
    }
  });

  // ----- WebRTC signaling relay -----

  socket.on('offer', (payload: unknown) => {
    if (currentRoom) socket.to(currentRoom).emit('offer', payload);
  });

  socket.on('answer', (payload: unknown) => {
    if (currentRoom) socket.to(currentRoom).emit('answer', payload);
  });

  socket.on('ice-candidate', (payload: unknown) => {
    if (currentRoom) socket.to(currentRoom).emit('ice-candidate', payload);
  });

  // ----- Disconnect -----

  socket.on('disconnect', () => {
    if (currentDeviceId) {
      cameras.delete(currentDeviceId);
      console.log(`[disconnect-camera] device=${currentDeviceId.slice(0, 8)}…`);
    }
    if (currentRoom) {
      const room = rooms.get(currentRoom);
      if (room) {
        room.members.delete(socket.id);
        socket.to(currentRoom).emit('peer-left');
        if (room.members.size === 0) rooms.delete(currentRoom);
      }
      console.log(`[disconnect] ${socket.id} left room ${currentRoom.slice(0, 8)}…`);
    }
  });
});

httpServer.listen(PORT, () => {
  console.log(`CamConnect signaling server running on :${PORT}`);
});
