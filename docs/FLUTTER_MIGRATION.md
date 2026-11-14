# Chuyển nền tảng mobile sang Flutter

## Quyết định

Ngày 14/11/2026, người dùng chọn **Flutter/Dart** thay nền tảng Expo/React Native vừa khởi tạo. Triển khai trên `feat/flutter-foundation`, baseline `c4422a9`; PR nhắm `develop`, không đưa thay đổi vào `main`.

Quyết định này thay lựa chọn Expo trước đó. Backend/database và contract nghiệp vụ dùng chung vẫn giữ nguyên.

## Phạm vi chuyển đổi

- Flutter **3.50.0 stable / Dart 3.14.0**, project chuẩn Android/iOS/web; UI dùng package Material chính thức `material_ui`.
- Thay runtime/tooling Expo, React Native, TypeScript, npm bằng Flutter/pub; dùng `http` và `flutter_secure_storage`.
- Giữ auth login/refresh/me/logout và dashboard sinh viên theo contract backend.
- Native giữ refresh token trong secure storage, access token ở bộ nhớ; browser preview giữ phiên trong bộ nhớ.
- Hai tab Tổng quan/Tài khoản. Các module project/task đầy đủ và store release là bước sau.
- API origin công khai `API_BASE_URL` qua `--dart-define` hoặc `--dart-define-from-file`; không chuyển credential sang build config.
- CI format/analyze/test, web release build và Android debug APK build. Live backend/database, thiết bị và iOS được xác minh riêng.

## Tài liệu cần đồng bộ

SRS tại repo `ai-pms-docs`, mục external interfaces, hiện ghi **React Native application for selected student/supervisor journeys**. MOB-00/MOB-02 cũng đề xuất Expo. Lựa chọn Flutter của người dùng là quyết định mới cho repo mobile; cần task cập nhật SRS/nghiên cứu để phản ánh stack thực tế. Bản chuyển đổi này không tự sửa tài liệu ở repo docs hoặc coi mô tả React Native cũ là yêu cầu quay lại Expo.

Phạm vi sản phẩm vẫn là Student/Team Leader trước, xem tiến độ và thao tác nhanh. Làm rõ phạm vi Supervisor khi triển khai vì bảng actor và external interfaces hiện mô tả khác nhau.

## Bằng chứng

`FOUNDATION_VALIDATION.md` là validation **Expo lịch sử** tại `c4422a9` (PR #4), không chứng minh bản Flutter đạt. Kết quả mới ghi tại `FLUTTER_VALIDATION.md`. Chỉ đánh dấu đạt sau khi chạy đúng kiểm tra; build không chứng minh backend/database hoặc thiết bị đã được nghiệm thu.
