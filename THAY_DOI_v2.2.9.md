# CircleSwitcher v2.2.9 — Đồng bộ animation in/out theo transition của hệ thống

Bản tách riêng như đã duyệt: chỉ làm phần đồng bộ nhịp animation, không đụng vào các sửa chữa của 2.2.8 (thoát switcher, vòng xám, cổ điển, slider nghiêng đều giữ nguyên). Mới kiểm tra tĩnh (cân bằng ngoặc khớp) — CHƯA Theos build, CHƯA test máy thật.

## Vấn đề gốc

Từ 2.2.6–2.2.8, animation của tweak chạy theo **đồng hồ riêng tính từ lúc chạm**: mở app thì fade/expand chạy ngay khi chạm, morph vào chạy 0,55s từ lúc gắn overlay. Trong khi animation của SpringBoard bắt đầu **muộn hơn và chạy theo nhịp của nó**. Hai đồng hồ lệch pha nhau là chỗ khựng ở điểm nối — dù từng animation riêng lẻ đều mượt.

## 1. Mở app: fade/expand bắt đầu cùng lúc với animation của hệ thống

- Khi chạm chọn app, tweak giờ chỉ **lên cò** (đặt cờ chờ `activationAnimPending`) rồi kích hoạt app như cũ — không fade, không expand ngay.
- Khi **transitionDidBegin của đường thoát** chạy (đúng khoảnh khắc SpringBoard bắt đầu phóng app), hook gọi `_cs_runActivationAnimation`: kính phình phủ màn hình (0,30s) + sân khấu mờ dần (0,32s khi có kính, 0,25s khi không) — cả hai cùng xuất phát với animation của hệ thống.
- Chốt an toàn: nếu đường kích hoạt nào đó không đi qua hook này, một fallback 0,25s tự chạy animation thay thế; nếu kích hoạt thất bại lặng lẽ (không có transition nào), không animation nào chạy và watchdog trả sân khấu nguyên vẹn như cũ. Cờ chờ được dọn ở teardown và ở watchdog nên không rò sang lần mở sau.

## 2. Morph lúc mở switcher: 0,55s → 0,42s

- Cả hai nhánh morph (kính thật và kính mờ dự phòng) rút từ 0,55s xuống **0,42s** — khớp với thời lượng transition mở switcher của hệ thống (ước lượng theo nhịp animation mặc định của iOS), để morph kết thúc cùng lúc sân khấu của hệ thống yên vị thay vì chạy thừa một đoạn trên nền đã đứng yên.

## 3. Exit guard chạy nhẹ hơn

- Vòng lặp canh giữ lúc thoát (ẩn lại view gốc) giãn nhịp từ ~40ms xuống **~80ms**, 30 lượt → 15 lượt (tổng thời gian canh giữ vẫn ~1,2s): giảm một nửa số lần đánh thức main queue trong lúc thoát. Việc đưa sân khấu lên trước vốn đã chỉ làm khi có view khác che nó (giữ nguyên).

## Version

2.2.8 → 2.2.9 đồng bộ mọi nơi: control, Info.plist (×2), footer Root.plist/Root_EN.plist, EasterEgg, LogoCell, RootListController, build.yml + tên artifact, README, header Tweak.x.

## Cần anh kiểm chứng trên máy

1. Mở app từ vòng xoay (cả chế độ kính 0–3 và không kính): còn khựng ở điểm nối không, kính phình có cùng nhịp với app phóng lên không.
2. Mở switcher: morph thu vào có kết thúc gọn cùng lúc mở xong không (đừng còn đoạn chạy thừa).
3. Thoát về Home bằng chạm vùng trống + vuốt: vẫn thoát tốt như 2.2.8 và không lộ switcher gốc (guard đã giãn nhịp — kiểm tra kỹ điểm này).
4. Quay video 60fps lúc mở/đóng app giúp em nếu được — phần này đúng/sai nằm ở nhịp thời gian, nhìn video mới kết luận chắc được.
