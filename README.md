# Mothership — Prototype (Roblox)

Game top-down multiplayer-strategy lấy cảm hứng từ Lordz.io. Bạn lái **Tàu Mẹ**,
hạm đội bay quanh theo quỹ đạo và tự bắn; khai thác thiên thạch để snowball kinh tế.

> Prototype build theo milestone. **Mỗi milestone phải Play được trong Studio.**
> Hiện đang ở: **M0 — Scaffold + Drive**.

---

## 1. Cài đặt công cụ (làm 1 lần)

1. Cài **Rojo** (CLI):
   - Cách nhanh (Aftman): `aftman add rojo-rbx/rojo` rồi `aftman install`.
   - Hoặc tải bản binary từ trang release của Rojo và thêm vào PATH.
   - Kiểm tra: `rojo --version`
2. Cài **plugin Rojo cho Studio**: trong Studio → **Plugins → Manage Plugins → tìm "Rojo"** và cài (hoặc `rojo plugin install`).

## 2. Chạy Rojo (mỗi lần dev)

Từ terminal, đứng trong thư mục `mothership/` (chỗ có file `default.project.json`):

```bash
rojo serve
```

Rojo sẽ in ra địa chỉ dạng `localhost:34872`.

## 3. Kết nối trong Studio

1. Mở một **place mới** (Baseplate cũng được — script sẽ tự tạo map riêng).
2. Bấm nút **Rojo** trên thanh Plugins → **Connect** (địa chỉ mặc định khớp với `rojo serve`).
3. Cây file trong `src/` sẽ sync vào Studio.

## 4. Test

Bấm **Play** (F5) hoặc **Play Solo**. Xem mục 5 để biết mỗi milestone cần kiểm gì.

---

## 5. Checklist test theo milestone

### M0 — Scaffold + Drive ✅ (milestone hiện tại)
- [ ] Bấm Play → thấy **camera top-down** nhìn xuống map 500x500 tối màu.
- [ ] Có **~30 asteroid** gom thành vài cụm rải trên map.
- [ ] Có **1 khối cầu neon** (Tàu Mẹ) ở góc dưới-trái.
- [ ] **Di chuột** → Tàu Mẹ lái mượt về phía con trỏ, không giật/teleport.
- [ ] Tàu Mẹ **không ra khỏi biên** map.
- [ ] **Output không có lỗi đỏ.**

### M1 — Fleet + Formation (chưa làm)
- Thêm quân → lấp đầy vòng quỹ đạo, bay mượt quanh Tàu Mẹ.

### M2 — Combat (chưa làm)
- Lái fleet vào 1 enemy dummy → 2 bên bắn nhau, có bên chết.

### M3 — Split (chưa làm)
- Giữ `Space` tách 2 cánh né/kẹp địch; thả ra gộp lại.

### M4 — Economy + Buildings + HUD (chưa làm)
- Khai thác → mua quân, hotbar + counters đầy đủ.

### M5 — Bots (chưa làm)
- 1 ván hoàn chỉnh: 2 bot bành trướng & đánh nhau, thắng/thua + restart.

---

## 6. Cấu trúc thư mục

```
mothership/
├── default.project.json          # cấu hình Rojo (map file -> Studio)
├── README.md
└── src/
    ├── ReplicatedStorage/
    │   ├── Config.luau           # TẤT CẢ balance numbers
    │   ├── Remotes.luau          # RemoteEvents
    │   └── Util.luau             # math helpers
    ├── ServerScriptService/
    │   ├── Main.server.luau      # bootstrap
    │   ├── MapSystem.luau        # baseplate + asteroids
    │   ├── MothershipSystem.luau # spawn + move mothership
    │   └── GameState.luau        # bảng trạng thái trung tâm
    └── StarterPlayer/StarterPlayerScripts/
        ├── CameraController.client.luau
        └── InputController.client.luau
```

> Kiến trúc **server-authoritative**: toàn bộ simulation chạy trên server;
> client chỉ lo camera, input và (sau này) UI.
