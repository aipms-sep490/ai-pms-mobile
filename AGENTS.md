# Quy tắc làm việc

## Git và phạm vi

- `develop` là default branch và nhánh tích hợp. Không triển khai, push hoặc merge tính năng vào `main`.
- Mỗi task mới dùng nhánh riêng từ `origin/develop` đã cập nhật. Kiểm tra status/branch/baseline trước khi sửa; không reset, stash hoặc ghi đè thay đổi của người khác.
- Tạo PR vào `develop`, chạy kiểm tra và review trước merge. Chỉ merge khi được người dùng cho phép; yêu cầu hiện tại đã cho phép đưa nền tảng mobile vào `develop`.
- Người dùng đã chọn Flutter/Dart thay Expo. Xem `docs/FLUTTER_MIGRATION.md`; không tự khôi phục stack cũ.
- Bàn giao ghi phạm vi, validation và trạng thái commit/push/PR. Phân biệt test/build, backend/database thật, thiết bị và bản phát hành đã ký.

## Triển khai Flutter

- Dùng Flutter **3.50.0 stable**, đồng bộ với CI; commit `pubspec.lock`.
- Ưu tiên widget, navigation và quản lý trạng thái có sẵn trong SDK; Flutter 3.50 dùng package Material chính thức `material_ui` thay import `flutter/material.dart` đã deprecated. Không thêm global-state library hoặc abstraction khi tính năng chưa cần.
- Backend quyết định authorization, academic scope, capability, scoring và trạng thái nghiệp vụ.
- Ưu tiên Student/Team Leader, thông tin thường xem và thao tác ngắn; xem `docs/MOBILE_ROADMAP.md`.
- Dùng theme/ColorScheme chung, SafeArea, touch target tối thiểu 48dp, nhãn semantics và loading/error/empty. Kiểm tra màn hình nhỏ và text scale lớn.
- Android/iOS/web là project Flutter chuẩn. Giữ cấu hình nền tảng cần thiết trong Git; không commit build output, SDK local path, signing credential hoặc cấu hình thiết bị cá nhân.
- Đọc tài liệu chính thức tương ứng phiên bản Flutter/plugin trước khi dùng API mới hoặc nâng dependency.

## Bảo mật và kiểm tra

- `API_BASE_URL` qua define/file define là cấu hình công khai. Không commit credential/token.
- Native refresh token dùng `flutter_secure_storage`; access token và web preview session ở bộ nhớ. Không lưu mật khẩu.
- Thay đổi session/API cần test refresh đồng thời, hết phiên, logout, response đến muộn và storage failure.
- Trước PR chạy `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test` và web build. Khi đổi native/plugin/config, kiểm tra Android build và ghi rõ iOS/device chưa xác minh nếu chưa chạy.
- Không lấy validation Expo lịch sử làm bằng chứng Flutter. Ghi kết quả hiện tại vào `docs/FLUTTER_VALIDATION.md`; không khẳng định live backend/database/device đạt khi chỉ dùng mock hoặc build.
