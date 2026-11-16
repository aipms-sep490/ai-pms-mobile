# Roadmap mobile

Định hướng: **theo dõi tiến độ + thao tác nhanh**, ưu tiên Student/Team Leader. Web đảm nhiệm lập kế hoạch phức tạp, soạn hồ sơ dài, quản trị học vụ, chấm điểm và công bố. Mobile và web dùng chung backend/database.

## Tiến độ ngày 16/11/2026

MOB-04 đến MOB-08 đã có phần triển khai MVP sinh viên trong 0.2.0: project/milestone/thành viên, việc của tôi và trạng thái theo capability, lời mời, inbox, lịch/RSVP, đọc báo cáo/phản hồi. Xem [contract và giới hạn](MOBILE_MVP.md). Dashboard và các màn dùng chung backend staging; không dùng dữ liệu giả khi chạy app.

MOB-03A đã kiểm tra luồng web với staging; nghiệm thu native secure storage/restart và mutation trên bộ dữ liệu thử riêng còn cần thiết. MOB-09 còn nghiệm thu thiết bị Android/iOS, external deep link/OS lifecycle và bản phát hành ký. CI đóng gói debug APK trỏ staging để hỗ trợ bước này. Không đánh dấu toàn bộ sản phẩm đạt production chỉ từ test/build.

## MOB-03 — Nền tảng Flutter

Nền tảng chuyển sang **Flutter/Dart** theo lựa chọn của người dùng: cấu hình API origin qua `API_BASE_URL`, auth/session, hai tab Tổng quan/Tài khoản, dashboard theo contract backend, setup và CI. Xem [quyết định chuyển đổi](FLUTTER_MIGRATION.md) và [validation Flutter](FLUTTER_VALIDATION.md).

## MOB-03A — Nghiệm thu tích hợp trước khi mở rộng

Kết nối với môi trường backend/database thật được phép dùng, bằng tài khoản sinh viên thử nghiệm. Kiểm tra login → `/auth/me` → dashboard, refresh khi hết access token, mở lại app, logout và dữ liệu/quyền bị thay đổi. Chạy trên Android/emulator hoặc thiết bị mục tiêu, xác minh secure storage, safe area, bàn phím và mạng. Ghi môi trường, thiết bị, kết quả và bằng chứng đã che dữ liệu nhạy cảm. Mock/unit/widget test và build không thay thế mốc này.

## Các bước tiếp theo

| Task | Nội dung | Điều kiện hoàn thành |
| --- | --- | --- |
| **MOB-04 — Project và milestone** | Project hiện tại, trạng thái, GVHD, thành viên, milestone và tiến độ | Dùng contract hiện hành; xử lý chưa có team/project, mất quyền, lỗi và làm mới; không hiển thị project ngoài phạm vi |
| **MOB-05 — Việc của tôi** | Danh sách/chi tiết task, deadline, quá hạn, bị chặn; cập nhật trạng thái | Lấy capability từ backend; gửi concurrency token; stale state trả 409 phải làm mới; thay đổi hiển thị được trên web |
| **MOB-06 — Lời mời nhóm** | Danh sách lời mời, nhận/từ chối | Theo đúng trạng thái và quyền API; chống gửi lặp; xử lý lời mời hết hiệu lực; team/context được cập nhật sau thành công |
| **MOB-07 — Inbox thông báo** | Chưa đọc/đã đọc, đọc tất cả, điều hướng về đối tượng | Đúng người nhận, trạng thái đọc được lưu; điểm đến kiểm tra lại quyền khi mở; không nhầm inbox với external push |
| **MOB-08 — Lịch và phản hồi** | Xem lịch họp, liên kết tham gia, report và feedback; RSVP nếu contract phù hợp | Hiển thị giờ theo thiết bị, đúng quyền và trạng thái; đọc được nội dung dài; kiểm thử liên kết và RSVP trên thiết bị |
| **MOB-09 — Hoàn thiện bản thử nghiệm** | UX, mạng yếu, bàn phím, accessibility, đóng gói thử | Smoke test Android/iOS mục tiêu; kiểm tra hết phiên, logout, khởi động lại, back/deep link và dữ liệu bị sửa đồng thời; ghi thiết bị và bằng chứng |

Thực hiện MOB-03A trước MOB-04/MOB-05. Mỗi task là một nhánh/PR có thể review vào `develop`. Kiểm tra lại contract và API triển khai trước khi bắt đầu; kế hoạch nghiên cứu cũ từng ghi Report/Meeting chưa có controller, nhưng hiện backend đã có các controller này.

## Sau MVP

- **Supervisor:** project đang hướng dẫn, nhóm cần chú ý, lịch và đọc/viết phản hồi ngắn. Đối chiếu lại phạm vi với SRS vì bảng actor ghi Web/Responsive, còn external interface nhắc selected supervisor journeys. SRS còn ghi React Native và cần đồng bộ quyết định Flutter; task này không tự sửa tài liệu ở repo docs.
- **Kết quả đã công bố và cảnh báo AI:** chỉ hiển thị thông tin trong quyền; giữ thuật toán và thời điểm công bố ở backend.
- **External push:** task riêng cho backend lẫn app, gồm đăng ký/thu hồi device token, provider delivery, quyền thông báo, mở đúng màn hình và kiểm thử foreground/background/app đóng. Không cam kết push chỉ bằng việc bổ sung màn hình inbox.
- **Chat, upload và video:** đánh giá nhu cầu trước khi mở phạm vi; kiểm thử mạng, file, quyền và vòng đời app. Chưa đặt offline mutation vào MVP.

## Mốc nghiệm thu

Luồng đầu tiên trên Flutter: đăng nhập → dashboard từ backend/database thật → mở lại app → khôi phục phiên hoặc xử lý hết phiên đúng → đăng xuất. Ghi trạng thái nghiệm thu riêng với kết quả test/build.

Sau MOB-04 đến MOB-08: xem việc sắp đến hạn → mở task → đổi trạng thái theo capability → web thấy thay đổi → đọc feedback/lịch/thông báo. Không dùng dữ liệu giả để thay cho backend chưa kết nối.
