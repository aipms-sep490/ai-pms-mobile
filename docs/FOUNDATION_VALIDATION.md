# MOB-03 validation — 14/11/2026

## Đã kiểm tra

- TypeScript strict, Expo ESLint và 10 test logic đạt.
- Test tập trung vào API origin/path, lỗi và timeout, login + `/auth/me`, refresh đồng thời, refresh hết hạn, resource 403, logout khi mất mạng, response đến sau logout và cách hiển thị deadline/progress.
- `npx expo install --check`: dependency phù hợp Expo SDK 58.
- `npx expo-doctor`: 20/20 checks.
- `npx expo export --platform all`: xuất bundle Android, iOS và web thành công.
- Chrome web preview ở 375×812 và landscape 812×375: không tràn ngang; đã kiểm tra form validation, login 401, login thành công, dashboard 503 + retry, dữ liệu tổng quan, profile và logout. API trong smoke test là fixture cục bộ, không truy cập database dự án.
- Web preview không ghi token vào localStorage/sessionStorage. Route được bảo vệ đưa người chưa đăng nhập về màn đăng nhập.
- Review độc lập đã kiểm tra auth/storage races, dashboard contract và workflow CI. Đã sửa safe area của màn Tổng quan và chiều cao/nhãn tab bar.

## Giới hạn

- Chưa kiểm thử native runtime trên điện thoại/emulator, SecureStore thực tế hoặc đăng nhập vào backend triển khai.
- Bundle export không phải APK/IPA hoặc bản phát hành đã ký. Tài khoản EAS, signing và store distribution chưa được cấu hình.
- `npm audit --omit=dev` ghi nhận 3 cảnh báo moderate trong chuỗi Expo → fingerprint → minimatch (tooling tạo fingerprint). Không dùng `audit fix --force` vì đề xuất hiện tại hạ Expo xuống major cũ; cần theo dõi bản vá upstream.
