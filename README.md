# Mothership — Roblox (Rojo)

Game top-down multiplayer-strategy lấy cảm hứng từ Lordz.io. Bạn lái **Tàu Mẹ**,
hạm đội bay quanh theo quỹ đạo và tự bắn; khai thác scrap để snowball kinh tế.
Tàu Mẹ chết = cả hạm đội chết → fleet **chắn thân** bảo vệ Tàu Mẹ.

> **Phase 0 hoàn thành** (1 ván trọn: lái, fleet, combat, Split, economy, 2 bot, win/lose).
> Đang xây tiếp: **Lobby 3D**, **UX/UI**, và **full combat 9-unit** (đang ở Bước 0).
> Kiến trúc **server-authoritative**, **data-driven** (mọi số nằm trong `Config.luau`).

---

## 1. Cài công cụ (làm 1 lần / mỗi máy)

1. **Rojo CLI** (đồng bộ file → Studio):
   - Tải `rojo.exe` (v7.7.0) từ trang **GitHub Releases của rojo-rbx/rojo**
     (`rojo-<ver>-windows-x86_64.zip`), giải nén, bỏ vào 1 thư mục có trong `PATH`.
   - Kiểm tra: `rojo --version`
2. **Plugin Rojo cho Studio**: Studio → **Plugins → Manage Plugins → tìm "Rojo"** và cài
   (hoặc chạy `rojo plugin install`).

## 2. Chạy & kết nối (mỗi lần dev)

Trong thư mục `mothership/` (chỗ có `default.project.json`):

```bash
rojo serve
```

Rojo in ra `localhost:34872`. Trong Studio: mở 1 place trống (Baseplate cũng được —
script tự dựng map/lobby) → bấm **Rojo** trên thanh Plugins → **Connect**. Cây `src/`
sync vào Studio. Bấm **Play** (F5) để test.

> Nếu server Rojo tự tắt giữa chừng (bug watcher trên Windows khi ghi file), chỉ cần
> chạy lại `rojo serve` và **Connect** lại trong Studio.

---

## 3. Đồng bộ nhiều máy (Git + GitHub)

Nguồn sự thật là các file trong `src/` — **không phải** file place `.rbxl`. Toàn bộ map,
lobby, HUD đều do **script tự dựng**, nên chỉ cần đồng bộ code là ra y hệt trên máy khác.

Remote: `https://github.com/linhntt9/mothership.git`

**Máy mới — lần đầu:**
```bash
git clone https://github.com/linhntt9/mothership.git
cd mothership
rojo serve
```
(nhớ cài `rojo.exe` trước nếu máy đó chưa có — xem mục 1)

**Máy đã clone — cập nhật bản mới nhất:**
```bash
cd mothership && git pull && rojo serve
```

**Sau khi làm xong — lưu lên GitHub:**
```bash
cd mothership && git add -A && git commit -m "mô tả thay đổi" && git push
```

> ⚠️ Thứ dựng **bằng tay trong Studio** (không qua script) nằm trong `.rbxl` và **không**
> theo Git. Dự án hiện dựng mọi thứ bằng code nên không cần lo; nếu sau này có, hãy
> publish place lên Roblox để mở lại ở máy khác.

> ⚠️ Để bảng ⚙ (dev config) lưu được số đã chỉnh: Studio → **Game Settings → Security →
> Enable Studio Access to API Services** (bật DataStore trong Studio).

---

## 4. Điều khiển

**Lobby (sảnh 3D):** `WASD` lái Tàu Mẹ · **lăn chuột** zoom · **giữ chuột phải + rê**
xoay camera · lái vào cổng **Class/Skin** để mở shop · lái vào cổng **VÀO TRẬN** để bắt đầu.

**Trong trận:** **di chuột** lái Tàu Mẹ · `1-4` mua quân · `Q` Mine (trên mỏ) · `R` Hub ·
click map để đặt · `Space` Split · nút **⌂ Lobby** (góc trên-trái) để về sảnh.

Bảng **⚙** (góc trên-trái, hoặc phím `~`): chỉnh mọi số Config lúc chạy + Chơi lại + Tạo bot.

---

## 5. Cấu trúc thư mục

```
mothership/
├── default.project.json              # cấu hình Rojo (cây file -> Studio)
├── README.md
└── src/
    ├── ReplicatedStorage/
    │   ├── Config.luau               # TẤT CẢ balance numbers (map, units, lobby, ...)
    │   ├── Remotes.luau              # RemoteEvents
    │   └── Util.luau                 # math helpers
    ├── ServerScriptService/
    │   ├── Main.server.luau          # bootstrap + vòng đời trận (lobby<->playing)
    │   ├── MatchState.luau           # trạng thái trận (LOBBY | PLAYING)
    │   ├── GameState.luau            # bảng trạng thái trung tâm
    │   ├── MapSystem.luau            # arena: baseplate + mỏ quặng
    │   ├── LobbySystem.luau          # sảnh 3D + 3 cổng shop
    │   ├── MothershipSystem.luau     # spawn + di chuyển Tàu Mẹ + nameplate
    │   ├── FleetSystem.luau          # đội hình 3 vòng (SCREEN/GUARD/CORE) + Split
    │   ├── CombatSystem.luau         # combat hitscan + chắn thân + bảng kết thúc
    │   ├── EconomySystem.luau        # scrap / income / mua quân
    │   ├── BuildingSystem.luau       # Scrap Mine + Drone Hub
    │   ├── PickupSystem.luau         # scrap rải đều (jittered grid)
    │   └── BotSystem.luau            # bot AI + leaderboard
    └── StarterPlayer/StarterPlayerScripts/
        ├── CameraController.client.luau  # camera trận (top-down) + lobby (orbit)
        ├── InputController.client.luau   # input: chuột (trận) / WASD (lobby)
        ├── HUD.client.luau               # HUD trong trận + bảng kết thúc
        ├── Lobby.client.luau             # UI lobby + phát hiện vùng cổng
        ├── Minimap.client.luau           # minimap
        ├── ConfigPanel.client.luau       # bảng ⚙ dev-tune
        ├── CombatVFX.client.luau         # tia laser
        └── ClientBus.luau                # event bus nội bộ client
```

> **Server-authoritative:** mọi simulation chạy trên server; client chỉ lo camera, input, UI.
> **Data-driven:** thêm unit/building = thêm entry vào bảng `Config`.
