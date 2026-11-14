# Validation nền tảng Flutter

Baseline chuyển đổi: `c4422a9`, nhánh `feat/flutter-foundation`. Kiểm tra ngày 14/11/2026 bằng Flutter 3.50.0 stable / Dart 3.14.0; không kế thừa trạng thái đạt từ Expo.

| Kiểm tra | Trạng thái | Bằng chứng/ghi chú |
| --- | --- | --- |
| SDK | Đã xác minh | SDK cục bộ `E:\tools\flutter`: Flutter 3.50.0 stable / Dart 3.14.0 |
| Dependency | Đạt | `flutter pub get`; dependency được khóa trong `pubspec.lock` |
| Dart format | Đạt | `dart format --output=none --set-exit-if-changed lib test` |
| Static analysis | Đạt | `flutter analyze`: No issues found |
| Unit/widget tests | Đạt | 16 tests: 10 auth/API/storage, 4 dashboard model, 2 widget flows; HTTP mock, không truy cập DB |
| Web release build | Đạt | `flutter build web --release --dart-define=API_BASE_URL=http://localhost:5080`; Wasm dry run cũng đạt |
| Android debug APK | Kiểm tra bắt buộc tại CI của PR | Local chưa có Android SDK/JDK; xem job Validate and build và artifact android-debug-apk; không suy từ web build |
| iOS build | Chưa xác minh | Cần macOS/Xcode và cấu hình phù hợp |
| Browser UI smoke test | Đạt với fixture API | Chrome 375×812 và 812×375: login 401/success, dashboard 503/retry, profile/logout; không tràn ngang, browser storage không chứa token |
| Native runtime và secure storage | Chưa xác minh | Cần emulator/thiết bị mục tiêu |
| Backend/database thật | Chưa xác minh | Không suy kết quả từ mock, widget test hoặc build |

## Mốc tích hợp

- Login đúng/sai và `/auth/me` bằng tài khoản thử nghiệm của môi trường được phép dùng.
- Dashboard đúng sinh viên/team/project; trạng thái chưa có team/project và bị từ chối quyền.
- Access token hết hạn, refresh đồng thời, mở lại native app và refresh token không hợp lệ.
- Logout online/offline; response đến muộn không khôi phục tài khoản đã đăng xuất.
- Safe area, bàn phím, text scale, màn hình nhỏ, mạng chậm/lỗi và thử lại trên thiết bị.

Không ghi mật khẩu/token hoặc dữ liệu cá nhân vào bằng chứng. Debug APK dành cho kiểm thử; signing/store release chưa được xác minh.

Widget test kiểm tra màn hình 375×667 với text scale 180%; đã sửa tràn nút đăng nhập được phát hiện bởi test. Luồng widget còn kiểm tra đăng nhập → lỗi dashboard/thử lại → tài khoản → landscape → đăng xuất.

Review độc lập đã kiểm tra auth races/storage, lifecycle dashboard, quyền, Android permissions/backup/debug HTTP, iOS keychain entitlement linkage và cấu hình CI. iOS/runtime native vẫn cần kiểm thử riêng.
