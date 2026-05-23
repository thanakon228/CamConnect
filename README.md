# CamConnect

ระบบดูกล้องระยะไกลผ่าน WebRTC ด้วยรหัสเชื่อมต่อ 6 หลัก — ไม่ต้องสมัครสมาชิก ไม่ต้องล็อกอิน

## วิธีใช้งาน

1. เปิด **camera_app** บนอุปกรณ์ที่ต้องการแชร์กล้อง → กด "สร้างรหัสเชื่อมต่อ"
2. เปิด **viewer_app** บนอุปกรณ์ที่ต้องการดู → ใส่รหัส 6 หลัก → กด "เชื่อมต่อ"
3. เห็นกล้องทันที

## โครงสร้าง

```
CamConnect/
├── apps/
│   ├── camera_app/    ← Flutter — สร้างรหัส + ส่งกล้อง
│   └── viewer_app/    ← Flutter — ใส่รหัส + ดูกล้อง
└── backend/
    └── signaling/     ← Node.js + Socket.IO
```

## Run ในเครื่อง

```bash
# 1. เริ่ม signaling server
cd backend/signaling
npm install
npm run dev

# 2. Build camera_app (A55 real device)
cd apps/camera_app
flutter run --dart-define=SIGNALING_URL=http://192.168.x.x:4001

# 3. Build viewer_app (LDPlayer emulator)
cd apps/viewer_app
flutter run --dart-define=SIGNALING_URL=http://10.0.2.2:4001
```
