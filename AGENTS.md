# Quy tắc làm việc

## Git và phạm vi

- `develop` là default branch và nhánh tích hợp của repo này. Không triển khai, push hoặc merge tính năng vào `main`.
- Mỗi task mới dùng một nhánh riêng từ `origin/develop` đã cập nhật. Trước khi sửa, kiểm tra status/branch/baseline; không reset, stash hoặc ghi đè thay đổi của người khác.
- Tạo PR vào `develop`, chạy kiểm tra và review trước khi merge. Chỉ merge khi đã được người dùng cho phép; yêu cầu hiện tại đã cho phép merge phần khởi tạo mobile vào `develop`.
- Bàn giao ghi phạm vi thực tế, kết quả validation và trạng thái commit/push/PR. Không gọi bundle export là APK/IPA đã build hoặc kiểm thử thiết bị.

## Triển khai

- Dùng Expo Router cho navigation; route đặt trong `src/app`, logic và component đặt ngoài thư mục route.
- Tái sử dụng API backend hiện có. Backend quyết định authorization, academic scope, capability và trạng thái nghiệp vụ.
- Ưu tiên Student/Team Leader. Giữ phạm vi mobile ở thông tin cần theo dõi và thao tác ngắn; xem `docs/MOBILE_ROADMAP.md`.
- Dùng token giao diện trong `src/ui/theme.ts`, touch target tối thiểu 48dp, có loading/error/empty và nhãn accessibility.
- Không thêm global state, thư viện hoặc abstraction nếu tính năng hiện tại chưa cần.
- Cài thư viện Expo/native bằng `npx expo install` để giữ tương thích SDK. Đọc tài liệu tương ứng phiên bản Expo trong `package.json` trước khi dùng API mới.
- Không sửa trực tiếp thư mục native được sinh; cấu hình qua app config và plugin.

## Bảo mật và kiểm tra

- Không commit credential, token hoặc file môi trường cục bộ. `EXPO_PUBLIC_*` là dữ liệu công khai.
- Native refresh token dùng SecureStore; không lưu mật khẩu hoặc access token xuống storage thông thường. Web preview giữ phiên trong bộ nhớ.
- Thay đổi logic phiên/API phải có test phù hợp, đặc biệt refresh đồng thời, hết phiên và đăng xuất.
- Trước PR chạy `npm run check`, `npx expo install --check` và `npx expo export --platform all`. Nêu rõ phần chưa thể xác minh trên thiết bị/backend thật.
