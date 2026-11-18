# CircleSwitcher v2.2.1 — Thay đổi

- **Sửa lỗi build trên GitHub Actions:** workflow chết ở bước cài Theos với lỗi `Package 'libxml2' has no installation candidate` (exit code 3) vì runner `ubuntu-latest` đã chuyển sang bản Ubuntu mới, nơi gói `libxml2` bị đổi tên/loại bỏ, trong khi script cài Theos vẫn yêu cầu tên gói cũ. Build chưa từng chạm tới bước biên dịch code.
  - Đã ghim `runs-on: ubuntu-22.04` trong `.github/workflows/build.yml` — bản Ubuntu khớp với script cài Theos hiện tại.
- **Version:** 2.2.0 → 2.2.1, đồng bộ ở control, Info.plist, build.yml + tên artifact, README, Tweak.x, LogoCell, EasterEgg, RootListController, Root.plist/Root_EN.plist (theo quy tắc mỗi bản mới +0.0.1).
- Ngoài 2 điểm trên, code giữ nguyên như bản 2.2.0.
