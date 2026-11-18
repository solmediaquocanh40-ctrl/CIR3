# CircleSwitcher v2.2.8 — Bản an toàn: sửa thoát switcher, vòng xám, cổ điển, slider độ nghiêng

Theo cách tách anh duyệt 00:16 2026-11-19: bản này chỉ gồm 4 mục rủi ro thấp. Phần đồng bộ animation in/out theo transition hệ thống để riêng sang 2.2.9. Mới kiểm tra tĩnh (cân bằng ngoặc khớp, cả hai file plist đều đọc được và có slider mới) — CHƯA Theos build, CHƯA test máy thật.

## 1. Chạm vùng trống không thoát được switcher (lỗi hồi quy của 2.2.7) — sửa

- Quay về **đúng ngữ nghĩa thoát của 2.2.6** — bản cuối cùng anh xác nhận chạm là thoát được: đánh dấu đã đóng, đóng băng sân khấu, cắt tương tác, rồi mới gửi lệnh Home; teardown vẫn do transitionDidEnd phụ trách. Thử nghiệm của 2.2.7 (giữ sân khấu sống + tương tác + physics trong lúc gửi lệnh) bị gỡ bỏ hoàn toàn.
- Cảm giác lag "đóng băng" được xử lý mà không đụng vào cơ chế thoát: khi chạm, nội dung vòng xoay **nhún nhẹ 0,99 trong 0,1s** để báo đã nhận chạm (transform được reset ở lần mở kế tiếp và khi watchdog khôi phục).
- Watchdog thoát được viết lại cho coherent với ngữ nghĩa mới: nó lấy **việc sân khấu còn hiện trên màn hình** làm sự thật gốc (bản 2.2.7 keyed theo gSwitcherSettledOpen nên với cách dismiss này nó sẽ không bao giờ kích hoạt). Nếu sau 0,8s lệnh thoát bị nuốt (không transition nào bắt đầu), watchdog **tự thử lại một lần bằng đường toggle của coordinator**, chờ thêm 0,8s nữa rồi mới trả sân khấu lại tương tác đầy đủ. Đường mở app dùng chung watchdog nhưng không thử lại bằng toggle.

## 2. Vòng xám bao quanh app ở chế độ kính — sửa

- Thủ phạm là ảnh nền ambient của tweak (hình vòng oval đồng tâm) nằm sau sân khấu: thân item đục trước đây che nó, item kính trong suốt thì nó lộ thành vòng xám. Khi kính thật đang sống, lớp nền này **bị ẩn hẳn** (kính không cần tranh nền phía sau). Khi kính tắt (fallback kính mờ), nó trở lại theo công tắc Backdrop như cũ.

## 3. Cổ điển: app trước che app sau — giảm

- **Viền chỉ còn ở thẻ trước**: trước đây mọi thẻ cổ điển đều đeo viền xanh 2pt. Nay độ đậm viền tính theo khoảng cách tới tâm (cùng công thức với transform của thẻ): thẻ trước viền đủ, càng xa càng mờ dần về 0 — hết cảnh viền chồng viền.
- **Thẻ sau bớt tối**: sàn độ mờ nâng từ 0,50 lên 0,68 và dốc fade gentler — thẻ sau đọc như thẻ thật thay vì bóng ma.
- **Thẻ trước nhỏ lại tối đa 6%** (hệ số ×0,94 ở chính giữa, easing mượt theo khoảng cách nên không giật khi cuộn) — trực tiếp giảm phần nó che lên thẻ sau.
- (Nhắc lại: bóng phát sáng tràn sang thẻ bên đã bỏ từ 2.2.7 và giữ nguyên.)

## 4. Slider "Độ nghiêng icon" (mới)

- Thêm slider trong Cài đặt (ngay dưới "Độ cong vòng xoay 3D"): khoảng 0,00–1,50, mặc định 1,00 = như hiện tại. Kéo về 0 là icon đứng thẳng hoàn toàn; kéo lên 1,50 là nghiêng hơn hiện tại 1,5 lần.
- Áp cho chế độ overlay 0, 1, 2 (chế độ 3 vòng tròn vốn không nghiêng; cổ điển giữ góc riêng theo từng chế độ). Preview trong Cài đặt cũng áp cùng hệ số để hai bên khớp nhau.
- Hạ tầng: pref mới `tiltAmount` (đọc trong CSLoadPreferences của tweak + loader của preview), mục slider thêm vào Root.plist và Root_EN.plist ("Độ nghiêng icon" / "Icon Tilt").

## Version

2.2.7 → 2.2.8 đồng bộ mọi nơi: control, Info.plist (×2), footer Root.plist/Root_EN.plist, EasterEgg, LogoCell, RootListController, build.yml + tên artifact, README, header Tweak.x.

## Cần anh kiểm chứng trên máy

1. Chạm vùng trống: thoát về Home được như 2.2.6 không, cảm giác nhún nhẹ có đỡ lag không.
2. Chế độ kính (0–3): vòng xám còn không.
3. Cổ điển: viền chỉ ở thẻ trước chưa, thẻ sau có sáng rõ hơn và bị che ít hơn không.
4. Slider Độ nghiêng: kéo về 0 xem icon có đứng thẳng, preview có khớp với thật không.
