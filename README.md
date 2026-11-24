# AI-PMS Mobile

Ứng dụng **Flutter/Dart** đồng hành cho sinh viên và trưởng nhóm: theo dõi đồ án, hạn công việc và thông tin cần xem trên điện thoại. Mobile dùng chung backend/database với AI-PMS Web.

`develop` là nhánh mặc định và nhánh tích hợp. Nền tảng chuyển từ Expo sang Flutter theo lựa chọn của người dùng; xem [quyết định chuyển đổi](docs/FLUTTER_MIGRATION.md).

## Phạm vi ứng dụng — 0.9.0

Phiên bản 0.9.0 đồng bộ giao diện theo hệ màu **FAMS** của bản Web, cập nhật quy tắc BE V4.0, bổ sung thao tác nhanh cho sinh viên, SignalR realtime foreground, AI V4 streaming, đăng nhập Google và chế độ đồng hành cho Giảng viên:

- Login bằng Email/Mật khẩu hoặc **Google Sign-In** (challenge + binding cookie + `google_sign_in`), khôi phục phiên, liên kết Google và quản lý **Avatar hồ sơ**.
- Native lưu refresh token bằng `flutter_secure_storage`; access token ở bộ nhớ. Web preview giữ phiên ở bộ nhớ.
- **Không gian Sinh viên** (5 tab **Tổng quan / Đồ án / Công việc / Hộp thư / Tài khoản**): mục *Việc cần xử lý ngay*, **Lịch tổng hợp**, đồ án/mốc/thành viên, **Quy ước làm việc** 1 chạm, **Đánh giá chéo** (bắt buộc giải trình ≥ 30 ký tự khi < 50%), **Action Items**, theo dõi hồ sơ/sức khỏe/lịch sử kết quả (chỉ đọc).
- **Công việc V4:** việc của tôi/toàn đồ án, tạo/sửa/phân công theo capability & ngành, tạo nhanh 1 bước (`initialStatus`, `initialCriteria`), lý do `BLOCKED` ≥ 15 ký tự, báo rõ lỗi `422` thiếu minh chứng `DONE`, **bình luận task**, **checklist tiêu chí**, **nhãn/taxonomy** và **xóa mềm + hoàn tác 5 giây**.
- **Báo cáo & Lịch họp:** soạn/lưu nháp/nộp **báo cáo tiến độ gọn** tự điền từ BE (`/progress-reports/prefill`), RSVP, phòng họp LiveKit, **tóm tắt AI sau họp**.
- **SignalR Realtime foreground:** kết nối `/hubs/chat` (tin nhắn tức thì, đang nhập, presence, `AccessRevoked`) và `/hubs/notifications` (badge chưa đọc trực tiếp), tự lùi về REST khi mất kết nối; hỗ trợ **chuyển tin nhắn chat thành công việc**. Chưa bao gồm external push ngoài màn hình khóa (FCM/APNs).
- **Trợ lý AI V4:** streaming câu trả lời (NDJSON), đổi tên/ghim/xóa hội thoại, góp ý câu trả lời, gợi ý câu hỏi tiếp theo, đính kèm tài liệu, công cụ `PROGRESS`/`TASK` và xem kết quả công bố.
- **Chế độ Giảng viên (`LECTURER`):** 4 tab riêng (**Tổng quan & Triage Queue / Đồ án hướng dẫn / Hộp thư / Tài khoản**), duyệt/từ chối yêu cầu hướng dẫn, viết nhận xét ngắn cho báo cáo & cuộc họp, dùng chung chat/LiveKit/AI/inbox.
- Dùng Material UI qua `material_ui`, quản lý trạng thái bằng SDK, HTTP qua `http`, WebSocket SignalR qua `web_socket_channel` và Google Sign-In qua `google_sign_in`.

Xem [roadmap](docs/MOBILE_ROADMAP.md), [phạm vi chat/call/AI](docs/MOBILE_COLLABORATION.md), [báo cáo UX](docs/MOBILE_UX_REVIEW.md) và [validation](docs/FLUTTER_VALIDATION.md).

## Chuẩn bị môi trường

Cài **Flutter 3.50.0 stable / Dart 3.14.0** và thêm thư mục `bin` của SDK vào `PATH`; CI dùng cùng phiên bản. Trên máy Windows của dự án, SDK đặt tại `E:\tools\flutter`; đây là đường dẫn cục bộ, không phải dependency trong repo.

```powershell
flutter --version
flutter doctor -v
git clone https://github.com/aipms-sep490/ai-pms-mobile.git
cd ai-pms-mobile
git switch develop
flutter pub get
```

Android cần Android SDK/toolchain và emulator hoặc điện thoại bật USB debugging; kiểm tra bằng `flutter doctor`. Build/chạy iOS cần macOS và Xcode. Web preview dùng Chrome/Edge; `flutter devices` liệt kê thiết bị khả dụng.

## Cấu hình API và chạy

Truyền **origin của API**, không thêm `/api/v1`, bằng `API_BASE_URL`:

Chạy với backend đã triển khai (cùng API với web):

```powershell
flutter run -d web-server --web-hostname=localhost --web-port=5173 --dart-define-from-file=config/staging.json
```

Mở `http://localhost:5173`. Origin này đã được kiểm tra CORS với staging; cổng ngẫu nhiên có thể bị backend từ chối. File `config/staging.json` chỉ chứa API origin công khai, không chứa tài khoản. Web preview giữ phiên ở bộ nhớ nên đăng nhập lại sau reload.

| Thiết bị | Ví dụ API origin |
| --- | --- |
| Backend staging | `https://api-staging.khaidz.com` |
| Web trên máy chạy backend | `http://localhost:5080` |
| Android emulator mặc định | `http://10.0.2.2:5080` |
| Điện thoại thật | IP LAN truy cập được của máy chạy backend hoặc URL HTTPS môi trường thử nghiệm |

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:5080
flutter devices
# Thay emulator-5554 bằng device ID được liệt kê.
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:5080
```

Hoặc dùng file cấu hình công khai cục bộ:

```powershell
Copy-Item config/example.json config/local.json
# Sửa API_BASE_URL cho thiết bị đang dùng.
flutter run -d chrome --dart-define-from-file=config/local.json
```

`config/local.json` được bỏ qua bởi Git. Sau khi đổi define, dừng app rồi chạy lại; hot reload không thay cấu hình biên dịch.

Điện thoại phải kết nối được API trực tiếp. Với LAN, backend cần lắng nghe đúng địa chỉ và firewall cho phép cổng đó. `localhost` trên điện thoại trỏ về chính điện thoại. HTTP chỉ dùng trong phát triển tin cậy; triển khai dùng HTTPS. Web preview cần backend cho phép CORS đối với origin trình duyệt mà Flutter phục vụ.

Android chỉ cho phép cleartext HTTP trong debug build; release dùng HTTPS. Với iOS, ưu tiên HTTPS và kiểm tra App Transport Security của môi trường thử nghiệm trước khi dùng API LAN.

## Kiểm tra và build

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release --dart-define=API_BASE_URL=http://localhost:5080
flutter build apk --debug --dart-define-from-file=config/staging.json
```

Web output ở `build/web`; debug APK ở `build/app/outputs/flutter-apk/app-debug.apk` khi build thành công. Debug APK dành cho thử nghiệm, chưa phải bản phát hành đã ký để đưa lên store. iOS cần macOS/Xcode và kiểm tra riêng.

GitHub Actions chạy format/analyze/test, web release build và Android debug APK build cho PR vào `develop` và push lên `develop`. CI dùng API origin công khai để biên dịch; không đăng nhập backend hoặc tự phát hành app.

Khi CI build thành công, tải artifact `android-staging-debug-apk` tại trang workflow run; artifact được giữ 7 ngày. APK dùng `config/staging.json`, kết nối backend HTTPS đã triển khai. Đổi môi trường bằng `--dart-define` hoặc file define; không đưa tài khoản vào cấu hình build.

## Cấu hình và phiên

- `--dart-define` và giá trị từ file define có thể đọc được từ app đã build. Chỉ đặt cấu hình công khai, không đặt mật khẩu, signing key hoặc service credential.
- Không commit token, mật khẩu hoặc cấu hình riêng của môi trường. Commit `pubspec.lock` để dependency nhất quán.
- Endpoint và các thao tác được hỗ trợ: xem [contract MVP](docs/MOBILE_MVP.md).
- Không lưu mật khẩu hoặc access token xuống storage. Web preview đăng nhập lại sau reload.
- Quyền và chính sách học vụ do backend quyết định.

## Làm việc với Git

```powershell
git switch develop
git pull --ff-only origin develop
git switch -c feat/ten-tinh-nang
# Triển khai, kiểm tra, commit
git push -u origin feat/ten-tinh-nang
```

Mở PR với base **`develop`**, kiểm tra CI và review trước merge. Không code, push hoặc merge tính năng vào `main`.

Nghiệm thu trên Android/iOS mục tiêu vẫn cần kiểm tra secure storage, khôi phục phiên, bàn phím, back và liên kết mở ngoài app. External push và phát hành store là các hạng mục riêng.
