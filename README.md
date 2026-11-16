# AI-PMS Mobile

Ứng dụng **Flutter/Dart** đồng hành cho sinh viên và trưởng nhóm: theo dõi đồ án, hạn công việc và thông tin cần xem trên điện thoại. Mobile dùng chung backend/database với AI-PMS Web.

`develop` là nhánh mặc định và nhánh tích hợp. Nền tảng chuyển từ Expo sang Flutter theo lựa chọn của người dùng; xem [quyết định chuyển đổi](docs/FLUTTER_MIGRATION.md).

## Phạm vi sinh viên — 0.3.0

- Login, khôi phục phiên và logout với tài khoản AI-PMS.
- Native lưu refresh token bằng `flutter_secure_storage`; access token ở bộ nhớ. Web preview chỉ giữ phiên trong bộ nhớ.
- Năm tab **Tổng quan / Đồ án / Công việc / Hộp thư / Tài khoản**, tải dữ liệu theo tab đã mở.
- Đồ án hiện tại: nội dung, GVHD nếu có, nhóm/thành viên, milestone và tiến độ; mở công việc từ deadline hoặc milestone.
- Việc của tôi: tìm kiếm, lọc trạng thái/quá hạn/bị chặn, phân trang, chi tiết và lịch sử. Đổi trạng thái chỉ khi capability BE cho phép, dùng concurrency token; bị chặn bắt buộc có lý do.
- Hộp thư: thông báo, lọc chưa đọc, đọc một/tất cả; điều hướng nội bộ kiểm tra quyền lại qua API. Nhận/từ chối lời mời nhóm của chính mình.
- Lịch họp: chi tiết, liên kết HTTP(S) mở ngoài app, RSVP dùng token của người tham gia. Báo cáo và phản hồi giảng viên ở chế độ đọc.
- Trò chuyện trực tiếp/nhóm/đồ án dùng cùng dữ liệu web: phân trang, trả lời, sửa/thu hồi theo quyền, thích, tệp, trạng thái đọc, tắt thông báo và tóm tắt AI. Mở qua biểu tượng chat trên thanh đầu trang.
- Phòng họp tích hợp LiveKit: mở/tham gia/kết thúc theo capability BE, mic/camera mặc định tắt, xem video và rời phòng. Backend phải bật/cấu hình dịch vụ video và lịch phải cho phép tham gia.
- Trợ lý AI: hỏi đáp học vụ/đồ án/kết hợp, lịch sử chung với web, tài liệu đính kèm, nguồn trích dẫn, cảnh báo/tiến độ, hỗ trợ bước tiếp theo, tóm tắt báo cáo và chuẩn bị họp; xem kết quả đã công bố.
- Ưu tiên vai trò `STUDENT`; backend quyết định quyền và phạm vi dữ liệu.
- Dùng Material UI qua package chính thức `material_ui`, quản lý trạng thái bằng SDK và HTTP qua `http`.

Code đối chiếu contract BE và staging. Chat cập nhật khi mở bằng REST polling; chưa có external push khi app đóng. Xem [phạm vi chat/call/AI](docs/MOBILE_COLLABORATION.md), [validation](docs/FLUTTER_VALIDATION.md) và [roadmap](docs/MOBILE_ROADMAP.md).

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
