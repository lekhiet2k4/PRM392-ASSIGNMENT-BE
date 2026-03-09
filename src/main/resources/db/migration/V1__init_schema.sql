-- ============================================================
-- La Vela Pool Booking — Initial Schema
-- TiDB (MySQL-compatible)
-- Migration: V1__init_schema.sql
-- ============================================================

CREATE DATABASE IF NOT EXISTS lavela_pool
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE lavela_pool;

-- ============================================================
-- 1. USERS
-- ============================================================
CREATE TABLE IF NOT EXISTS users (
    id              BIGINT          NOT NULL AUTO_INCREMENT,
    firebase_uid    VARCHAR(128)    NOT NULL,
    full_name       VARCHAR(100)    NOT NULL,
    email           VARCHAR(255)    NULL,
    phone           VARCHAR(20)     NULL,
    status          VARCHAR(20)     NOT NULL DEFAULT 'ACTIVE',   -- ACTIVE | LOCKED
    created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    UNIQUE KEY uq_users_firebase_uid (firebase_uid),
    UNIQUE KEY uq_users_email        (email),
    UNIQUE KEY uq_users_phone        (phone)
);

-- ============================================================
-- 2. USER_ROLES  (1 user → nhiều role)
-- ============================================================
CREATE TABLE IF NOT EXISTS user_roles (
    user_id BIGINT      NOT NULL,
    role    VARCHAR(20) NOT NULL,   -- CUSTOMER | STAFF | ADMIN

    PRIMARY KEY (user_id, role),
    CONSTRAINT fk_user_roles_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- ============================================================
-- 3. POOLS
-- ============================================================
CREATE TABLE IF NOT EXISTS pools (
    id          BIGINT       NOT NULL AUTO_INCREMENT,
    name        VARCHAR(200) NOT NULL,
    address     VARCHAR(500) NOT NULL,
    geo_lat     DOUBLE       NULL,
    geo_lng     DOUBLE       NULL,
    description TEXT         NULL,
    open_hours  VARCHAR(100) NULL,                              -- e.g. "06:00-22:00"
    status      VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE',        -- ACTIVE | INACTIVE
    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (id)
);

-- ============================================================
-- 4. POOL_IMAGES  (1 pool → nhiều ảnh)
-- ============================================================
CREATE TABLE IF NOT EXISTS pool_images (
    id        BIGINT        NOT NULL AUTO_INCREMENT,
    pool_id   BIGINT        NOT NULL,
    image_url VARCHAR(1000) NOT NULL,
    sort_order INT          NOT NULL DEFAULT 0,

    PRIMARY KEY (id),
    CONSTRAINT fk_pool_images_pool FOREIGN KEY (pool_id) REFERENCES pools (id) ON DELETE CASCADE
);

-- ============================================================
-- 5. SLOTS
-- ============================================================
CREATE TABLE IF NOT EXISTS slots (
    id                  BIGINT          NOT NULL AUTO_INCREMENT,
    pool_id             BIGINT          NOT NULL,
    start_time          DATETIME        NOT NULL,
    end_time            DATETIME        NOT NULL,
    capacity_total      INT             NOT NULL,
    capacity_available  INT             NOT NULL,
    price               DECIMAL(12, 2)  NOT NULL,
    status              VARCHAR(20)     NOT NULL DEFAULT 'ACTIVE',  -- ACTIVE | INACTIVE | FULL
    version             BIGINT          NOT NULL DEFAULT 0,         -- Optimistic lock
    created_at          DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    CONSTRAINT fk_slots_pool     FOREIGN KEY (pool_id) REFERENCES pools (id) ON DELETE CASCADE,
    CONSTRAINT chk_slot_capacity CHECK (capacity_available >= 0 AND capacity_available <= capacity_total),
    CONSTRAINT chk_slot_time     CHECK (end_time > start_time),

    INDEX idx_slots_pool_time (pool_id, start_time, end_time)
);

-- ============================================================
-- 6. BOOKINGS
-- ============================================================
CREATE TABLE IF NOT EXISTS bookings (
    id              BIGINT          NOT NULL AUTO_INCREMENT,
    user_id         BIGINT          NOT NULL,
    pool_id         BIGINT          NOT NULL,
    slot_id         BIGINT          NOT NULL,
    qty             INT             NOT NULL,
    amount          DECIMAL(12, 2)  NOT NULL,
    status          VARCHAR(30)     NOT NULL DEFAULT 'PENDING_PAYMENT',
    -- PENDING_PAYMENT | CONFIRMED | CHECKED_IN | COMPLETED | EXPIRED | CANCELED | FAILED
    payment_status  VARCHAR(20)     NOT NULL DEFAULT 'CREATED',
    -- CREATED | PENDING | SUCCESS | FAILED | REFUNDED
    booking_code    VARCHAR(50)     NOT NULL,
    qr_payload      TEXT            NULL,       -- Server-signed jwt/hmac, set khi CONFIRMED
    expires_at      DATETIME        NOT NULL,   -- now + TTL (default 15 phút)
    cancel_reason   VARCHAR(500)    NULL,
    created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    UNIQUE KEY uq_bookings_code (booking_code),
    CONSTRAINT fk_bookings_user FOREIGN KEY (user_id) REFERENCES users   (id),
    CONSTRAINT fk_bookings_pool FOREIGN KEY (pool_id) REFERENCES pools   (id),
    CONSTRAINT fk_bookings_slot FOREIGN KEY (slot_id) REFERENCES slots   (id),

    INDEX idx_bookings_user       (user_id),
    INDEX idx_bookings_slot       (slot_id),
    INDEX idx_bookings_status     (status),
    INDEX idx_bookings_expires_at (expires_at)   -- Dùng bởi scheduler expire TTL
);

-- ============================================================
-- 7. PAYMENTS
-- ============================================================
CREATE TABLE IF NOT EXISTS payments (
    id               BIGINT          NOT NULL AUTO_INCREMENT,
    booking_id       BIGINT          NOT NULL,
    provider         VARCHAR(50)     NOT NULL,                -- VNPAY | MOMO | STRIPE
    provider_txn_id  VARCHAR(200)    NULL,                    -- ID từ payment gateway
    amount           DECIMAL(12, 2)  NOT NULL,
    currency         VARCHAR(3)      NOT NULL DEFAULT 'VND',
    status           VARCHAR(20)     NOT NULL DEFAULT 'CREATED',
    -- CREATED | PENDING | SUCCESS | FAILED | REFUNDED
    redirect_url     TEXT            NULL,                    -- URL chuyển user sang gateway
    raw_payload_ref  TEXT            NULL,                    -- Ref tới raw webhook (S3/path)
    paid_at          DATETIME        NULL,
    refunded_at      DATETIME        NULL,
    created_at       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    UNIQUE KEY uq_payments_booking               (booking_id),              -- 1 booking → 1 payment (MVP)
    UNIQUE KEY uq_payments_provider_txn          (provider, provider_txn_id), -- Idempotency key
    CONSTRAINT fk_payments_booking FOREIGN KEY   (booking_id) REFERENCES bookings (id)
);

-- ============================================================
-- 8. INVENTORY_LOGS  (Audit log thay đổi capacity slot)
-- Chỉ INSERT, không UPDATE / DELETE
-- ============================================================
CREATE TABLE IF NOT EXISTS inventory_logs (
    id              BIGINT       NOT NULL AUTO_INCREMENT,
    slot_id         BIGINT       NOT NULL,
    booking_id      BIGINT       NULL,
    payment_id      BIGINT       NULL,
    delta           INT          NOT NULL,       -- Âm = giữ chỗ, Dương = trả chỗ
    capacity_after  INT          NOT NULL,       -- Snapshot capacity sau khi thay đổi
    reason          VARCHAR(50)  NOT NULL,
    -- RESERVE | RELEASE | CONFIRM | CANCEL | EXPIRE | MANUAL_ADJUST
    actor           VARCHAR(100) NOT NULL,       -- firebase_uid hoặc "SYSTEM"
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    CONSTRAINT fk_inv_log_slot    FOREIGN KEY (slot_id)    REFERENCES slots    (id),
    CONSTRAINT fk_inv_log_booking FOREIGN KEY (booking_id) REFERENCES bookings (id) ON DELETE SET NULL,
    CONSTRAINT fk_inv_log_payment FOREIGN KEY (payment_id) REFERENCES payments (id) ON DELETE SET NULL,

    INDEX idx_inv_log_slot    (slot_id),
    INDEX idx_inv_log_booking (booking_id)
);
