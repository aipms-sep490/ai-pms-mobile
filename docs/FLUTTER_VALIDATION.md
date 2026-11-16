# Validation nền tảng Flutter

Baseline chuyển đổi: `c4422a9`, nhánh `feat/flutter-foundation`. Kiểm tra ngày 14/11/2026 bằng Flutter 3.50.0 stable / Dart 3.14.0; không kế thừa trạng thái đạt từ Expo.

Bảng đầu ghi kết quả tại mốc chuyển đổi. Kết quả UX/UI và kết nối staging mới hơn nằm ở phần tiếp theo.

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

## UX/UI và backend staging — 14/11/2026

Nhánh `feat/mobile-workspace-ux`, baseline `def7e53`. Giữ nguyên hai tab Tổng quan/Tài khoản và các endpoint hiện có; không thêm thao tác project/task. Dùng skill `chrome-devtools` và `ui-ux-pro-max` để audit, kiểm tra trên Chrome bằng DevTools MCP.

- Đăng nhập: bỏ nhãn lặp, rút gọn phần giới thiệu, giữ autofill/validation/hiện mật khẩu và thông báo đang đăng nhập.
- Tổng quan: thu gọn header, gom số liệu cùng chiều cao, giữ cảnh báo quá hạn bằng chữ và màu; phần đồ án/tiến độ/hạn xuất hiện sớm hơn. Thêm nút làm mới 48dp có nhãn, khóa khi đang tải, giữ pull-to-refresh.
- Tài khoản: thông tin gọn hơn; giữ logout, trạng thái đang xử lý và lỗi. Hai tab có màu icon/nhãn nhất quán.
- Bố cục nội dung tối đa 680dp, chữ dài được xuống dòng; số liệu chuyển thành hàng dọc khi chữ lớn hoặc màn hẹp. Không thêm dependency; `pubspec.lock` được tạo lại đầy đủ bằng SDK đã chốt thay cho lockfile JSON thiếu dependency cũ.

| Kiểm tra lượt UX | Kết quả |
| --- | --- |
| Format / analyze | Đạt; không có issue |
| Unit/widget tests | 16 tests đạt. Mở rộng flow test để kiểm tra làm mới lỗi vẫn giữ dữ liệu, khóa nút khi đang tải, retry, màn 320×667 với text scale 200%, tài khoản và logout landscape |
| Web release | Đạt với `--dart-define-from-file=config/local.json` trỏ tới staging; Wasm dry run đạt |
| Chrome DevTools | Xem trực tiếp login, dashboard, tài khoản ở 390×844, 375×667 và 812×375; login/dashboard desktop 1366×768. Không thấy tràn nội dung trong các màn đã xem |
| API staging thật | `POST /auth/login` 200, `GET /auth/me` 200, `GET /dashboards/student` 200; dữ liệu qua API, không truy cập DB trực tiếp |
| Mất mạng / retry | DevTools Offline: thông báo lỗi kết nối và dữ liệu cũ vẫn còn; online + Thử lại gọi dashboard 200 |
| Console | Luồng online đã kiểm tra không có error/warning; giả lập Offline tạo lỗi network dự kiến |

API origin dùng khi kiểm tra: `https://api-staging.khaidz.com`, web origin `http://localhost:5173`; cấu hình công khai có tại `config/staging.json`. Không lưu tài khoản, token hoặc screenshot có thông tin cá nhân vào repo.

Kết quả backend ở trên xác nhận các endpoint phục vụ dữ liệu thật cho tài khoản thử nghiệm được phép dùng; chưa xác minh tính đúng đắn toàn bộ dữ liệu DB, native runtime, iOS hoặc bản phát hành store. Android debug APK được build bởi CI của PR; APK mặc định CI vẫn dùng API emulator, không dùng làm bằng chứng kết nối staging.

## Mốc tích hợp

- Login đúng/sai và `/auth/me` bằng tài khoản thử nghiệm của môi trường được phép dùng.
- Dashboard đúng sinh viên/team/project; trạng thái chưa có team/project và bị từ chối quyền.
- Access token hết hạn, refresh đồng thời, mở lại native app và refresh token không hợp lệ.
- Logout online/offline; response đến muộn không khôi phục tài khoản đã đăng xuất.
- Safe area, bàn phím, text scale, màn hình nhỏ, mạng chậm/lỗi và thử lại trên thiết bị.

Không ghi mật khẩu/token hoặc dữ liệu cá nhân vào bằng chứng. Debug APK dành cho kiểm thử; signing/store release chưa được xác minh.

Widget test kiểm tra màn hình 375×667 với text scale 180%; đã sửa tràn nút đăng nhập được phát hiện bởi test. Luồng widget còn kiểm tra đăng nhập → lỗi dashboard/thử lại → tài khoản → landscape → đăng xuất.

Review độc lập đã kiểm tra auth races/storage, lifecycle dashboard, quyền, Android permissions/backup/debug HTTP, iOS keychain entitlement linkage và cấu hình CI. iOS/runtime native vẫn cần kiểm thử riêng.

## MVP sinh viên 0.2.0 — 16/11/2026

Baseline `f6f3c54`, nhánh `feat/mobile-student-mvp`. Contract đối chiếu BE develop `9eedf9a` và staging; phạm vi chi tiết tại [MOBILE_MVP.md](MOBILE_MVP.md). Dùng Flutter 3.50.0/Dart 3.14.0; thêm plugin chính thức `url_launcher` 6.3.3, giữ lockfile do SDK tạo.

| Kiểm tra | Kết quả |
| --- | --- |
| Format / analyze | Đạt; không có issue |
| Unit/widget | 25 tests đạt: auth/API/storage, model, các flow cũ và workspace mới |
| Task mutation | HTTP mock: capability/version khớp, 409 tải authority mới, bắt buộc lý do BLOCKED, khóa gửi lặp, 503 giữ dữ liệu cũ, 403 xóa nội dung, logout hủy route chi tiết |
| Inbox/invitation | HTTP mock: phân trang, PATCH read, POST read-all, đúng người nhận/PENDING, xác nhận nhận lời mời, không gửi lặp |
| Lịch/báo cáo | HTTP mock: RSVP dùng token người tham gia thay token meeting; đọc báo cáo dài và feedback trên 320×667, text scale 200% |
| Lifecycle/accessibility | Response và callback đến sau logout/dispose không phục hồi màn cũ hoặc gọi setState trên page đã hủy; kiểm tra semantic action của hàng mở lịch và nhãn feedback có thể đọc |
| Backend thật | Các API đọc project, team, milestone/progress, task/list/detail/history/capability, notification, invitation, meeting/collaboration và danh sách report trả 200. Không truy cập DB trực tiếp |
| Ghi dữ liệu staging | Chưa nghiệm thu mutation trên bộ dữ liệu học vụ thử riêng; không lấy mock làm bằng chứng ghi DB thật |
| Android/iOS runtime | Chưa xác minh: máy hiện không có Android SDK/emulator; iOS cần macOS/Xcode |

Đã sửa các lỗi được test/audit bắt: ListTile bị lớp nền che hiệu ứng bấm; ExpansionTile dùng chung storage key với vị trí cuộn; brand đăng nhập tràn ở 320px/text 200%; hàng danh sách và nội dung dài thiếu nhãn semantics rõ ràng. Không thêm dữ liệu giả vào bản app.

CI hiện build web release và `android-staging-debug-apk` với `config/staging.json`, không còn dùng API emulator cho artifact mới. Artifact giữ 7 ngày; build không thay thế nghiệm thu thiết bị/signing/store release. Không ghi credential, bearer token hoặc ảnh có thông tin cá nhân vào repo.

## Chat/call/AI 0.3.0 — 16/11/2026

Nhánh `feat/mobile-chat-call-ai`, baseline `797c022`; đối chiếu BE develop `9eedf9a`. Ưu tiên đồng bộ tính năng theo yêu cầu người dùng; không chờ toàn bộ ma trận nghiệm thu native để mở phạm vi.

- Flutter 3.50.0 / Dart 3.14.0; lockfile sinh bởi SDK; LiveKit 2.13.2, File Picker 13.3.3, UUID 4.6.0.
- Format/analyze đạt. 28 tests đạt, gồm hồi quy 25 tests và kiểm tra multipart replay qua refresh, binary download, ID/sequence chat 64-bit, join credential hết hạn/URL không an toàn/capability.
- Web release staging build đạt, Wasm dry run đạt. Android debug APK phải qua job CI trước merge; iOS và runtime camera/mic trên thiết bị chưa xác minh.
- API staging thật: login/dashboard 200; chat conversations 200 (rỗng), recipients 200, upload policy 200; lịch sử assistant và AI run 200 (rỗng); digest/rủi ro và workflow NEXT_STEPS 200. Kết quả chưa công bố trả 404.
- Tài khoản thử hiện chỉ có lịch họp COMPLETED. Chưa gọi join/start/end phòng thật, chưa gửi tin nhắn cho người khác và chưa dùng các kết quả đọc làm bằng chứng cho media hai máy hoặc ghi DB của tính năng mới.
- Chrome DevTools 375×667: login → danh sách chat/người nhận → AI digest → hỏi AI. POST tạo hội thoại/ask và GET đọc lại hội thoại đều 200; hội thoại đã lưu trên BE. Mô hình trả FALLBACK/tạm không khả dụng, app hiển thị đúng nội dung và giới hạn BE trả về; không khẳng định chất lượng sinh nội dung AI. Console không có warning/error trong các luồng đã xem.
- Sửa ánh xạ evidence dùng ID có tiền tố TASK-/MS-/PR-/MTG- đúng contract BE để mở màn có kiểm tra quyền; nguồn không được hỗ trợ giữ dạng tham chiếu đọc.

Không có Android SDK/emulator tại máy Windows này; iOS cần macOS/Xcode. External push, SignalR và screenshare/recording chưa được triển khai. Phạm vi và các endpoint ở [MOBILE_COLLABORATION.md](MOBILE_COLLABORATION.md).

## Soạn công việc và công cụ AI 0.4.0 — 16/11/2026

Baseline `0018acf`, nhánh `feat/mobile-task-authoring`; contract BE `9eedf9a`, không đổi dependency hoặc native permission.

- Tạo task theo `create_task`; yêu cầu mốc trong đồ án, ngành thuộc frozen registration snapshot/major requirements; công việc liên ngành cần một ngành chính. Chọn người phụ trách từ thành viên BE, gửi deadline UTC.
- Sửa nội dung/deadline theo `update_task`, phân công riêng theo `assign_task`; đọc lại capability trước khi ghi. Giữ parentTaskId, không đưa assignee/discipline vào PUT nội dung. 409 khóa lưu đến khi tải authority mới, giữ bản đang soạn để đối chiếu; create không rõ kết quả không tự gửi lại.
- Danh sách chuyển được giữa việc của tôi/toàn đồ án; tạo thành công quay về danh sách toàn đồ án để không làm mất dấu task mới chưa phân công cho mình.
- AI có PROGRESS/TASK; PROGRESS dùng dữ liệu BE, bản nháp TASK mở trình soạn có kiểm tra quyền và kiểm tra thủ công trước khi tạo. Mode học vụ không gửi công cụ chỉ dùng cho đồ án.
- Format/analyze đạt; 32 tests đạt. Kiểm tra mới gồm phạm vi ngành đã xác minh, bản nháp cần ngành chính, payload UTC/phân công, conflict giữ draft và parentTaskId, không ghi đè phân công, công cụ PROGRESS đọc lại hội thoại đã lưu. Các flow auth/chat/call/workspace cũ vẫn đạt.
- API staging thật: login/dashboard/project capability/major requirements 200. Test account `create_task=false`; không thực hiện ghi task bằng tài khoản không có quyền. Project có frozen interdisciplinary scope, requirements rỗng được đối chiếu với frozen scope như web/BE.
- POST assistant với `toolMode=PROGRESS` trả 200, `generationStatus=COMPLETED`, `answerType=GROUNDED` và evidence thật. Đây là công cụ dữ liệu hệ thống, không phải bằng chứng mô hình hỏi tự do đã phục hồi; chưa đổi cấu hình provider BE.

Web release staging và APK được kiểm tra tại CI của PR trước merge. Kết quả native/runtime/iOS còn theo dõi riêng; không gửi tin nhắn cho người khác để kiểm tra task.
