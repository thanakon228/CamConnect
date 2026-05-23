# Plan: ตั้งครั้งเดียว แม่ดูได้ตลอด แม้กล้องปิดแอป

## เป้าหมายภาพรวม
ระบบ "set-and-forget" สำหรับครอบครัว:
1. **ฝั่งกล้อง (ลูก)**: เปิดสตรีมครั้งแรก → ปิดหน้าจอ/ปิดแอปได้ กล้องยังสตรีมอยู่ใน background
2. **ฝั่งแม่ (viewer)**: ใส่รหัสครั้งแรกครั้งเดียว → ครั้งต่อๆ ไปเปิดแอปก็เห็นกล้องเลย

ผลลัพธ์: แม่เปิดแอปดูได้ตลอดเวลา โดยที่ลูกไม่ต้องเปิดแอปกล้องเลย

---

## Phase A: One-time Pairing (viewer ไม่ต้องใส่รหัสซ้ำ)

### แนวคิด
- กล้องมี **persistent device_id (UUID)** ติดตัวเครื่อง
- รหัส 6 หลัก = แค่ "pair code" ชั่วคราว map ไป device_id
- viewer ใส่รหัส → ได้ device_id → save ใน SharedPreferences
- ครั้งต่อไปใช้ device_id ตรงๆ

### Backend (signaling server)
ไฟล์: `backend/signaling/src/index.ts`
- เพิ่ม Map `code → device_id` (TTL 10 นาที)
- เพิ่ม Map `device_id → cameraSocketId` (camera ที่ online)
- Event ใหม่:
  - `register-camera {device_id, code?}` — camera แจ้งตัวตน + เผยรหัสจับคู่ (ถ้ามี)
  - `pair-viewer {code}` → reply `{device_id}` หรือ error
  - `join {device_id}` — viewer เข้าห้องด้วย device_id

### Camera app
- NEW `lib/src/device_id.dart` — generate/load UUID จาก SharedPreferences
- MOD `pubspec.yaml` — เพิ่ม `shared_preferences`, `uuid`
- MOD `signaling_service.dart` — เพิ่ม `registerCamera(deviceId, code)`
- MOD `streaming_screen.dart` — ส่ง register-camera เมื่อ socket connect

### Viewer app
- NEW `lib/src/pairing_storage.dart` — get/set/clear `paired_device_id`
- MOD `pubspec.yaml` — เพิ่ม `shared_preferences`
- MOD `main.dart` — `FutureBuilder` ตรวจ paired_device_id ก่อน build first screen
- MOD `home_screen.dart` — ใส่รหัส → pair-viewer → save → navigate LiveView พร้อม deviceId
- MOD `live_view_screen.dart` — รับ `deviceId` แทน `code` + ปุ่ม "เลิกจับคู่"
- MOD `signaling_service.dart` — เพิ่ม `pairViewer(code)` + `joinByDeviceId(deviceId)`

---

## Phase B: Foreground Service (กล้องสตรีมได้ในขณะปิดแอป)

### แนวคิด
ใช้ Android native foreground service ประเภท `camera` + persistent notification — Android จะไม่ฆ่ากล้องและ network ของแอปแม้ user กด home/ปิดจอ

### Camera app native code
- NEW `android/.../CameraStreamingService.kt` — Foreground service ที่:
  - `startForeground(id, notification, FOREGROUND_SERVICE_TYPE_CAMERA)`
  - acquire `PARTIAL_WAKE_LOCK`
  - notification "กำลังสตรีมกล้อง" + ปุ่ม Stop
  - ไม่ได้แตะกล้องเอง — แค่บอก Android ว่าแอปนี้สำคัญ
- MOD `android/.../MainActivity.kt` — MethodChannel `startCameraService` / `stopCameraService` + ขอ POST_NOTIFICATIONS
- MOD `AndroidManifest.xml` — เพิ่ม:
  - `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CAMERA`, `POST_NOTIFICATIONS`, `WAKE_LOCK`
  - declare `<service android:foregroundServiceType="camera" .../>`

### Camera app Dart code
- NEW `lib/src/foreground_service.dart` — Dart wrapper เรียก MethodChannel
- MOD `streaming_screen.dart`:
  - `initState()` หลัง getUserMedia สำเร็จ → call `startCameraService()`
  - `dispose()` → call `stopCameraService()`
- (Optional) MOD `main.dart` — เริ่ม streaming อัตโนมัติเมื่อมี device_id แล้ว (เปิดแอปครั้งแรกตั้งค่า → ครั้งต่อๆ ไปสตรีมทันที)

---

## ขั้นตอนการทำงาน (เรียงตามลำดับ)

### Phase A (40 นาที)
1. แก้ backend index.ts — Maps + 3 events ใหม่
2. สร้าง device_id.dart (camera)
3. แก้ signaling_service ทั้งสองฝั่ง รองรับ events ใหม่
4. แก้ streaming_screen — ส่ง register-camera
5. สร้าง pairing_storage.dart (viewer)
6. แก้ main.dart (viewer) — auto-route
7. แก้ home_screen (viewer) — pair-viewer flow
8. แก้ live_view_screen — รับ deviceId + ปุ่มเลิกจับคู่
9. Build + install + test ผ่าน A55 (camera) + LDPlayer (viewer)

### Phase B (30 นาที)
10. แก้ AndroidManifest — permissions + service
11. เขียน CameraStreamingService.kt
12. แก้ MainActivity.kt — MethodChannel + runtime perm
13. สร้าง foreground_service.dart
14. แก้ streaming_screen — start/stop service
15. Build + install + test: เปิดสตรีม → กด home → viewer ยังเห็นภาพ → กลับมาเปิด viewer ใหม่ก็ยังเห็น

### Phase C — Test integration (15 นาที)
16. Reset ทั้งสองเครื่อง
17. Camera: เปิดแอป → start stream → ปิดจอ
18. Viewer: เปิดแอป → ใส่รหัสครั้งเดียว → เห็นภาพ → ปิดแอป → เปิดใหม่ → เห็นภาพทันที (ไม่ต้องใส่รหัส)
19. ปิดจอ camera นาน 5 นาที → viewer ยังเห็นภาพ

---

## ความเสี่ยง / ข้อควรระวัง

**Phase A:**
- Camera ต้องค้างที่ signaling server แม้ยังไม่มี viewer — server ต้อง track `device_id → socket` (ทำใน plan แล้ว)
- Race condition: viewer pair มาก่อน camera online → viewer ต้อง retry/wait

**Phase B:**
- **Android 14+ FOREGROUND_SERVICE_CAMERA**: ถ้าขาด → SecurityException ตอน startForeground
- **POST_NOTIFICATIONS runtime perm** (Android 13+): ถ้า user deny → notification ไม่แสดงแต่ service ยังรัน
- **Doze mode**: ปิดจอนานๆ Android อาจ throttle network → ต้อง wake lock + ทดสอบจริง
- **Battery optimization**: บางเครื่องต้องให้ user ปิด battery optimization manual ถึงจะรันได้ยาวๆ (Samsung เป็นเครื่องที่เข้มงวด)
- **Camera lifecycle**: Flutter อาจ release camera ตอน activity pause → ต้องทดสอบ ถ้าจำเป็นต้อง prevent

**ทั่วไป:**
- Storage หาย/ถูกลบ → device_id เปลี่ยน → ต้อง re-pair (ไม่ critical แค่ UX)

## เวลาโดยประมาณ
ทั้งหมด 90-120 นาที (Phase A 40 + Phase B 30 + Test 15-30 + buffer)

---
รอ confirm — พิมพ์ "เริ่มเลย" / "OK" / "ทำเลย"
ถ้าอยากทำทีละ phase ก็ได้: "เริ่ม phase A" / "เริ่ม phase B"
