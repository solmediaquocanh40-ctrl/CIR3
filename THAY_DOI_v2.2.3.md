# CircleSwitcher v2.2.3 — Sửa dứt điểm lỗi #1 + viền chồng (một bản gộp, theo yêu cầu của anh)

## Lỗi quan trọng nhất: ấn vào màn hình thì thoát ra switcher gốc — ĐÃ TÌM RA THỦ PHẠM THẬT
- Ở bản 2.2.2 em sửa đúng ở handler chạm (gửi lệnh home trước), NHƯNG còn một đường code khác phá nó trong cùng khoảnh khắc: hook `transitionDidBegin` của view controller — mỗi khi bắt đầu THOÁT switcher (về Home hoặc vào app), nó tháo lớp phủ và khôi phục view gốc NGAY LẬP TỨC. Nghĩa là trong toàn bộ animation thoát (~0.3–0.5s), màn hình hiện switcher gốc. Anh ấn → CircleSwitcher biến mất → switcher gốc hiện ra. Đúng triệu chứng anh mô tả, và đó là lỗi của em khi rà soát thiếu đường code này.
- Nay: **không còn bất kỳ tháo dỡ nào ở thời điểm bắt đầu thoát nữa** (cả hook VC lẫn hook coordinator dự phòng). Lớp phủ giữ nguyên trên cùng trong suốt animation thoát; việc tháo dỡ chỉ diễn ra ở `transitionDidEnd` — khi switcher đã ra khỏi màn hình, không ai thấy được nữa. Áp dụng cho cả 3 đường thoát: ấn khoảng trống về Home, ấn vào app, vuốt về Home.
- Bỏ bộ đếm 0.30s của 2.2.2 trong hàm về Home (nó còn có thể bắn nhầm sau khi mở lại nhanh, giết nhầm lớp phủ mới). Thay bằng watchdog 0.8s: nếu lệnh thoát bị hệ thống nuốt mất (không có transition nào chạy), lớp phủ được mở khóa tương tác lại thay vì đơ màn hình.
- Mở app (`_cs_activateAppLayout`) cũng bỏ khôi phục view gốc giữa chừng — cùng một nguyên tắc: teardown chỉ ở DidEnd.

## Viền xanh chồng nhau / glass không vừa khung / che icon phía sau
- Tắt hẳn lớp rim PNG trên MỌI item: nét vẽ của ảnh rim thụt vào trong canvas nên nó luôn vẽ thêm một khung thứ hai lệch vào trong so với viền layer — đây là "viền chồng + glass không vừa khung". Nay mỗi item chỉ còn đúng MỘT khung: viền layer, cùng hình dạng với phần kính bị cắt theo nó. (Slider glass vẫn điều khiển màu/phổ viền, halo và độ mờ nền như cũ.)
- Chế độ 2 (Khung Tròn): orb bên cạnh thu nhỏ nhanh hơn khi rời tâm (hàm mũ 2.2 → 3.0), orb giữa bị giới hạn chặt hơn theo khoảng cách khe (hệ số 1.55 → 1.30), bán kính quỹ đạo nới 0.44 → 0.46 bề ngang — giảm hẳn cảnh orb giữa nuốt icon phía sau.
- Giảm khựng khi vuốt: màu viền trước đây được tạo mới cho từng icon ở từng khung hình kéo — nay tính một lần cho cả lượt layout; màu nền icon chỉ gán lại khi độ đặc thật sự thay đổi.

## Giữ nguyên toàn bộ chức năng cũ. Version 2.2.2 → 2.2.3 đồng bộ mọi nơi.

## Cách anh kiểm chứng bản này đúng là bản mới
- Cuối trang Cài đặt của tweak phải hiện **v2.2.3**. Nếu vẫn hiện số khác là file upload chưa ghi đè hết — báo em ngay, đừng test tiếp cho mất công.
- Test lỗi #1: mở CircleSwitcher → ấn vào khoảng trống → phải về thẳng màn hình chính, không thấy switcher gốc ở bất kỳ khung hình nào.
