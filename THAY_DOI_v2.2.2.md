# CircleSwitcher v2.2.2 — Thay đổi (theo 9 ý kiến từ video test 149s + ảnh chụp gần)

## Kiến trúc (trả lời câu hỏi của anh)
- Chế độ 0–3 là lớp phủ (overlay) đè lên switcher mặc định; chế độ 4–9 can thiệp trực tiếp switcher gốc. Đợt này giữ nguyên kiến trúc nhưng bịt kín các chỗ hở, và phần nào iOS tự làm được thì trả lại cho iOS (học theo cách iPadSwitcher/Zetsu mượt: ít tự vẽ lại, bám vào pipeline của hệ thống).

## Đã sửa
1. **Chớp switcher mặc định + delay khi mở:** lớp phủ trước đây chỉ gắn vào SAU KHI switcher gốc mở xong (ở sự kiện transitionDidEnd). Nay gắn ngay ở transitionDidBegin — lớp phủ "đi nhờ" animation mở của chính hệ thống, khung hình đầu tiên thấy được đã là CircleSwitcher; bỏ luôn hiệu ứng hiện hình riêng ở lần mở sớm (chính nó gây cảm giác delay). Nới cửa sổ chống kích hoạt trùng 0.40s → 1.0s để bản DidEnd không dựng lại vòng xoay lần 2.
2. **Ấn khoảng trống rớt về switcher mặc định:** hàm về màn hình chính cũ tháo lớp phủ TRƯỚC rồi mới gửi lệnh home — lệnh chậm/trượt là user rơi xuống bản gốc. Nay gửi lệnh home TRƯỚC (thử lần lượt clickedMenuButton → handleHomeButtonSinglePressUp → toggle của coordinator), lớp phủ giữ nguyên che bản gốc trong lúc hệ thống đóng, 0.30s sau mới tháo.
3. **Header cổ điển không theo thẻ + vị trí tên vô tác dụng (bỏ hẳn cách cũ):** cách dời header gốc theo thẻ đã chứng minh không qua được lượt bố cục của hệ thống trên máy thật. Nay: ẩn header gốc ở MỌI chế độ cổ điển, CircleSwitcher tự vẽ nhãn tên app của mình BÊN TRONG thẻ (pageView) — nhãn thừa hưởng transform của thẻ nên dính theo thẻ tuyệt đối, và cả 4 vị trí Trên/Giữa (kèm làm mờ thẻ 0.78)/Dưới/Ẩn đều chạy thật. Tên app lấy từ appLayout của container qua SBApplicationController.
4. **Viền đen + khung ma ở thẻ cổ điển:** nguyên nhân thật là code cũ tự xoá cornerRadius của thẻ về 0 (viền thành vuông) trong khi hệ thống bo tròn phần ảnh chụp riêng → khe lệch hiện thành viền đen; cộng với bóng đổ vẽ theo khung container (to hơn, lệch) thành khung thứ hai. Nay: không đụng vào cornerRadius của hệ thống nữa, viền + cắt góc nằm trên đúng một lớp của thẻ; bóng phát sáng dùng shadowPath = đúng hình bo tròn của thẻ.
5. **Mask glass không bám viền (thẻ chế độ 0):** ảnh rim PNG có nét vẽ thụt vào trong canvas, khi kéo giãn lên thẻ nó thành khung thứ hai lệch vào trong. Thẻ (không tròn) nay chỉ dùng viền layer duy nhất; orb tròn giữ lớp rim như cũ (đang đẹp trong ảnh test).
6. **Tắt app không thu hẹp khoảng cách:** sau khi kill, các icon còn lại giữ nguyên góc cũ (ảnh 2 icon neo ở 2 đầu màn hình, giữa trống). Nay sau mỗi lần kill (vuốt lên hoặc nút ✕ từng app), vòng xoay tự trượt (snap) về bước góc mới theo số app còn lại và đưa app kế tiếp ra giữa.
7. **Icon trên dấu ✕ "mất tiêu":** tìm thấy nguyên nhân trong code — icon bị ẩn cứng khi |theta| > 0.96π, mà đáy vòng tròn (chế độ 3) nằm đúng ở theta = ±π nên icon tới đó là biến mất. Nay: chế độ 3 không ẩn icon nữa; chế độ 0–2 chuyển sang mờ dần (0.86π → 0.985π) thay vì cắt đột ngột.
8. **Hai orb chồng nhau:** orb phía trước nay tăng độ đặc nền theo độ "ở trước" (0.86 → 0.98) để lớp kính mờ của nó làm nhoè phần phía sau thay vì xuyên thấu 2 viền; đồng thời thu nhỏ orb trung tâm của chế độ 2 theo khoảng cách khe khi có nhiều app (trước đây orb 224pt nuốt 2 orb bên cạnh).
9. **Mượt hơn:** khi kéo vòng xoay, các item được rasterize (GPU giữ nguyên hình, không vẽ lại bóng/mờ trên CPU mỗi khung hình); trang Cài đặt: việc dựng lại khung Xem trước được debounce 0.05s thay vì dựng lại ở từng tick kéo slider (nguyên nhân khựng khi chuyển trang/danh sách); thẻ CoverFlow/Deck giảm độ thu nhỏ (0.14 → 0.10) để thẻ trước bớt che thẻ sau.

## Giữ nguyên toàn bộ chức năng cũ
- 10 chế độ, glass refract/specular/dispersion, fade/scale/roll/circleMorph, presets, nút ✕ đóng hết app, vuốt lên tắt app trước, đế hologram, màu tuỳ chỉnh... không bỏ tính năng nào.

## Chưa kiểm chứng (cần build + máy thật)
- Bản này mới kiểm tra tĩnh (cân bằng ngoặc, đối chiếu key). Cần anh build 2.2.2, cài và quay video 60fps mới để em đếm khung hình chớp lúc mở và kiểm tra lại: header cổ điển, lằn ngang đế hologram (đợt này chưa đụng vào đế — nếu còn lằn, đợt sau em render đế thành 1 layer duy nhất như đã hứa), khoảng cách sau kill, icon đáy vòng.
- Nhãn tên tự vẽ ở cổ điển: nếu tên app nào hiện sai/thiếu (do iOS khác version trả appLayout khác), báo em để em chỉnh đường lấy tên.
