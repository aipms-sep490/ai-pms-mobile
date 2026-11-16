# Mobile 0.3.0 — chat, call và AI

Baseline mobile `797c022`; contract BE develop `9eedf9a`; API staging qua `config/staging.json`. Mobile gọi API có xác thực, dùng chung dữ liệu với web; không nối DB trực tiếp. Không có dữ liệu mẫu thay thế trong runtime.

## Trò chuyện

- Danh sách cuộc trò chuyện/người nhận/thành viên dùng cursor BE. Mở direct hoặc nhóm/team/project bằng API hiện hành.
- Tin nhắn giữ ID/sequence 64-bit dưới dạng chuỗi; sắp xếp bằng BigInt, hợp nhất trang theo ID. Trả lời, sửa/thu hồi dùng capability và concurrency token; retry gửi cùng nội dung giữ clientMessageId để BE chống trùng.
- Tải tệp theo chính sách `/upload-policies/CHAT_ATTACHMENT` (hiện 11 MiB/tệp); tải xuống qua API có xác thực rồi lưu bằng trình chọn tệp hệ điều hành. Không dùng URL tải riêng tư làm external link.
- Trạng thái đọc, reaction thích, mute 8 giờ/bật lại, tóm tắt AI. Không tự gửi tin nhắn khi chỉ mở danh sách.
- Trong hội thoại đang mở: kiểm tra version mỗi 4 giây, chỉ tải lại khi thay đổi, dừng polling khi app vào background/route khác; 429 lùi 30 giây. Đây là REST polling, chưa phải SignalR hoặc push khi app đóng.

## Phòng họp

- Từ chi tiết lịch có `IN_APP_VIDEO`: GET `/meetings/{id}/video/session`; các nút dựa vào canStart/canJoin/canEnd và lý do BE trả về.
- POST start/join/end đúng thao tác người dùng. Join credential LIVEKIT chỉ tồn tại trong request/phiên SDK; kiểm tra URL HTTPS/WSS, thời hạn và capability trước kết nối.
- LiveKit Flutter 2.13.2: video người tham gia, mic/camera mặc định tắt, bật/tắt sau khi tham gia, phát âm thanh, SDK reconnect và rời phòng. Rời/back/logout giải phóng media; rời phòng không kết thúc phòng cho người khác. Kết thúc tất cả cần quyền và xác nhận.
- Android có quyền camera/audio/network; iOS có mô tả camera/micro và audio background. Chưa nghiệm thu native Bluetooth/audio routing, chia sẻ màn hình, ghi hình hoặc cuộc gọi đến khi app đóng. Không hiển thị nút giả cho các phần này.

## AI và kết quả

- `/academic/assistant`: hội thoại lưu cùng web, scope ACADEMIC/PROJECT/COMBINED; expectedRevision xử lý thay đổi đồng thời. Hỏi tối đa 2000 ký tự; mobile hỗ trợ một tệp PDF/DOCX/TXT/MD tối đa 10 MiB cho mỗi lượt.
- Citation mở lại snapshot qua API có quyền; evidence chỉ điều hướng các entity được hỗ trợ, kiểm tra lại quyền ở màn đích. Bản gợi ý có thể sao chép, chưa tự tạo task/report/meeting.
- Digest/rủi ro, workflow NEXT_STEPS/BLOCKERS/SUBMISSION_CHECK/MEETING_BRIEF; tóm tắt báo cáo/chat; lịch sử AI run và yêu cầu phân tích tiến độ mới. Hiển thị thiếu dữ liệu/thất bại, không biến dữ liệu thiếu thành 0.
- GET `/projects/{id}/result` chỉ xem kết quả công bố. 404 sau khi xác minh quyền project được hiển thị là chưa có kết quả; không tính điểm/công bố tại app.

## Phạm vi còn lại

Từ 0.4.0, gợi ý TASK có thể mở form tạo công việc để đối chiếu mốc/ngành/người phụ trách và lưu theo quyền. Hội thoại có công cụ PROGRESS (dữ liệu tiến độ BE) và TASK (yêu cầu bản nháp); không tự lưu mutation từ AI.

External push, SignalR foreground thay polling, AI streaming, nhiều tệp trong một lượt AI, áp dụng gợi ý report/meeting, screenshare/recording và feature parity của các form dài trên web chưa nằm trong bản này. Xem validation để phân biệt phần đã build với luồng đã chạy thật.
