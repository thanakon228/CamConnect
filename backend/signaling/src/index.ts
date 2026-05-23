import { createServer } from 'node:http';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Server, Socket } from 'socket.io';
import admin from 'firebase-admin';

const PORT = Number(process.env.PORT ?? 4001);
const PAIR_CODE_TTL_MS = 10 * 60 * 1000; // pair code หมดอายุ 10 นาที

// ---- Firebase Admin init ----

// อ่าน service account จาก env (recommended) หรือ file firebase-admin.json
// ถ้าไม่มี → ไม่ตาย แค่ FCM ปลุกกล้องจะใช้ไม่ได้
const __dirname = dirname(fileURLToPath(import.meta.url));
const adminKeyFile = join(__dirname, '..', 'firebase-admin.json');

let fcmEnabled = false;
try {
  let cred: admin.ServiceAccount | null = null;
  if (process.env.FIREBASE_ADMIN_KEY) {
    cred = JSON.parse(process.env.FIREBASE_ADMIN_KEY);
  } else if (existsSync(adminKeyFile)) {
    cred = JSON.parse(readFileSync(adminKeyFile, 'utf-8'));
  }
  if (cred) {
    admin.initializeApp({ credential: admin.credential.cert(cred) });
    fcmEnabled = true;
    console.log('[fcm] Firebase Admin initialized — remote wake-up enabled');
  } else {
    console.warn('[fcm] No Firebase credentials — remote wake-up disabled');
  }
} catch (e) {
  console.error('[fcm] Failed to init Firebase Admin:', (e as Error).message);
}

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

const rooms = new Map<string, RoomInfo>();
const pairCodes = new Map<string, PairCodeInfo>();
const cameras = new Map<string, CameraInfo>();

// device_id → FCM token (เก็บถาวรในหน่วยความจำ — รีสตาร์ท server ก็หาย แต่ camera จะส่งใหม่ตอน register-camera)
const fcmTokens = new Map<string, string>();

// กัน spam push: device_id → timestamp ล่าสุดที่ส่ง
const lastPushAt = new Map<string, number>();
const PUSH_COOLDOWN_MS = 5_000; // ห้ามส่ง push ซ้ำใน 5 วินาที

// ลบ pair code ที่หมดอายุทุก 2 นาที
setInterval(() => {
  const now = Date.now();
  for (const [code, info] of pairCodes) {
    if (now - info.createdAt > PAIR_CODE_TTL_MS) {
      pairCodes.delete(code);
    }
  }
}, 2 * 60 * 1000);

// ---- FCM push helper ----

async function pushWakeCamera(deviceId: string): Promise<void> {
  if (!fcmEnabled) {
    console.warn(`[fcm] would wake ${deviceId.slice(0, 8)}… but FCM disabled`);
    return;
  }
  const token = fcmTokens.get(deviceId);
  if (!token) {
    console.warn(`[fcm] no token for ${deviceId.slice(0, 8)}…`);
    return;
  }
  const now = Date.now();
  const last = lastPushAt.get(deviceId) ?? 0;
  if (now - last < PUSH_COOLDOWN_MS) {
    console.log(`[fcm] cooldown — skip push to ${deviceId.slice(0, 8)}…`);
    return;
  }
  lastPushAt.set(deviceId, now);

  try {
    await admin.messaging().send({
      token,
      // notification + data → Android แสดง heads-up notification + tap → เปิด app
      notification: {
        title: 'เครื่องแม่ขอเปิดกล้อง',
        body: 'แตะเพื่ออนุญาตเปิดกล้องและเริ่มสตรีม',
      },
      data: { action: 'wake-camera', deviceId },
      android: {
        priority: 'high',
        ttl: 30_000,
        notification: {
          channelId: 'camconnect_wake_request',
          sound: 'default',
          defaultVibrateTimings: true,
          // visibility=public → แสดงบน lock screen
          visibility: 'public',
        },
      },
    });
    console.log(`[fcm] sent wake push to ${deviceId.slice(0, 8)}…`);
  } catch (e) {
    console.error(`[fcm] push failed for ${deviceId.slice(0, 8)}…:`, (e as Error).message);
    // token หมดอายุ → ลบทิ้ง camera จะส่งใหม่ตอน register
    if ((e as Error).message.includes('not-registered')) {
      fcmTokens.delete(deviceId);
    }
  }
}

// ---- Server ----

const httpServer = createServer((_req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    status: 'ok',
    rooms: rooms.size,
    pairCodes: pairCodes.size,
    cameras: cameras.size,
    fcmEnabled,
    fcmTokens: fcmTokens.size,
  }));
});

const io = new Server(httpServer, {
  cors: { origin: '*' },
});

io.on('connection', (socket: Socket) => {
  let currentRoom: string | null = null;
  let currentDeviceId: string | null = null;

  // camera แจ้งตัวตน: device_id + pair code (option) + fcm_token (option)
  socket.on(
    'register-camera',
    (payload: { deviceId?: string; code?: string; fcmToken?: string }) => {
      const deviceId = payload?.deviceId;
      const code = payload?.code;
      const fcmToken = payload?.fcmToken;

      if (typeof deviceId !== 'string' || deviceId.length < 8) {
        socket.emit('error', 'device_id ไม่ถูกต้อง');
        return;
      }

      cameras.set(deviceId, { socketId: socket.id });
      currentDeviceId = deviceId;

      if (typeof code === 'string' && code.length === 6) {
        pairCodes.set(code.toUpperCase(), { deviceId, createdAt: Date.now() });
      }

      if (typeof fcmToken === 'string' && fcmToken.length > 10) {
        fcmTokens.set(deviceId, fcmToken);
        console.log(
          `[register-camera] device=${deviceId.slice(0, 8)}… code=${code ?? '-'} fcm=${fcmToken.slice(0, 12)}…`,
        );
      } else {
        console.log(`[register-camera] device=${deviceId.slice(0, 8)}… code=${code ?? '-'} (no fcm)`);
      }

      socket.emit('register-camera-ok');
    },
  );

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

  // Room join — ถ้า camera ของ room นี้ offline และมี FCM token → ส่ง push ปลุก
  socket.on('join', (input: string) => {
    if (typeof input !== 'string') {
      socket.emit('error', 'join ต้องส่ง string');
      return;
    }

    let roomKey: string;
    if (input.length === 6) {
      const info = pairCodes.get(input.toUpperCase());
      if (!info) {
        socket.emit('error', 'ไม่พบรหัสนี้ หรือรหัสหมดอายุแล้ว');
        return;
      }
      roomKey = info.deviceId;
    } else {
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

    // ถ้าห้องนี้ camera ยังไม่เข้า (room มี viewer คนเดียว) และเรารู้ token ของ camera → ส่ง FCM ปลุก
    const cameraOnline = cameras.has(roomKey);
    if (!cameraOnline && room.members.size === 1) {
      console.log(`[join] camera ${roomKey.slice(0, 8)}… offline, sending wake push`);
      pushWakeCamera(roomKey).catch((e) => console.error('[fcm] push error:', e));
    }

    if (room.members.size === 2) {
      // peer-joined ต้องไปถึง camera (เพราะ camera เป็นคนสร้าง offer)
      // ปกติ: camera join ก่อน (เป็น peer แรก) → ส่งให้ peer แรก = camera ✓
      // FCM wake-up: viewer join ก่อน, camera join ทีหลัง → socket นี้คือ camera
      //   → ต้องส่งให้ตัวเอง (ไม่ใช่ peer แรก = viewer)
      const isCameraSocket = currentDeviceId === roomKey;
      if (isCameraSocket) {
        socket.emit('peer-joined');
      } else {
        socket.to(roomKey).emit('peer-joined');
      }
    }
  });

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
