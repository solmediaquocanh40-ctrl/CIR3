# CircleSwitcher v2.2.5 — Đưa ý tưởng video demo vào tweak (theo lệnh của anh, 22:20 2026-11-18)

## 1. ENTRANCE MORPH — mở switcher theo đúng video demo anh duyệt
- Khi mở CircleSwitcher (chế độ vòng xoay 0–3), app ở giữa không còn "hiện pop" nữa: nó bắt đầu là một khung bo góc lớn như màn hình app, rồi **thu nhỏ dần, 4 góc kéo vào trong** (bán kính bo tăng dần tới đúng bo góc của item đích — hình tròn ở các chế độ orb), **kèm motion blur theo tốc độ**: nét ở đầu, mờ nhất giữa quãng, nét lại khi đáp xuống.
- Điểm đáp của morph là khung nghỉ thật của item ở giữa (layout ghi lại mỗi lần vẽ), nên morph nối liền mạch vào vòng xoay, không có điểm cắt.
- Vòng xoay thật hiện dần bên dưới ở cuối morph. Chạm vào màn hình giữa chừng thì morph kết thúc ngay, không cản thao tác.
- Chạy trên chính animation mở của hệ thống (không animation chồng animation) — đây là phần trị cái "giật 1 cái" khi vuốt mở.
- Nội dung trong khung morph là icon app phóng lớn trên kính mờ (overlay không lấy được hình ảnh trực tiếp của app đang chạy — xem mức % trong tin nhắn bàn giao).

## 2. MOTION BLUR KHI VUỐT VÒNG XOAY
- Một lớp mờ duy nhất phủ sân khấu, độ mờ chạy theo tốc độ vuốt: vuốt càng nhanh càng mờ (che được các bước khung hình gây cảm giác giật), dừng lại là tan hết, icon nét như cũ. Chỉ 1 view phụ, gần như không tốn hiệu năng.
- Cả hai hiệu ứng dùng chung công tắc Motion Blur sẵn có trong Cài đặt (đang bật mặc định) — tắt Motion Blur là tắt cả hai, không thêm key chết.

## 3. Giữ nguyên từ 2.2.4
- Đế hologram đã xoá hẳn; viền xanh chỉ ở app chính giữa; lỗi ấn màn hình ra switcher gốc giữ kỷ luật tháo-lớp-phủ ở cuối transition. Toàn bộ chức năng khác giữ nguyên.
- Version 2.2.4 → 2.2.5 đồng bộ mọi nơi. Kiểm tra: cuối trang Cài đặt phải hiện v2.2.5.
