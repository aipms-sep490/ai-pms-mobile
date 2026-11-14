# Roadmap mobile

Định hướng: **theo dõi tiến độ + thao tác nhanh**, ưu tiên Student/Team Leader. Web đảm nhiệm lập kế hoạch phức tạp, soạn hồ sơ dài, quản trị học vụ, chấm điểm và công bố. Mobile và web dùng chung backend/database.

## MOB-03 — Nền tảng

Phạm vi của đợt khởi tạo: Expo + TypeScript + Router, cấu hình API origin, auth/session, hai tab Tổng quan/Tài khoản, dashboard sinh viên lấy dữ liệu thật, hướng dẫn setup và CI. Các kiểm tra chạy trong PR; thiết bị thật và API triển khai cần được xác minh riêng.

## Các bước tiếp theo

| Task | Nội dung | Điều kiện hoàn thành |
| --- | --- | --- |
| **MOB-04 — Project và milestone** | Project hiện tại, trạng thái, GVHD, thành viên, milestone và tiến độ | Dùng contract hiện hành; xử lý chưa có team/project, mất quyền, lỗi và làm mới; không hiển thị project ngoài phạm vi |
| **MOB-05 — Việc của tôi** | Danh sách/chi tiết task, deadline, quá hạn, bị chặn; cập nhật trạng thái | Lấy capability từ backend; gửi concurrency token; stale state trả 409 phải làm mới; thay đổi hiển thị được trên web |
| **MOB-06 — Lời mời nhóm** | Danh sách lời mời, nhận/từ chối | Theo đúng trạng thái và quyền API; chống gửi lặp; xử lý lời mời hết hiệu lực; team/context được cập nhật sau thành công |
| **MOB-07 — Inbox thông báo** | Chưa đọc/đã đọc, đọc tất cả, điều hướng về đối tượng | Đúng người nhận, trạng thái đọc được lưu; điểm đến kiểm tra lại quyền khi mở; không nhầm inbox với external push |
| **MOB-08 — Lịch và phản hồi** | Xem lịch họp, liên kết tham gia, report và feedback; RSVP nếu contract phù hợp | Hiển thị giờ theo thiết bị, đúng quyền và trạng thái; đọc được nội dung dài; kiểm thử liên kết và RSVP trên thiết bị |
| **MOB-09 — Hoàn thiện bản thử nghiệm** | UX, mạng yếu, bàn phím, accessibility, đóng gói thử | Smoke test Android/iOS mục tiêu; kiểm tra hết phiên, logout, khởi động lại, back/deep link và dữ liệu bị sửa đồng thời; ghi thiết bị và bằng chứng |

Mỗi task là một nhánh/PR có thể review vào `develop`. Kiểm tra lại contract và API triển khai trước khi bắt đầu; kế hoạch nghiên cứu cũ từng ghi Report/Meeting chưa có controller, nhưng hiện backend đã có các controller này.

## Sau MVP

- **Supervisor:** project đang hướng dẫn, nhóm cần chú ý, lịch và đọc/viết phản hồi ngắn. Chốt lại phạm vi với SRS vì bảng actor ghi Web/Responsive, còn external interface có nhắc selected supervisor journeys.
- **Kết quả đã công bố và cảnh báo AI:** chỉ hiển thị thông tin trong quyền; giữ thuật toán và thời điểm công bố ở backend.
- **External push:** task riêng cho backend lẫn app, gồm đăng ký/thu hồi device token, provider delivery, quyền thông báo, mở đúng màn hình và kiểm thử foreground/background/app đóng. Không cam kết push chỉ bằng việc bổ sung màn hình inbox.
- **Chat, upload và video:** đánh giá nhu cầu trước khi mở phạm vi; kiểm thử mạng, file, quyền và vòng đời app. Chưa đặt offline mutation vào MVP.

## Mốc nghiệm thu

Luồng đầu tiên: đăng nhập → xem dashboard dữ liệu thật → mở lại app → khôi phục phiên hoặc xử lý hết phiên đúng → đăng xuất.

Sau MOB-04 đến MOB-08: xem việc sắp đến hạn → mở task → đổi trạng thái theo capability → web thấy thay đổi → đọc feedback/lịch/thông báo. Không dùng dữ liệu giả để thay cho backend chưa kết nối.
