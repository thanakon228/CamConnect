# Device Owner Setup — Anti-Force-Stop

> ทำให้ camera_app **ไม่สามารถถูก Force Stop หรือ Uninstall** ได้
> สำหรับ "เครื่องลูกที่ใช้ดูเด็กแบบ dedicated"

มี 2 ระดับสิทธิ์ — เลือกตามความต้องการ

---

## 🔒 ระดับ A — Device Admin (ง่าย ทุกเครื่องทำได้)

**ป้องกัน:**
- ✅ ลบ app (Uninstall greyed out)
- ❌ Force Stop **ยังกดได้**

**วิธีตั้ง:**
1. เปิดแอป Settings ในเครื่องลูก
2. ค้นหา **"Device admin apps"** หรือ **"แอปผู้ดูแลอุปกรณ์"**
   (Settings → Security → More security settings → Device admin apps)
3. หา **CamConnect — กล้อง** → กดเปิด toggle
4. กด **"Activate"** ในป๊อปอัพ

**ผล:** เมื่อกด Uninstall — ระบบจะบอก "ต้องปิด Device admin ก่อน" → child ทั่วไปทำไม่เป็น

**ถอน:** Settings → Device admin apps → toggle off → uninstall

---

## 🔐 ระดับ B — Device Owner (เต็มระดับ MDM)

**ป้องกัน:**
- ✅ ลบ app
- ✅ **Force Stop ปุ่ม disabled**
- ✅ Clear data ก็ไม่ได้

**ข้อจำกัด:**
- ⚠️ ต้องตั้ง **ตอนเครื่องอยู่ในสภาพ "ใหม่"** (no Google account)
- ⚠️ ถ้ามี account แล้ว → **ต้อง factory reset ก่อน**
- ⚠️ ครั้งเดียวต่อเครื่อง

### ขั้นตอน Setup (one-time):

**Step 1: เตรียมเครื่อง**
- Factory reset เครื่องลูก (Settings → General management → Reset → Factory data reset)
- **อย่า** sign in Google account ใดๆ ตอน setup wizard
- **อย่า** เพิ่ม Samsung account
- ข้าม restore from backup
- เครื่องอยู่ในสถานะ "fresh" + ไม่มี user เพิ่มเติม

**Step 2: เปิด USB Debugging**
- Settings → About → Build number — กด 7 ครั้ง (Developer mode)
- Settings → Developer options → USB debugging ON

**Step 3: ติดตั้งและตั้ง Device Owner**
```bash
# เสียบ phone กับ PC
adb devices  # ควรเจอ device

# ติดตั้ง APK
adb install camera_app/build/app/outputs/flutter-apk/app-debug.apk

# ตั้งเป็น Device Owner — คำสั่งสำคัญ
adb shell dpm set-device-owner com.camconnect.camera_app/.CamConnectDeviceAdminReceiver

# Expected output:
# Success: Active admin set to component {com.camconnect.camera_app/.CamConnectDeviceAdminReceiver}
```

**Step 4: เปิดแอปครั้งแรก**
- เปิด CamConnect → กดเริ่มสตรีม → จับคู่กับเครื่องแม่
- จากนี้ไป ปุ่ม Force Stop และ Uninstall ใน Settings จะ disabled

### วิธีถอด Device Owner (ถ้าต้องการ):
```bash
adb shell dpm remove-active-admin com.camconnect.camera_app/.CamConnectDeviceAdminReceiver
# หรือ factory reset (ทุกอย่างหายหมด)
```

---

## 🆘 Troubleshooting

### `dpm set-device-owner` ขึ้น `Not allowed to set the device owner because there are already several users on the device`
- แปลว่ามี Google account หรือ secondary user อยู่
- ต้อง factory reset ใหม่ + ข้ามทุก account ในตอน wizard
- หรือยอมรับใช้แค่ระดับ A (Device Admin)

### `dpm set-device-owner` ขึ้น `Trying to set the device owner, but device owner is already set`
- ตั้งแล้ว — เปิด Settings ตรวจปุ่ม Force Stop จริง

### Samsung Knox block
- บางรุ่น Samsung ต้อง disable Knox ก่อน
- Settings → Biometrics and security → Other security settings → ปิด Knox

### App หาย / corrupted หลังตั้ง
- adb เข้าได้เสมอ → remove device owner → uninstall → reinstall
- ถ้า adb เข้าไม่ได้ → factory reset

---

## 💡 คำแนะนำเลือกระดับ

| สถานการณ์ | แนะนำ |
|---|---|
| เด็กเล็ก 3 ขวบ ไม่รู้จัก Settings | **ระดับ A** (Device Admin) — เพียงพอ |
| เด็กโต / รู้จัก Force Stop | **ระดับ B** (Device Owner) — เครื่อง fresh |
| แค่ทดสอบ ไม่อยากเสี่ยง factory reset | **ระดับ A** |
| ต้องการ 100% anti-tampering | **ระดับ B** |

ส่วนใหญ่ **ระดับ A พอ** — เด็ก 3 ขวบไม่มีทาง force stop เป็น
