# ==========================================
# Giai đoạn 1: Builder stage
# ==========================================
FROM node:18-alpine AS builder

WORKDIR /app

# Copy riêng file khai báo phụ thuộc trước để tận dụng Build Cache
COPY package*.json ./

# Cài đặt toàn bộ dependencies trong môi trường builder
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

# Chỉ copy các artifact thực sự cần thiết từ builder stage
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/server.js ./

EXPOSE 3000

CMD ["node", "server.js"]
