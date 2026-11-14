# VaultChat - Secure End-to-End Encrypted Communication Platform

VaultChat is a zero-knowledge, end-to-end encrypted (E2EE) real-time messaging and calling application. It features a modern **Flutter** mobile client (Clean Architecture & BLoC) paired with a high-performance **Laravel 11** backend and **Laravel Reverb** real-time WebSocket server.

---

## 🌟 Key Features

- **Zero-Knowledge End-to-End Encryption (E2EE)**: Messages and media files are encrypted on-device before transmission using AES-256-GCM and ECDH key agreement. The server only stores opaque ciphertext blobs, IVs, and authentication tags.
- **Real-Time WebSockets**: Instant message dispatch, presence updates (online/offline/last seen), typing indicators, and delivery ticks powered by Laravel Reverb.
- **P2P Audio & Video Calling**: Low-latency, high-quality WebRTC calls with STUN/TURN NAT traversal and DTLS-SRTP encryption.
- **Encrypted Ephemeral Media**: Secure voice notes, camera captures, and documents with client-side key generation and payload verification.
- **Disappearing Messages**: Configurable message expiration timers with automated background cleanup.
- **PIN-Based Encrypted Key Backup**: Cloud key backup encrypted client-side using PBKDF2/AES-GCM so private keys are never exposed in plaintext.
- **Dynamic Network & Tunneling**: In-app runtime network dialog allowing instant backend and WebSocket endpoint configuration without recompiling the APK.

---

## 🏗️ Architecture

```
┌────────────────────────────────────────────────────────┐
│             Flutter Mobile Client (Android/iOS)        │
│    (Clean Architecture: Presentation, Domain, Data)    │
│  - E2EE Cryptographic Engine (AES-256-GCM / ECDH)      │
│  - WebRTC PeerConnection (Audio / Video Signaling)     │
│  - WebSocket Client (Pusher/Reverb Protocol)           │
└───────────────────▲─────────────────▲──────────────────┘
                    │ HTTPS           │ WSS
                    ▼                 ▼
┌─────────────────────────┐    ┌─────────────────────────┐
│   Laravel 11 REST API   │    │  Laravel Reverb Server  │
│  - Sanctum Auth Tokens  │    │  - Real-time Events     │
│  - Schema Migrations    │    │  - Signaling Channel    │
│  - Ciphertext Storage   │    │  - Presence Channels    │
└─────────────────────────┘    └─────────────────────────┘
```

---

## 🚀 Getting Started

### Prerequisites

- **PHP 8.2+** with `sqlite`, `pdo`, `mbstring`, `openssl` extensions
- **Composer** (PHP Package Manager)
- **Node.js 18+** & NPM
- **Flutter SDK 3.24+**
- **Android Studio** / Android SDK (for Android builds)

---

### Backend Setup (Laravel 11)

1. Navigate to the backend directory:
   ```bash
   cd backend
   ```

2. Install PHP dependencies:
   ```bash
   composer install
   ```

3. Configure environment file:
   ```bash
   cp .env.example .env
   php artisan key:generate
   ```

4. Run database migrations:
   ```bash
   php artisan migrate
   ```

5. Start the HTTP API Server:
   ```bash
   php artisan serve --port=8000
   ```

6. In a separate terminal, start the Reverb WebSocket Server:
   ```bash
   php artisan reverb:start --host=0.0.0.0 --port=8080 --debug
   ```

---

### Frontend Setup (Flutter)

1. Navigate to the frontend directory:
   ```bash
   cd frontend
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Set up the environment configuration:
   ```bash
   cp .env.example .env
   ```
   > Edit `frontend/.env` to point to your backend API (`API_BASE_URL`) and WebSocket host (`REVERB_HOST`). For Android emulators, default `10.0.2.2` works directly out of the box.

4. Run the app:
   ```bash
   flutter run
   ```

---

## 🔐 Security & Privacy Architecture

- **No Hardcoded Credentials**: All tokens, keys, and network URLs are managed strictly via environment variables (`.env`) and encrypted local device storage (`flutter_secure_storage`).
- **Zero Plaintext Storage**: The database contains only encrypted data structures. User private keys never leave the client device.
- **Pure Schema Migrations**: The repository contains schema migration scripts only — no database seeders, mock user databases, or sensitive personal data.
- **Safe Audit Logging**: Client and server diagnostics automatically sanitize all payloads, redacting passwords, tokens, private keys, and authorization headers.

---

## 📜 License

This project is licensed under the [MIT License](LICENSE).
