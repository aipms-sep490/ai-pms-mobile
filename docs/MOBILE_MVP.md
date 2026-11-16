# MVP sinh viên 0.2.0

Mobile ưu tiên theo dõi và thao tác ngắn. Web tiếp tục phụ trách tạo kế hoạch, soạn/nộp hồ sơ và báo cáo dài, quản trị học vụ, đánh giá/công bố. Không bổ sung external push, chat, upload, offline mutation hoặc phòng video tích hợp trong phạm vi này.

## Điều hướng

Năm tab Tổng quan, Đồ án, Công việc, Hộp thư, Tài khoản. Nội dung chỉ tải khi tab được mở; giữ bộ lọc/vị trí cuộn khi đổi tab. Sau thao tác thành công, các tab đã mở được làm mới context và số liệu. Dashboard mở được project, task và milestone; hộp thư mở được tài nguyên liên quan trong các loại hỗ trợ.

Chi tiết luôn đọc lại tài nguyên qua API được xác thực. Đăng xuất, đổi tài khoản hoặc đổi vai trò sẽ hủy toàn bộ stack màn chi tiết. Vai trò khác STUDENT giữ tổng quan giải thích phạm vi và tài khoản, không tải các màn nghiệp vụ sinh viên.

## Contract

Đối chiếu snapshot `ai-pms-backend` develop `9eedf9a` ngày 16/11/2026 và endpoint staging. Tất cả đường dẫn có prefix `/api/v1`.

| Luồng | API |
| --- | --- |
| Context | `GET /dashboards/student` |
| Project/nhóm | `GET /projects/{id}`, `GET /teams/{id}` |
| Milestone | `GET /milestones/project/{projectId}`, `GET /milestones/project/{projectId}/progress`, `GET /milestones/{id}` |
| Việc của tôi | `GET /tasks/project/{projectId}` với `assigneeUserId`, `status`, `isOverdue`, `isBlocked`, `search`, `page`, `pageSize` |
| Việc trong milestone | Cùng endpoint task với `milestoneId`; kiểm tra milestone thuộc project hiện tại trước khi tải |
| Task chi tiết | `GET /tasks/{id}`, `/tasks/{id}/history`, `/tasks/{id}/execution-actions` |
| Task trạng thái | `PUT /tasks/{id}/status` với `newStatus`, `reason`, `concurrencyToken` |
| Thông báo | `GET /notifications`, `PATCH /notifications/{id}/read`, `POST /notifications/read-all` |
| Lời mời | `GET /teams/invitations`, `POST /teams/invitations/{id}/accept` hoặc `/reject` |
| Lịch | `GET /projects/{projectId}/meetings`, `GET /meetings/{id}`, `GET /meetings/{id}/collaboration` |
| RSVP | `PUT /meetings/{id}/rsvp` với `status` và concurrency token của `myRsvp` |
| Báo cáo/phản hồi | `GET /projects/{projectId}/progress-reports`, `GET /progress-reports/{id}` |

Danh sách phân trang dùng page/pageSize/totalCount/totalPages từ BE; milestone là mảng. Không chặn số mục ở trang đầu hoặc tự tạo số liệu giả. Thời gian DateTime được diễn giải UTC rồi hiển thị theo thiết bị; DateOnly giữ nguyên ngày. Dashboard hiện hữu vẫn ghi rõ giờ Việt Nam.

## Quyền và cập nhật

- Task chỉ hiện thao tác khi capability `change_task_status` cho phép, đúng resource/status và token khớp bản task. Danh sách chuyển trạng thái theo TaskStateMachine hiện hành; trạng thái mới chưa biết không hiện lựa chọn ghi.
- BE luôn kiểm tra lại quyền, trạng thái project, dependency và concurrency. Lỗi 409 tải lại dữ liệu/capability; không tự gửi lại mutation. Không hiển thị chi tiết lỗi/provider/DB từ ProblemDetails.
- Khi đang gửi, khóa thao tác lặp; task/RSVP chặn back trong lúc gửi. Lời mời có xác nhận trong app và chỉ hiện thao tác với PENDING, đúng người nhận. Hết hiệu lực/mất quyền được BE từ chối và app tải lại.
- RSVP dùng token của người tham gia, không dùng token meeting. Chỉ có lựa chọn khi người dùng nằm trong `myRsvp`, project ACTIVE và meeting SCHEDULED.
- Link ngoài chỉ nhận HTTP(S), có host, không chứa userInfo; không gửi bearer token sang link. Dùng plugin chính thức [url_launcher](https://pub.dev/packages/url_launcher); link vẫn có thể chọn/sao chép nếu mở thất bại. IN_APP_VIDEO hướng người dùng sang web.
- Notification chỉ điều hướng các loại TASK, PROJECT, MILESTONE, MEETING, PROGRESS_REPORT, TEAM/TEAM_INVITATION có ID hợp lệ. Loại còn lại đọc nội dung, không tự mở URL tùy ý.
- Lỗi mạng giữ dữ liệu cũ kèm thông báo; lỗi 401/403/404 xóa nội dung tài nguyên. Sau mutation, xóa snapshot cũ trước khi tải lại để không dùng lại capability/token vừa thất bại.

## Nghiệm thu còn cần thiết

Web/API đọc thật và test HTTP mock không thay thế nghiệm thu mutation trên dữ liệu thử riêng, thiết bị Android/iOS, secure storage, restart/resume, bàn phím và liên kết ngoài. Các kết quả cụ thể được ghi trong FLUTTER_VALIDATION.md. APK staging là debug build, chưa ký phát hành store.
