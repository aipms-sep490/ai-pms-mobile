# Hướng dẫn Đóng gói APK & Phát hành AI-PMS Mobile lên Google Play (CH Play)

Tài liệu này tổng hợp toàn bộ quy trình phát hành bản Release đã ký số cho ứng dụng **AI-PMS Mobile** (`vn.edu.aipms.ai_pms_mobile`).

---

## 1. Quy trình tự động xuất APK & AAB bằng GitHub Actions

Workflow `.github/workflows/release-android.yml` hỗ trợ xuất đồng thời:
- `ai-pms-v<version>-arm64-v8a-release.apk` — **Khuyên dùng** cài trực tiếp lên điện thoại Android 64-bit hiện đại (nhẹ hơn ~40–50%).
- `ai-pms-v<version>-universal-release.apk` — Cài được trên mọi máy Android.
- `ai-pms-v<version>-release.aab` — Gói **Android App Bundle** chuẩn để tải lên **Google Play Console**.
- `SHA256SUMS.txt` — Mã kiểm toàn vẹn tệp.

### Cách kích hoạt bản phát hành mới
1. Nâng `version` trong `pubspec.yaml` (ví dụ `1.0.0+8` → `1.0.1+9` — **bắt buộc tăng số sau dấu `+` (`versionCode`) cho mỗi lần nộp CH Play**).
2. Vào GitHub Repo → **Actions** → **Android Release (APK & Play Store AAB)** → bấm **Run workflow** (chọn `staging` hoặc `production`), **hoặc** push tag `v1.0.1`:
   ```powershell
   git tag v1.0.1
   git push origin v1.0.1
   ```
3. Sau ~6–9 phút, tải file `.apk` / `.aab` tại mục **Releases** của GitHub hoặc trong Artifact của workflow run.

---

## 2. Cấu hình Google Sign-In cho Android APK thật

Để nút **"Đăng nhập bằng Google"** chạy trên điện thoại Android (đăng nhập Email/Mật khẩu luôn chạy bình thường không cần bước này):

1. Vào **Google Cloud Console** → đúng project đang chứa Web OAuth Client ID của AI-PMS.
2. Chọn **APIs & Services → Credentials → + Create Credentials → OAuth client ID**.
3. Chọn **Application type: Android**:
   - **Package name:** `vn.edu.aipms.ai_pms_mobile`
   - **SHA-1 certificate fingerprint:** dán mã SHA-1 của Upload Keystore *(và thêm 1 Android Client ID nữa với SHA-1 của App Signing key sau khi bật Play App Signing trên Google Play Console)*.
4. Copy **Android Client ID** vừa tạo (dạng `xxxxx.apps.googleusercontent.com`) và thêm vào mảng `GoogleAuth:AllowedAuthorizedParties` trong file cấu hình Backend (`appsettings.Staging.json` / Production), sau đó khởi động lại container `aipms-api`.

---

## 3. Bộ hồ sơ nộp lên Google Play Console (CH Play)

### A. Tạo ứng dụng mới
- **App name:** `AI-PMS — Quản lý Đồ án` (tối đa 30 ký tự)
- **Default language:** `Vietnamese (vi-VN)` (có thể thêm bản dịch `English (en-US)`)
- **App or game:** `App` · **Free or paid:** `Free`
- **Package ID (khóa vĩnh viễn theo AAB):** `vn.edu.aipms.ai_pms_mobile`

### B. Các đường dẫn bắt buộc
- **Privacy Policy URL:** `https://aipims.khaidz.com/privacy.html`
- **Account Deletion URL:** `https://aipims.khaidz.com/privacy.html#account-deletion`

### C. Bảng khai báo Data Safety (An toàn dữ liệu)
| Loại dữ liệu | Có thu thập? | Mục đích | Mã hóa khi truyền? | Chia sẻ bên thứ 3? |
| :--- | :---: | :--- | :---: | :---: |
| Name, Email address, User IDs | Có | App functionality, Account management | Có (HTTPS) | Không bán / không quảng cáo |
| Photos & Files (khi người dùng tự chọn upload) | Tùy chọn | App functionality (đính kèm chat/báo cáo/AI) | Có (HTTPS) | Không |
| Audio / Video (LiveKit video meeting) | Tùy chọn (tạm thời) | App functionality (họp nhóm trực tuyến) | Có (WSS/WebRTC) | Không |
| App interactions / Messages | Có | App functionality (chat, tiến độ, AI) | Có (HTTPS/WSS) | Không |

### D. Khai báo App Access (Tài khoản kiểm duyệt cho Google Reviewer)
Vì ứng dụng yêu cầu đăng nhập, **BẮT BUỘC** chọn **"All or some functionality is restricted"** và cung cấp 1 tài khoản demo sinh viên ổn định trong phần hướng dẫn cho Google Reviewer để tránh bị từ chối kiểm duyệt.

### E. Tài sản đồ họa & Mô tả Store Listing
- **App Icon (512×512 PNG):** `store-assets/play-store/app-icon-512x512.png`
- **Feature Graphic (1024×500 PNG):** `store-assets/play-store/feature-graphic-1024x500.png`
- **Screenshots:** Chụp tối thiểu 2–4 ảnh màn hình điện thoại thật sau khi cài APK (Đăng nhập, Tổng quan đồ án, Công việc, Trợ lý AI / Chat).
- **Mô tả ngắn (≤ 80 ký tự):**
  > Theo dõi đồ án tốt nghiệp, công việc, họp nhóm và Trợ lý AI học vụ mọi lúc.
- **Mô tả chi tiết gợi ý:**
  > **AI-PMS Mobile** là ứng dụng đồng hành dành cho sinh viên, trưởng nhóm và giảng viên hướng dẫn trên nền tảng Quản lý Đồ án Tốt nghiệp AI-PMS.
  >
  > **Tính năng nổi bật:**
  > - **Theo dõi tiến độ & Việc cần làm ngay:** Xem mốc đồ án, hạn công việc, lịch tổng hợp và các mục ưu tiên cần xử lý.
  > - **Quản lý công việc chuẩn quy trình:** Tạo, cập nhật, phân công công việc, quản lý checklist tiêu chí, bình luận và hoàn tác nhanh.
  > - **Báo cáo tiến độ & Đánh giá chéo:** Soạn báo cáo tiến độ tuần nhanh với dữ liệu tự điền từ hệ thống, xác nhận quy ước làm việc 1 chạm.
  > - **Trao đổi nhóm & Họp video tích hợp:** Nhắn tin thời gian thực (SignalR), thông báo tức thì và tham gia phòng họp video trực tuyến ngay trong ứng dụng.
  > - **Trợ lý AI học vụ có dẫn nguồn:** Hỏi đáp quy chế học vụ, tra cứu tiến độ đồ án, soạn bản nháp công việc và nhận tóm tắt AI sau cuộc họp.
  > - **Chế độ Giảng viên hướng dẫn:** Theo dõi danh sách đồ án phụ trách, hàng chờ xử lý và phản hồi nhanh cho nhóm sinh viên.

### F. Lộ trình duyệt lên CH Play
1. **Bật Google Play App Signing** ngay lần đầu tải `.aab` lên (Google quản lý App Signing Key chính; Upload Keystore của bạn chỉ dùng để tải bản cập nhật lên Play Console).
2. Tải `ai-pms-v1.0.0-release.aab` lên track **Internal Testing** trước để mời nhóm tester cài trực tiếp từ link Play Store trong vài phút.
3. Nếu dùng tài khoản **Google Play Personal** (tạo sau 11/2023): chuyển sang **Closed Testing** với tối thiểu **12 tester opt-in liên tục 14 ngày** rồi mới mở đơn phát hành **Production**. Nếu dùng tài khoản **Organization (D-U-N-S)** thì có thể gửi duyệt Production ngay sau bước kiểm thử nội bộ.
