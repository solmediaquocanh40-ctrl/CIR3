# THAY ĐỔI v2.2.6 — Sửa 3 lỗi tồn đọng (theo đúng kế hoạch đã duyệt 23:06 2026-11-18)

Bản này CHỈ sửa 3 lỗi anh báo sau khi test bản trước (22:50 2026-11-18). Không đụng vào
entrance morph (để nguyên chờ bản kính thật 2.2.7 thay bằng morph shader), không đụng
chế độ cổ điển 4–9, giữ nguyên toàn bộ chức năng cũ.

## Lỗi 1 — Chạm màn hình vẫn lộ switcher gốc (lỗi nặng nhất)

Hai thủ phạm, sửa cả hai:

1. **Xoá hẳn fallback lộ switcher gốc.** Trong `_cs_dismissSwitcherToHome`, nếu mọi
   selector lệnh Home đều trượt trên bản iOS này (`sentHome == NO`), code cũ gọi
   `_cs_setSwitcherActive:NO` — khôi phục view gốc NGAY TẠI CHỖ. Tức là lỗi này nằm
   trong thiết kế cũ, không phải iOS tự làm. Từ 2.2.6: khi lệnh Home thất bại, tweak
   **ở lại trong switcher** — trả sân khấu về trạng thái tương tác đầy đủ như trước
   khi chạm (bật lại tương tác + chạy lại physics). Không còn bất kỳ đường nào tự ý
   hiện switcher gốc.
2. **Exit guard — vòng lặp ẩn lại view gốc khi đang thoát.** Từ lúc transition thoát
   bắt đầu (`transitionDidBegin`, toMode 1 = Home hoặc 3 = App), view gốc bị ẩn lại
   ngay sau `%orig`, rồi một vòng lặp mỗi ~40ms (tối đa ~1,2s) tiếp tục ẩn lại +
   đưa stage lên trên cùng cho đến khi `transitionDidEnd`. Phòng trường hợp iOS tự
   hiện lại/re-layout view gốc giữa chừng animation thoát — đường rò thứ hai của lỗi.
   Watchdog thoát cũng được nâng cấp: nếu lệnh thoát bị nuốt hẳn, nó khôi phục cả
   alpha + physics của stage (trước chỉ bật lại tương tác).

## Lỗi 2 — Vuốt còn khựng (phần thuộc về dựng items)

Tìm ra phần còn thiếu: đường nhanh cũ chỉ chạy khi danh sách app **giống hệt cả thứ
tự**. Mà mở một app là iOS sắp xếp lại recents → gần như mọi lần mở đều rơi vào đường
dựng lại TOÀN BỘ items (nạp lại mọi icon đồng bộ) và reset góc xoay về 0.

Từ 2.2.6, `reloadAppsFromSwitcher` có **đường tái dùng theo bundleID**: app còn tồn
tại thì giữ nguyên item cũ (icon/halo/rim đã nạp sẵn, chỉ cập nhật lại appLayout và
thứ tự), app đã đóng mới bị gỡ, app mới mới phải tạo item. `spinAngle` được giữ
nguyên — layout tự suy lại app chính giữa từ góc xoay — nên vòng xoay không còn nhảy
về 0. Chỉ khi không còn app nào trùng (mở lần đầu / đổi hẳn danh sách) mới dựng lại
toàn bộ như cũ. Việc tạo item được tách thành `_cs_makeItemForLayout:` dùng chung
cho cả hai đường.

Lưu ý trung thực: phần khựng của **entrance morph** (2 view blur sống bị resize mỗi
frame) chưa sửa ở bản này — theo kế hoạch đã duyệt, morph sẽ bị thay hẳn bằng morph
shader ở bản kính thật 2.2.7, sửa bây giờ là công thừa một vòng.

## Lỗi 3 — Chọn app thì bung ra cũng khựng

Trước đây khi kích hoạt app, stage đứng yên ở độ mờ 100% suốt animation thoát rồi
**biến mất bằng một cú cắt cứng** ở `transitionDidEnd`. Từ 2.2.6: ngay khi lệnh kích
hoạt được gửi, stage **mờ dần trong ~0,2s** theo animation mở app. Nếu kích hoạt thất
bại lặng lẽ (không có transition nào bắt đầu), watchdog 0,8s sẽ khôi phục alpha +
tương tác + physics — không bao giờ để người dùng kẹt trên một overlay đã mờ.

## Version

2.2.5 → **2.2.6** đồng bộ mọi nơi: control, Info.plist (prefs), build.yml + tên
artifact, README, header Tweak.x, LogoCell, EasterEgg, nút share + tiêu đề ẩn trong
RootListController, footer Root.plist / Root_EN.plist.

## Chưa kiểm chứng

Bản này mới kiểm tra tĩnh (đối chiếu code + cân bằng cú pháp), **chưa build Theos,
chưa test máy thật**. Cần anh: upload TOÀN BỘ file trong zip lên GitHub (kèm file
build.yml riêng vì upload web nuốt thư mục .github), build, kiểm tra footer Cài đặt
đúng v2.2.6, rồi quay video 60fps 3 thao tác: (1) chạm vùng trống trong
CircleSwitcher, (2) vuốt qua lại vài vòng rồi mở lại switcher lần hai, (3) chọn một
app bất kỳ. Ba đoạn đó phán cả 3 lỗi.
