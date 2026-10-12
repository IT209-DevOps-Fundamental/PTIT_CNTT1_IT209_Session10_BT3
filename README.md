# BÀI 3: TỐI ƯU HÓA DUNG LƯỢNG IMAGE & LAYER CACHING VỚI MULTI-STAGE BUILD

---

## 1. Mục tiêu & Bối cảnh

Trong môi trường triển khai Production, việc duy trì một Docker Image cồng kềnh chứa đầy công cụ biên dịch (compilers, build tools, package manager cache, devDependencies) gây ra nhiều vấn đề nghiêm trọng:
- **Lãng phí băng thông & thời gian deploy:** Kéo dài thời gian CI/CD khi kéo (pull) và đẩy (push) image lên Docker Registry.
- **Tăng bề mặt tấn công (Attack Surface):** Các gói phần mềm, tiện ích hệ thống thừa thãi làm tăng nguy cơ tồn tại lỗ hổng bảo mật (CVEs).
- **Lãng phí dung lượng đĩa cứng máy chủ:** Hạn chế số lượng container có thể chạy đồng thời trên cùng một node.

Kỹ thuật **Multi-stage Build** giải quyết bài toán này bằng cách chia quy trình đóng gói thành nhiều giai đoạn:
1. **Stage 1 (Builder):** Dùng để cài đặt dependencies, biên dịch mã nguồn, chạy build tool.
2. **Stage 2 (Runtime):** Sử dụng một base image runtime tối giản (Alpine Linux), chỉ sao chép kết quả đã biên dịch từ Stage 1 sang (`COPY --from=builder`). Toàn bộ file rác, npm cache, công cụ build ở Stage 1 sẽ bị loại bỏ hoàn toàn khỏi image cuối cùng.

---

## 2. Cấu trúc thư mục

```
BT3/
├── Dockerfile          # Multi-stage Dockerfile (Tối ưu cho Production)
├── Dockerfile.single   # Single-stage Dockerfile (Dùng để đối chiếu, so sánh)
├── .dockerignore       # Loại trừ node_modules, log, git
├── package.json        # Định nghĩa dependencies (Express)
├── server.js           # Mã nguồn REST API
└── README.md           # Báo cáo so sánh dung lượng, layer và kiểm thử
```

---

## 3. So sánh kiến trúc hai Dockerfile

### 3.1. Single-stage Build (`Dockerfile.single`)
```dockerfile
# Single-stage Dockerfile: Sử dụng base image tiêu chuẩn, không tách biệt môi trường build
FROM node:18-slim

WORKDIR /app

# Copy toàn bộ mã nguồn trước khi cài đặt dependencies
COPY . .

# Chạy npm install: Lưu lại toàn bộ npm cache và build metadata vào image
RUN npm install

EXPOSE 3000

CMD ["node", "server.js"]
```
- **Nhược điểm:** 
  - Toàn bộ cache của npm (`~/.npm`) và file thừa bị lưu chết vào layer của Docker Image.
  - Sử dụng base image lớn hơn (`node:18-slim` dựa trên Debian).
  - Không tận dụng được cache layer: bất kỳ thay đổi nào trong mã nguồn đều kích hoạt lại bước `npm install`.

---

### 3.2. Multi-stage Build (`Dockerfile`)
```dockerfile
# ==========================================
# Giai đoạn 1: Builder stage
# ==========================================
FROM node:18-alpine AS builder

WORKDIR /app

# Tận dụng Build Cache: copy file package*.json trước
COPY package*.json ./

# Cài đặt dependencies trong môi trường builder
RUN npm install

# Copy toàn bộ mã nguồn
COPY . .

# ==========================================
# Giai đoạn 2: Runtime stage siêu nhẹ
# ==========================================
FROM node:18-alpine

WORKDIR /app

# Thiết lập môi trường Production và cổng ứng dụng
ENV NODE_ENV=production
ENV PORT=3000

# Chỉ trích xuất các tệp cần thiết từ builder stage, bỏ qua hoàn toàn npm cache
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/server.js ./

EXPOSE 3000

CMD ["node", "server.js"]
```
- **Ưu điểm vượt trội:**
  - **Tách biệt môi trường:** Runtime image hoàn toàn sạch sẽ, chỉ chứa đúng runtime Node.js và thư viện cần thiết.
  - **Tối ưu Layer Caching:** Tách riêng `COPY package*.json` giúp Docker cache layer `npm install`.
  - **Giảm dung lượng:** Base Alpine chỉ chiếm ~8.5MB OS rootfs so với ~85MB của Debian.

---

## 4. Bảng so sánh chi tiết: Single-stage vs Multi-stage

Dựa trên kết quả build thực tế từ Docker Engine trên hệ thống:

| Tiêu chí | Single-stage (`hw-backend:single`) | Multi-stage (`hw-backend:multistage`) | Đánh giá & Tác động |
| :--- | :--- | :--- | :--- |
| **Base Image** | `node:18-slim` (Debian Bookworm) | `node:18-alpine` (Alpine Linux) | Alpine tối giản hơn 10 lần ở tầng OS gốc. |
| **Disk Usage (Uncompressed)** | **294 MB** | **186 MB** | Giảm **108 MB (~37%)** dung lượng đĩa cứng cục bộ. |
| **Content Size (Compressed)** | **70.6 MB** | **45.6 MB** | Giảm **~36%** kích thước nén, đạt chuẩn **dưới 50MB** (< 100MB). |
| **Base OS Rootfs Size** | ~85.2 MB | ~8.5 MB | Giảm **90%** dung lượng hệ điều hành nền. |
| **Layer phát sinh ứng dụng** | 4 layers (gồm cả layer `RUN npm install` nặng 12.8MB) | 3 layers nhỏ (chỉ copy file kết quả: 45KB + 4.67MB + 12KB) | Không còn layer npm install cồng kềnh trong runtime image. |
| **Bảo mật (Attack Surface)** | Còn chứa package manager & build artifacts | Loại bỏ hoàn toàn công cụ build, file tạm và cache | Giảm thiểu tối đa số lượng CVE tiềm ẩn. |
| **Tốc độ Re-build khi đổi code** | Chậm (phải chạy lại `npm install` nếu code đổi) | Tức thì (tận dụng layer cache cho `package.json`) | Tiết kiệm thời gian đóng gói trong pipeline CI/CD. |

---

## 5. Nhật ký kiểm thử & Bằng chứng thực nghiệm

### 5.1. Build cả hai image
```bash
# Build single-stage
docker build -f Dockerfile.single -t hw-backend:single .

# Build multi-stage
docker build -t hw-backend:multistage .
```

### 5.2. Kiểm tra danh sách image (`docker images | grep hw-backend`)
```text
REPOSITORY              TAG          IMAGE ID       DISK USAGE   CONTENT SIZE
hw-backend              multistage   c719d4c2293f   186MB        45.6MB
hw-backend              single       d4e93eec9125   294MB        70.6MB
```

### 5.3. Khởi chạy và kiểm tra Container Multi-stage
```bash
docker run -d --name app-multistage -p 8081:3000 hw-backend:multistage
```

Kiểm tra trạng thái qua `docker ps`:
```text
CONTAINER ID   IMAGE                   STATUS         PORTS                                         NAMES
a60f7a57b11d   hw-backend:multistage   Up 5 seconds   0.0.0.0:8081->3000/tcp, [::]:8081->3000/tcp   app-multistage
```

### 5.4. Kiểm tra phản hồi API bằng `curl`
```bash
curl -i http://localhost:8081/
```
**Kết quả HTTP Response thực tế:**
```http
HTTP/1.1 200 OK
X-Powered-By: Express
Content-Type: application/json; charset=utf-8
Content-Length: 96
ETag: W/"60-e4Ck7KIw0k6baNO3oCViNvn9+HY"
Date: Mon, 12 Oct 2026 01:08:05 GMT
Connection: keep-alive
Keep-Alive: timeout=5

{"status":"success","message":"Hello from Docker Multi-stage Build!","environment":"production"}
```

### 5.5. Phân tích chi tiết Layer (`docker history`)

#### Multi-stage Image (`hw-backend:multistage`):
```text
IMAGE          CREATED         CREATED BY                                      SIZE      COMMENT
c719d4c2293f   1 minute ago    CMD ["node" "server.js"]                        0B        buildkit.dockerfile.v0
<missing>      1 minute ago    EXPOSE [3000/tcp]                               0B        buildkit.dockerfile.v0
<missing>      1 minute ago    COPY /app/server.js ./ # buildkit               12.3kB    buildkit.dockerfile.v0
<missing>      1 minute ago    COPY /app/node_modules ./node_modules # buil…   4.67MB    buildkit.dockerfile.v0
<missing>      1 minute ago    COPY /app/package*.json ./ # buildkit           45.1kB    buildkit.dockerfile.v0
<missing>      1 minute ago    ENV PORT=3000                                   0B        buildkit.dockerfile.v0
<missing>      1 minute ago    ENV NODE_ENV=production                         0B        buildkit.dockerfile.v0
<missing>      1 minute ago    WORKDIR /app                                    8.19kB    buildkit.dockerfile.v0
```
> **Nhận xét:** Trong runtime image chỉ xuất hiện 3 lệnh `COPY` trích xuất chính xác `server.js` (12.3KB), `node_modules` (4.67MB) và `package.json` (45.1KB). Lệnh `RUN npm install` không hề để lại layer nào trong image cuối.

#### Single-stage Image (`hw-backend:single`):
```text
IMAGE          CREATED         CREATED BY                                      SIZE      COMMENT
d4e93eec9125   1 minute ago    CMD ["node" "server.js"]                        0B        buildkit.dockerfile.v0
<missing>      1 minute ago    EXPOSE [3000/tcp]                               0B        buildkit.dockerfile.v0
<missing>      1 minute ago    RUN /bin/sh -c npm install # buildkit           12.8MB    buildkit.dockerfile.v0
<missing>      1 minute ago    COPY . . # buildkit                             20.5kB    buildkit.dockerfile.v0
```
> **Nhận xét:** Layer `npm install` chiếm tới 12.8MB (chứa cả npm cache), cộng thêm base Debian cồng kềnh, làm tăng đáng kể dung lượng image.

---

## 6. Kết luận
- Kỹ thuật **Multi-stage Build** kết hợp cùng **Alpine Linux Base** đã giúp tối ưu hóa dung lượng image xuống **45.6MB** (kích thước nén) và **186MB** (kích thước đĩa), thấp hơn nhiều so với giới hạn mục tiêu 100MB nén.
- Đảm bảo tính đóng gói an toàn và sạch sẽ cho môi trường Production, sẵn sàng phục vụ triển khai CI/CD.
