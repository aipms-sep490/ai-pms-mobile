# AI-PMS Mobile

Ứng dụng đồng hành cho sinh viên và trưởng nhóm: theo dõi đồ án, hạn công việc và thông tin học vụ trên điện thoại. Mobile dùng chung API và dữ liệu với AI-PMS Web.

Nền tảng ban đầu sử dụng **React Native, Expo SDK 58, TypeScript và Expo Router**. `develop` là nhánh mặc định và nhánh tích hợp; phát triển từng tính năng trên nhánh riêng, mở PR vào `develop`.

## Phạm vi hiện tại

- Đăng nhập bằng tài khoản AI-PMS hiện có, khôi phục phiên và đăng xuất.
- Native lưu refresh token bằng Expo SecureStore; access token giữ trong bộ nhớ. Web preview chỉ giữ phiên trong bộ nhớ.
- Hai tab hoạt động: **Tổng quan** và **Tài khoản**.
- Tổng quan lấy dữ liệu thật từ `GET /api/v1/dashboards/student`, có trạng thái tải, lỗi, thử lại và làm mới.
- Phạm vi chức năng ưu tiên tài khoản `STUDENT`. Tài khoản vai trò khác nhận thông báo về phạm vi hỗ trợ; backend vẫn quyết định quyền truy cập.

Các màn hình quản lý project/task đầy đủ và thao tác nhanh sẽ được triển khai theo [roadmap](docs/MOBILE_ROADMAP.md). Không có dữ liệu demo hoặc backend riêng cho mobile.

## Chạy lần đầu

Cần **Node.js 24** (từ 24.3.0), npm và một API AI-PMS có thể truy cập. `package-lock.json` khóa các dependency của dự án.

```powershell
git clone https://github.com/aipms-sep490/ai-pms-mobile.git
cd ai-pms-mobile
git switch develop
npm ci
Copy-Item .env.example .env.local
```

Sửa `EXPO_PUBLIC_API_URL` trong `.env.local` thành **origin của API**, không thêm `/api/v1`:

| Thiết bị chạy app | Ví dụ API origin |
| --- | --- |
| Web preview trên máy chạy backend | `http://localhost:5080` |
| Android emulator mặc định | `http://10.0.2.2:5080` |
| Điện thoại thật | IP LAN có thể truy cập của máy chạy backend hoặc URL HTTPS của môi trường dùng thử |

Điện thoại cần kết nối được API trực tiếp. Với LAN, backend phải lắng nghe trên địa chỉ phù hợp và firewall cho phép cổng đó. `localhost` trên điện thoại trỏ về chính điện thoại. Chỉ dùng HTTP với môi trường phát triển tin cậy; môi trường triển khai dùng HTTPS.

```powershell
npm start
```

Mở app bằng Expo Go tương thích SDK hoặc development build. Có thể dùng `npm run android` với Android emulator đã cấu hình, hoặc `npm run web` để xem trên trình duyệt. iOS Simulator cần macOS; Windows có thể chạy Metro và kết nối iPhone phù hợp qua Expo Go/development build.

Web preview cần backend cho phép CORS đối với origin trình duyệt mà Expo hiển thị. Sau khi đổi API origin, khởi động lại Metro; nếu giá trị chưa đổi, chạy `npm start -- --clear`.

## Kiểm tra trước PR

```powershell
npm run check
npx expo install --check
npx expo-doctor
npx expo export --platform all
```

`check` chạy TypeScript, lint và các test logic. Export kiểm tra việc đóng gói JavaScript/assets cho các nền tảng; không thay thế kiểm thử trên thiết bị hoặc tạo APK/IPA đã ký.

GitHub Actions chạy kiểm tra và export khi có PR vào `develop` hoặc push lên `develop`. CI không cần tài khoản Expo hay secret backend và không tự phát hành app.

## Cấu hình và phiên đăng nhập

- Mọi biến `EXPO_PUBLIC_*` được đóng gói vào app và có thể đọc được. Chỉ đặt cấu hình công khai, không đặt mật khẩu, JWT signing key, private key hoặc service credential.
- `.env.local`, token và tài khoản thử nghiệm không được commit. Dùng tài khoản do môi trường backend cấp.
- Các endpoint dùng chung: `/api/v1/auth/login`, `/refresh`, `/me`, `/logout` và `/api/v1/dashboards/student`.
- Quyền, phạm vi nhóm/project và trạng thái nghiệp vụ do backend kiểm soát. Không suy quyền từ giao diện hoặc tự tính lại chính sách học vụ.
- Web preview đăng nhập lại sau khi reload. Native dùng secure storage cho refresh token; không lưu mật khẩu.

## Làm việc với Git

```powershell
git switch develop
git pull --ff-only origin develop
git switch -c feat/ten-tinh-nang
# Triển khai, kiểm tra, commit
git push -u origin feat/ten-tinh-nang
```

Mở PR với base **`develop`**, kiểm tra CI và review trước khi merge. Không code, push hoặc merge tính năng vào `main`.

## Giới hạn bản nền tảng

Chưa cấu hình tài khoản EAS, signing, store release hoặc bản APK/IPA. Native runtime, secure storage, điều hướng, bàn phím và kết nối API cần smoke test trên thiết bị mục tiêu trước phát hành. Thông báo trong hệ thống và push khi app đóng là hai hạng mục riêng; backend hiện chưa có external push delivery.
