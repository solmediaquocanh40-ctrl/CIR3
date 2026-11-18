# CircleSwitcher v2.2.7 — Kính thật (Metal) + sửa lỗi bóng vàng cam + sửa lag khi chạm

Bản gộp theo kế hoạch anh duyệt 23:37 2026-11-18: kính thật cho chế độ overlay 0–3, sửa lỗi lớp màu ở cổ điển, sửa khựng/lag. Mới kiểm tra tĩnh — CHƯA Theos build, CHƯA test máy thật.

## 1. Kính thật cho overlay 0–3 (mới)

- Đưa shader kính của LiquidGlassKit (bộ code 3 anh gửi) vào tweak: SDF đa hình (tối đa 16 khối), khúc xạ Snell bẻ cong hình nền thật, tán sắc cầu vồng ở mép, viền sáng Fresnel + loé glare. Chỉnh sửa so với bản gốc: bán kính bo góc riêng cho từng khối (orb to nhỏ khác nhau), bỏ các hàm chết.
- Shader nhúng dạng source (`CSGlassShader.h`, sinh từ `LiquidGlassCS.metal`) và **biên dịch ngay trên máy ở lần mở đầu** rồi cache — vì build trên Ubuntu không có trình biên dịch Metal. Engine được hâm nóng sẵn từ lúc SpringBoard nạp tweak. Lỗi ở bất kỳ khâu nào (không có Metal, biên dịch lỗi, chụp nền lỗi) → **tự lùi về kính mờ cũ**, không crash, không đen màn hình.
- Nền phía sau sân khấu được chụp **một lần mỗi lần mở** bằng CABackdropLayer vào IOSurface (cầu nối zero-copy viết lại bằng ObjC) + một lượt làm mờ MPS — khác bản gốc chụp lại mỗi frame và chờ GPU trên main thread. Lúc vuốt nền đứng yên nên không cần chụp lại; mỗi frame chỉ cập nhật toạ độ các khối kính (uniforms) — gần như miễn phí.
- **Một view Metal duy nhất** vẽ toàn bộ kính của sân khấu trong một pass, thay cho N lớp blur sống (mỗi item một UIVisualEffectView) — nghi phạm chính gây khựng khi vuốt. Khi kính thật chạy: thân item trong suốt (icon/chữ/viền giữ nguyên), lớp blur và lớp ambient của item được ẩn. Pill tiêu đề và nút ✕ cũng vào cùng một pass kính cho đồng bộ (nền của chúng chuyển trong suốt, hoàn nguyên khi kính tắt).
- Ba slider kính trong Cài đặt nay lái thông số thật: glassRefract → chỉ số khúc xạ + độ dày kính; glassSpecular → độ loé/Fresnel; glassDispersion → độ tán sắc.
- **Morph mở switcher bằng shader**: khối kính của app chính giữa bắt đầu là một "màn hình" bo góc lớn rồi kéo 4 góc thu về đúng khung nghỉ — chỉ đổi uniforms, không resize view nào mỗi frame như morph cũ (thủ phạm giật). Blur theo tốc độ chạy trên lớp veil cố định của sân khấu (chỉ đổi alpha). Khi kính không khả dụng, morph cũ vẫn là fallback.
- **Mở app bằng kính phình**: khối kính của app chính giữa phình ra phủ màn hình trong lúc sân khấu fade dài hơn một chút (0,32s), mắt bám vào một vật thể liên tục thay vì fade chạy lệch nhịp với animation phóng app của hệ thống. Animation mở app vẫn là của SpringBoard — bản này che mối nối tốt hơn chứ không chiếm được 100%.
- Phạm vi: chỉ overlay 0–3. Cổ điển 4–9 là thẻ của SpringBoard, không áp kính này. Xem trước trong Cài đặt giữ nguyên kính mờ.

## 2. Sửa lỗi lớp vàng cam ở cổ điển

- Bỏ hẳn bóng phát sáng (layer.shadow màu glow, radius 18, offset (0,6), shadowPath phẳng không xoay) trên container của thẻ cổ điển — chính nó vẽ đè vệt sữa ấm lên app phía sau trong ảnh test 2.2.6. Phát sáng ở cổ điển giờ chỉ còn viền 2pt trên chính layer của thẻ (bị clip trong khung thẻ, không tràn sang app bên cạnh được).

## 3. Sửa lag khi chạm vùng trống về Home

- Không đóng băng sân khấu ngay khi chạm nữa: vòng xoay giữ nguyên chuyển động + physics cho tới khi transition thoát thật sự bắt đầu; cờ dismissPending chặn các cú chạm tiếp theo trong lúc chờ để không đua với lệnh thoát. Lệnh Home trượt (mọi selector đều miss) → dỡ cờ, trả sân khấu tương tác đầy đủ như cũ (vẫn tuyệt đối không lộ switcher gốc — giữ nguyên sửa 2.2.6). Watchdog 0,8s cũng dỡ cờ khi khôi phục.

## Hạ tầng

- Makefile: thêm framework Metal, MetalKit, MetalPerformanceShaders, CoreVideo (chỉ tweak chính; bundle Cài đặt không đổi).
- Version 2.2.6 → 2.2.7 đồng bộ mọi nơi: control, Info.plist (×2), footer Root.plist/Root_EN.plist, EasterEgg, LogoCell, RootListController (nút ẩn + nút share), build.yml + tên artifact, README, header Tweak.x.

## Cần anh kiểm chứng trên máy (video 60fps, 4 thao tác)

1. Mở CircleSwitcher ở chế độ 0–3: orb có thành kính thật (thấy nền bị bẻ cong qua orb, mép có tán sắc) không; vuốt qua lại có nhẹ hơn không.
2. Đoạn morph lúc mở + đoạn mở app: còn giật không.
3. Ấn vùng trống về Home: còn cảm giác lag không.
4. Chế độ cổ điển: vệt vàng cam trên app phía sau còn không.
Nếu kính không lên (vẫn kính mờ cũ), cho em biết để em rà đường fallback — và nếu tiện, gửi em cả 4 thao tác trên cùng một video.
