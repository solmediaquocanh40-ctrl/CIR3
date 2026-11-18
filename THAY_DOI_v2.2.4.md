# CircleSwitcher v2.2.4 — Theo lệnh trực tiếp của anh (21:56, 2026-11-18)

## 1. XOÁ HẲN ĐẾ HOLOGRAM
- Đế hologram (đĩa + vòng + halo, cái có dải đen/lằn ngang) bị loại bỏ hoàn toàn: không hiện ở bất kỳ chế độ nào nữa, cả trong tweak lẫn khung Xem trước ở Cài đặt. Không sửa, không vá — bỏ luôn như anh ra lệnh. Nút ✕ và mọi thứ khác giữ nguyên vị trí.

## 2. VIỀN XANH CHỒNG NHAU — BỎ LUÔN
- Nay chỉ app ở chính giữa (front) mới có viền xanh, hiện dần khi app tiến ra giữa; các app hai bên/phía sau KHÔNG có viền. Không còn viền nào để chồng lên nhau nữa.

## 3. LỖI ẤN MÀN HÌNH → THOÁT RA SWITCHER GỐC
- Trả lời câu hỏi của anh: không tweak nào thay thế được switcher gốc ở cấp hệ thống — kể cả Zetsu hay iPadSwitcher cũng không, chúng đều hook vào switcher của iOS. Cái làm được, và bản này làm, là chiếm trọn màn hình của switcher gốc trong suốt thời gian nó mở để bản gốc không lộ ra một khung hình nào:
  - Lớp phủ gắn ngay từ khung hình đầu tiên của animation mở (từ 2.2.2).
  - Không còn bất kỳ đường code nào tháo lớp phủ/khôi phục view gốc trong lúc switcher đang hiện hay đang thoát (đường code phá hoại này chính là thủ phạm sống sót qua 2.2.2, đã gỡ ở 2.2.3 và có trong bản này).
  - Tháo dỡ chỉ xảy ra sau khi switcher đã khuất khỏi màn hình (transitionDidEnd), cho cả 3 đường thoát: ấn khoảng trống về Home, ấn vào app, vuốt về Home.
- Bản 2.2.3 chứa phần sửa này nhưng được làm ra khi anh CHƯA ra lệnh nên anh chưa cài — bản 2.2.4 này là bản đầu tiên anh ra lệnh mà chứa nó.

## Giữ nguyên
- Toàn bộ chức năng còn lại: 10 chế độ, glass, fade/scale/roll, presets, ✕ đóng hết app, vuốt lên tắt app, màu tuỳ chỉnh. Chỉ mất: đế hologram (theo lệnh anh) và viền ở các app không ở giữa (để hết chồng viền).
- Version 2.2.3 → 2.2.4 đồng bộ mọi nơi. Kiểm tra: cuối trang Cài đặt phải hiện v2.2.4.
