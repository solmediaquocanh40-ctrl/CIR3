# CircleSwitcher v2.2.0 — Những gì đã sửa trong đợt này

## Theo video quay thật trên máy (101 giây, 60fps)

1. **Header gốc của iOS kẹt ở trên cùng** (“Ảnh ▾ Bubble ▾ Bubble”, “Tweak Settings”, “Sileo”, icon nhỏ bên trái, đè lên pill tên app ở kiểu tròn)
   - Nguyên nhân: code cũ chỉ hook `setAlpha:` — header đã hiện sẵn khi switcher ổn định thì không bao giờ bị ẩn.
   - Đã sửa: ẩn chủ động trong `layoutSubviews`/`didMoveToWindow` của header, duyệt đệ quy toàn bộ cây view khi kích hoạt overlay (trước đây chỉ nhìn 1 cấp subview), và mỗi item container tự tìm + ẩn/khôi phục header của chính nó.

2. **Đế hologram biến mất ở kiểu 0, 1, 2**
   - Nguyên nhân: đế là view trong suốt chứa 2 ảnh template nhạt; view trong suốt không tự đổ bóng được, mà phần sáng thật trước đây nằm ở bóng đổ.
   - Đã sửa: đế gồm một **đĩa đặc phát sáng** (fill + shadow của chính nó, offset 0 nên không tạo lằn ngang) và một **vòng đặc** vẽ bằng border. Bóng của container trong suốt đã tắt hẳn — lằn ngang nếu còn sẽ lộ rõ trong video kiểm chứng tiếp theo.

3. **Kiểu cổ điển: tên app ở trên không đi theo thẻ; đặt tên Ở giữa/Phía dưới không tác dụng**
   - Nguyên nhân: transform chỉ áp lên thân thẻ (`pageView`), header là view riêng không được chạm tới; `titlePosition` ở chế độ cổ điển chỉ dùng để ẩn/hiện header.
   - Đã sửa: header được dời theo đúng thẻ của nó và nhận cùng transform; cả 4 vị trí (Trên / Giữa / Dưới / Ẩn) giờ đều chạy ở chế độ cổ điển.

4. **Chạm vào app thì CircleSwitcher thoát trước, switcher mặc định lộ ra; bung/thu app giật**
   - Nguyên nhân: ẩn overlay trước rồi launch app ở runloop kế tiếp bằng `launchApplicationWithIdentifier:`.
   - Đã sửa: kích hoạt qua `SBUIController activateApplication:` (đường của hệ thống) **trong cùng khung hình**, khôi phục view gốc cùng lúc để hệ thống animate thẻ thật, overlay chỉ cross-fade 0,18s bên trên animation đó. Fallback về cách cũ nếu API không có.
   - Giảm khựng thêm: bỏ kích hoạt trùng 2 lần mỗi lần mở (hook ViewController + Coordinator), carousel không dựng lại khi danh sách app không đổi (giữ nguyên góc xoay), entrance giảm từ scale 1,14 + mờ nặng xuống 1,03 và chạy đúng ngay lần mở đầu tiên, gesture khoá hướng không còn cộng dồn quãng vuốt đầu.

5. **Nút ✕ chỉ đóng app ở giữa**
   - Đã sửa: ✕ giờ **đóng hết mọi app** trong switcher (nhãn trong Cài đặt đã ghi rõ). Vuốt lên trên app ở giữa vẫn đóng riêng app đó. Chạm ✕ không còn bị gesture chạm của sân khấu gọi đóng lần thứ hai.
   - Cơ chế kill chỉ dùng **một** đường đầu tiên áp dụng được (delegate kill → coordinator delete → recents remove), không bắn cả ba cùng lúc như trước.

6. **Viền xanh chồng nhau, glass không vừa khung**
   - Đã sửa: halo chuyển vào **bên trong** từng item và bị chính bo góc của item cắt, không tràn sang item bên cạnh; ảnh vành kính được fit lại đúng bounds từng item mỗi layout; viền và kính dùng chung một đường bo góc; khoảng z giữa các item tăng từ 320 lên 520.

## Theo báo cáo rà soát tĩnh trước đó

7. **Cấu trúc build chuẩn Theos**: thư mục `CircleSwitcherPrefs/` riêng, `Resources/` chứa Root.plist/Root_EN/Presets/Info và toàn bộ PNG, `control`/`Makefile`/`.github/workflows/build.yml` đúng tên đúng chỗ.
8. **Tên asset đúng quy ước scale**: `ambient_backdrop@2x.png`, `glass_rim@3x.png`, `orb_halo@2x.png`… (trước là `_2x/_3x` nên không tải được), bổ sung bản 1x cho 3 asset thiếu.
9. **Nối dây các tuỳ chọn chết**: 3 slider kính `glassRefract/glassSpecular/glassDispersion` giờ thật sự điều khiển vành kính/viền ở cả switcher thật và Xem trước (tán sắc = lệch màu viền về phía magenta theo mức chỉnh); `fadeIcons/scaleIcons/rollIcons` áp dụng ở cả overlay và cổ điển; `circleMorph` có tác dụng ở overlay. Các key còn lại trong Presets.json (`style`, `snapCircle`, `springStiffness`…) vẫn không có đường tiêu thụ — khi áp preset, chỉ các key dịch được mới có hiệu lực, như trước.
10. **Đồng bộ**: version 2.2.0 ở mọi nơi (control, Info, GitHub Actions, logo, Easter Egg, nút share), default `orbSize` thống nhất 0,72, Preview mode 2 nội suy liên tục giống switcher thật, color picker không còn bắn ReloadPrefs liên tục khi kéo màu.
11. **LiquidGlass.metal**: vẫn là shader tham chiếu, **chưa được biên dịch/dùng** — hiệu ứng kính hiện thực bằng CALayer. Đã gỡ framework Metal khỏi cả 2 Makefile để không gây hiểu lầm. Nếu muốn dùng shader Metal thật, đó là một đợt làm riêng (MTKView cho từng orb sẽ đánh đổi độ mượt).

## Chưa kiểm chứng được ở đây
- Chưa build bằng Theos/iOS SDK và chưa chạy trên máy thật trong đợt sửa này. Cần: đẩy repo lên GitHub Actions để lấy .deb, cài lên máy, quay lại video 60fps để đo: header còn kẹt không, đế sáng mức nào, lằn ngang còn không, khung hình khựng khi mở app còn mấy frame.
