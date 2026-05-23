# Handoff — CamConnect

> Project ที่ root: `B:\Users\thana\Desktop\ClaudeCode\CamConnect`
> GitHub: https://github.com/thanakon228/CamConnect
> Branch ปัจจุบัน: `master`

## เป้าหมาย (Goal)

ระบบดูกล้องระยะไกลแบบ "set-and-forget" สำหรับครอบครัว:
- **ฝั่งกล้อง (ลูก)**: เปิดแอปครั้งเดียวกดเริ่มสตรีม → ปิดแอป/ล็อคเครื่องได้ กล้องยังสตรีมตลอด
- **ฝั่งแม่ (viewer)**: ใส่รหัส 6 หลักครั้งเดียว → เปิดแอปเมื่อไรก็ดูได้เลย ไม่ต้องใส่รหัสซ้ำ
- WebRTC peer-to-peer ผ่าน Socket.IO signaling server (รัน local LAN)

### หลังจาก setup ครั้งแรกแล้ว flow ที่ใช้งานจริงคือ
1. แม่เปิดแอป viewer → เห็นกล้องลูกทันที (ผ่าน device_id ที่ pair ไว้)
2. ลูกไม่ต้องทำอะไรกับมือถือ — กล้องสตรีมเองผ่าน Foreground Service

---

## ความคืบหน้าปัจจุบัน (Current Progress) — ทำเสร็จแล้วทั้งหมด

### Phase 1: Core WebRTC + Signaling
- ✅ Signaling server (Node.js + TypeScript + Socket.IO) ที่ `backend/signaling/`
- ✅ camera_app (Flutter + flutter_webrtc 1.4.1) ส่งกล้องหลัง
- ✅ viewer_app (Flutter + flutter_webrtc 1.4.1) รับ video stream
- ✅ ทำงานข้ามเครื่อง: **Samsung Galaxy A55 (Android 16)** ↔ **LDPlayer (Android 9)**

### Phase 2: แก้บั๊ก WebRTC native crash
- ✅ พบว่าขาด permission `ACCESS_NETWORK_STATE` → libjingle native crash ใน network_thread
- ✅ เพิ่ม network/wifi/bluetooth permissions ครบ
- ✅ ใช้ `iceServers: []` (LAN-only, ไม่ STUN)
- ✅ Lazy PeerConnection — สร้างหลัง viewer join เพื่อลดความซับซ้อน

### Phase 3: One-time Pairing (Phase A)
- ✅ camera มี persistent UUID เก็บใน SharedPreferences (`device_id.dart`)
- ✅ Signaling server map `code → device_id` ผ่าน event `register-camera` / `pair-viewer`
- ✅ viewer เก็บ `paired_device_id` (`pairing_storage.dart`)
- ✅ viewer auto-route ไป LiveView ถ้ามี paired (`main.dart` ใช้ FutureBuilder)
- ✅ ปุ่ม "เลิกจับคู่" ใน LiveViewScreen

### Phase 4: Auto-streaming + Foreground Service (Phase B)
- ✅ Android Foreground Service ประเภท `camera|microphone` (`CameraStreamingService.kt`)
- ✅ MethodChannel `com.camconnect.camera_app/foreground_service` (`foreground_service.dart`)
- ✅ Wake lock PARTIAL กัน Doze mode
- ✅ Persistent notification + ปุ่ม Stop
- ✅ Flag `auto_streaming_enabled` ใน SharedPreferences (`streaming_prefs.dart`)
- ✅ home_screen auto-navigate ไป Streaming ถ้า flag เปิด + ปุ่ม "หยุดอัตโนมัติ"
- ✅ BootReceiver — launch MainActivity หลังรีบูตเครื่อง

### Phase 5: กันโดน swipe จาก Recent
- ✅ `excludeFromRecents="true"` — app หายจาก Recent Tasks
- ✅ `autoRemoveFromRecents="false"`, `finishOnTaskLaunch="false"`, `relinquishTaskIdentity="true"`
- ✅ ResurrectReceiver + AlarmManager `setAndAllowWhileIdle` — bypass Android 12+ BAL
- ✅ ทดสอบแล้ว: camera_app ไม่ปรากฏใน Recent Tasks UI

---

## สิ่งที่ได้ผล (What Worked)

### Native libwebrtc on Android — สำคัญมาก
- **ใส่ permissions ครบ** ใน AndroidManifest โดยเฉพาะ `ACCESS_NETWORK_STATE` ไม่งั้น native crash
- ใช้ `flutter_webrtc: ^1.4.1` (1.4.1 latest as of session) — รุ่น 0.11.7 มีปัญหา Registrar API
- `compileSdk = 35` ใน app's build.gradle.kts
- `iceServers: []` พอสำหรับ LAN — ไม่ต้อง STUN

### LDPlayer network
- LDPlayer ใช้ bridged network ไม่ใช่ standard emulator
- ใช้ `http://<host-LAN-IP>:4001` (เช่น `192.168.1.33:4001`) ทั้ง camera + viewer
- `10.0.2.2` **ใช้ไม่ได้** กับ LDPlayer (`ping 10.0.2.2` = 100% packet loss)

### Foreground Service + Camera ใน Android 14+
- ประกาศ `android:foregroundServiceType="camera|microphone"` ใน manifest
- ใส่ permissions `FOREGROUND_SERVICE_CAMERA` + `FOREGROUND_SERVICE_MICROPHONE` + `POST_NOTIFICATIONS`
- `startForeground(id, notification, type)` ใส่ type ตอน Android 10+
- Service ไม่ได้แตะกล้องเอง — แค่ "babysit" Flutter activity

### excludeFromRecents > onTaskRemoved hack
- ป้องกัน user swipe ตั้งแต่ต้นทาง ดีกว่ารอ resurrect ทีหลัง
- ResurrectReceiver + AlarmManager เป็น safety net ในกรณีที่ task ยังถูก remove

### Pairing architecture
- เก็บ persistent `device_id` ที่กล้อง ไม่ขึ้นกับ pair code 6 หลัก (ที่หมดอายุใน 10 นาที)
- viewer pair ครั้งเดียวด้วยรหัส → server return device_id → save local
- ครั้งต่อๆ ไปใช้ device_id ตรงๆ join room ได้เลย

---

## สิ่งที่ไม่ได้ผล (What Didn't Work)

### ❌ `flutter_webrtc: ^0.11.7`
- ใช้ deprecated API `PluginRegistry.Registrar` ที่ถูกลบใน Flutter 3.41+
- → อัปเกรดเป็น 1.4.1

### ❌ ใช้ `stun:stun.l.google.com:19302`
- ทำให้ WebRTC ลอง DNS lookup + UDP → ช้า + ไม่จำเป็นสำหรับ LAN
- บน Android 16 ทำให้ crash บางครั้ง
- → ใช้ `iceServers: []` (host candidates เท่านั้น)

### ❌ Build บน Android 16 (API 36) Samsung A55 ตอนแรก
- ขาด `ACCESS_NETWORK_STATE` → libjingle SecurityException → SIGABRT บน `network_thread`
- Stack trace ใน `libjingle_peerconnection_so.so` ที่ไม่มี symbols ทำให้ debug ยาก
- ต้องดู `org.webrtc.NetworkMonitor` ใน logcat ก่อน crash จะเห็น `SecurityException: ConnectivityService`

### ❌ `service.startActivity()` ตรงๆ จาก `onTaskRemoved`
- Android 12+ บล็อก BAL silently — ไม่มี error แต่ activity ไม่ launch
- → ใช้ AlarmManager + BroadcastReceiver แทน

### ❌ ทดสอบ ResurrectReceiver ผ่าน `adb shell am broadcast`
- หลัง `am force-stop` Android จะ block broadcasts ทั้งหมดให้ app ที่ถูก force-stop
- ทดสอบ flow นี้ใน production จริงต้องสวิป Recent ด้วยมือ (ตอนนี้ป้องกันด้วย excludeFromRecents แทน)

### ❌ `adb shell am task remove <id>`
- ไม่มีคำสั่งนี้บน Android 16 — `cmd activity` ก็ไม่มี
- ทดสอบ swipe-away ตรงๆ ด้วย adb ไม่ได้

### ❌ `flutter_webrtc: 0.14.4`
- version นี้ไม่มีจริงบน pub.dev — เป็นเลขที่ผมคิดเอา
- → ตรวจ `curl https://pub.dev/api/packages/flutter_webrtc` ก่อน

---

## ขั้นตอนถัดไป (Next Steps)

### 🔥 งานที่ควรทำต่อ (Priority สูง)

1. **ทดสอบจริง: swipe จาก Recent บนเครื่อง Samsung A55**
   - หลังติดตั้ง APK ล่าสุด ลองเปิดแอป + กดเริ่มสตรีม
   - ดูว่า Recent Tasks มี CamConnect ไหม (ควรไม่มี เพราะ `excludeFromRecents="true"`)
   - ถ้ามี → debug ทำไม attribute ไม่ work; ถ้าไม่มี → ผ่าน ✅

2. **ตั้ง Battery Optimization บน Samsung A55**
   - Samsung เข้มงวด อาจฆ่า FGS แม้ใส่ permissions ครบ
   - ไปที่ Settings → Battery → CamConnect → ตั้งเป็น "ไม่จำกัด"
   - ทดสอบทิ้งไว้นานๆ (1-2 ชม.) ดูว่า service ยังรันไหม

3. **รวมเข้ากับ FamilyCare project**
   - User บอกว่าหลัง CamConnect เสร็จ จะรวมเข้ากับ FamilyCare ที่มี login
   - FamilyCare path: `B:\Users\thana\Desktop\ClaudeCode\FamilyCare`
   - FamilyCare มี Step 1-5 เสร็จ + Firebase + parent auth + device pairing
   - แนวทาง: นำ WebRTC logic + pairing flow จาก CamConnect ไปแทนที่ stub ใน FamilyCare

### 🟡 งานที่ควรพิจารณา (Priority กลาง)

4. **Network resilience**
   - ตอนนี้ถ้า WiFi เปลี่ยน → ทั้ง camera และ viewer ต้องเชื่อมต่อใหม่ด้วยตัวเอง
   - ควรเพิ่ม auto-reconnect logic ใน SignalingService (camera + viewer)
   - WebRTC ICE restart ถ้า connection state เปลี่ยนเป็น "disconnected"

5. **Multi-camera support**
   - ตอนนี้ viewer pair กับกล้องได้ทีละ 1 เครื่อง
   - ถ้าต้องการดูหลายกล้อง: เปลี่ยน `paired_device_id` เป็น `List<String>` + UI เลือก

6. **Security**
   - ตอนนี้ใครรู้ device_id ก็เข้าดูได้ → ใน production ต้องเพิ่ม auth token
   - JWT จาก server มอบให้ viewer หลัง pair → server validate ทุก join

### 🟢 Nice-to-have (Priority ต่ำ)

7. **NEARBY/QR pairing แทนรหัส 6 หลัก** — สแกน QR แทนพิมพ์รหัส
8. **Cloud signaling server** — รัน Railway/Fly.io แทน local LAN
9. **TURN server** — สำหรับเครือข่ายที่ NAT ซับซ้อน
10. **Two-way audio** — ตอนนี้ stream แค่ video, audio false; เปิด audio ได้

---

## ข้อมูลที่ต้องรู้ก่อนเริ่ม

### Tools / Environment
- Flutter 3.41.9 stable (Engine 9161402dc0)
- Android SDK platforms: 31, 35 (35 ต้องลงไว้ในเครื่องด้วย)
- Node.js: signaling server ใน `backend/signaling/` รันด้วย `npm run dev`
- Devices ที่ใช้ทดสอบ:
  - `R5CX40GY4TD` = Samsung Galaxy A55 (Android 16, API 36) — camera role
  - `emulator-5554` = LDPlayer (Android 9, API 28) — viewer role
  - Host LAN IP: `192.168.1.33`

### คำสั่งที่ใช้บ่อย

```bash
# Start signaling server (in backend/signaling/)
cd backend/signaling && npm run dev

# Build camera_app
cd apps/camera_app && flutter build apk --debug --no-pub

# Build viewer_app
cd apps/viewer_app && flutter build apk --debug --no-pub

# Install + grant permissions camera_app (Samsung A55)
adb -s R5CX40GY4TD install -r apps/camera_app/build/app/outputs/flutter-apk/app-debug.apk
adb -s R5CX40GY4TD shell pm grant com.camconnect.camera_app android.permission.CAMERA
adb -s R5CX40GY4TD shell pm grant com.camconnect.camera_app android.permission.RECORD_AUDIO
adb -s R5CX40GY4TD shell pm grant com.camconnect.camera_app android.permission.POST_NOTIFICATIONS

# Install viewer_app (LDPlayer)
adb -s emulator-5554 install -r apps/viewer_app/build/app/outputs/flutter-apk/app-debug.apk

# Verify FGS running
adb -s R5CX40GY4TD shell dumpsys activity services com.camconnect.camera_app | grep isForeground

# Read shared_preferences (camera_app's persistent state)
adb -s R5CX40GY4TD shell run-as com.camconnect.camera_app cat shared_prefs/FlutterSharedPreferences.xml
```

### โครงสร้างไฟล์สำคัญ

```
CamConnect/
├── backend/signaling/src/index.ts          # Socket.IO server + events
├── apps/camera_app/
│   ├── android/app/src/main/
│   │   ├── AndroidManifest.xml              # permissions + activity attrs + service + receivers
│   │   └── kotlin/com/camconnect/camera_app/
│   │       ├── MainActivity.kt              # MethodChannel + POST_NOTIFICATIONS perm
│   │       ├── CameraStreamingService.kt    # FGS + wake lock + onTaskRemoved
│   │       ├── BootReceiver.kt              # BOOT_COMPLETED → launch
│   │       └── ResurrectReceiver.kt         # broadcast → launch (BAL bypass)
│   └── lib/src/
│       ├── device_id.dart                   # persistent UUID
│       ├── streaming_prefs.dart             # auto_streaming flag
│       ├── foreground_service.dart          # MethodChannel wrapper
│       ├── signaling_service.dart           # Socket.IO client + registerCamera()
│       ├── home_screen.dart                 # auto-navigate + status UI
│       └── streaming_screen.dart            # camera + WebRTC + FGS start/stop
└── apps/viewer_app/lib/src/
    ├── pairing_storage.dart                 # paired_device_id storage
    ├── signaling_service.dart               # + pairViewer() method
    ├── home_screen.dart                     # pair flow
    └── live_view_screen.dart                # deviceId-based + unpair button
```

### Memory ที่บันทึกไว้ (อยู่ใน MEMORY ของ Claude)

- `flutter-webrtc-pitfalls.md` — เรื่อง permissions + LDPlayer network
- `familycare-project.md` — context ของ FamilyCare ที่จะรวมเข้าทีหลัง
- `feedback_debug-mode-skill.md` — แนวทาง debug

---

## วิธีเริ่มงานต่อใน session ใหม่

1. เปิด conversation ใหม่ใน Claude Code โดยให้ working dir = `B:\Users\thana\Desktop\ClaudeCode\CamConnect`
2. เริ่มข้อความแรก: "อ่าน HANDOFF.md แล้วทำต่อ" หรือบอกสิ่งที่อยากทำ
3. Agent จะมี context ครบ ทำงานต่อได้ทันที
