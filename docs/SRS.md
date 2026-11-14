# Software Requirements Specification (SRS)
## Project: Local-Hosted Real-Time Chat & WebRTC Calling Application (ChatAPP)
**Document Version:** 2.0 (Phase 1 Comprehensive & QA Engineering Amendment)  
**Date:** October 18, 2026  
**Status:** Approved for Implementation (Phase 1 Scope)

---

## 1. Executive Summary & Architectural Overview

ChatAPP is a secure, real-time communication platform built with a **Laravel 11** backend and a **Flutter** (Android/iOS) cross-platform mobile application. The system operates on a zero-cloud, developer-hosted infrastructure where the backend runs locally on localhost and is securely exposed to mobile devices across the public internet via encrypted tunneling (Cloudflare Tunnels or Ngrok).

### 1.1 Core Architecture Highlights
- **Backend Architecture**: Laravel 11 following strict Clean Layering (`Controller -> FormRequest -> Service -> Repository -> API Resource`).
- **Real-Time Communication**: WebSocket transport via **Laravel Reverb** for instant messaging, delivery/read receipts, user presence, and real-time signaling.
- **Media Streaming**: Peer-to-Peer (P2P) **WebRTC** with DTLS-SRTP encryption for 1-to-1 Voice Calling, Video Calling, and Screen Sharing.
- **Zero-Knowledge End-to-End Encryption (E2EE)**:
  - Asymmetric Key Exchange: Curve25519 (X25519) identity key pairs generated on-device.
  - Symmetric Session Encryption: AES-256-GCM with unique Initialization Vectors (IV) and Message Authentication Codes (MAC / Auth Tag).
  - Backend role is strictly zero-knowledge: The backend stores and routes ciphertexts, public keys, and encrypted media blobs only. Plaintext and private keys never touch the network or server.
- **Offline & Local Storage Strategy**: Decrypted messages, thumbnails, and media files are cached securely in the mobile device's private sandboxed internal directory (`.chatapp_vault/`) and indexed in a local SQLite database, with automatic synchronization and hard deletion when purged on the server.

---

## 2. QA Defect Remediation & Technical Specifications (Hotfixes)

This section specifies the technical requirements and architecture for resolving the defects identified during Phase 1 Quality Assurance testing.

### 2.1 BUG-01: Authentication Session Invalidation & Logout Redirection
- **Defect Description**: When a user taps "Sign Out" on the `HomePage`, the user remains on the `HomePage` rather than being redirected to `LoginPage`. Subsequent actions or background polling fail with HTTP `401 Unauthorized`.
- **Root Cause Analysis**:
  1. `HomePage` does not implement a `BlocListener<AuthBloc, AuthState>` listening for the `Unauthenticated` state.
  2. `main.dart` uses a static root page rather than a reactive authentication guard or reactive `MaterialApp` router.
  3. The local Sanctum token is deleted from secure storage, but active in-memory user sessions and WebSocket connections remain open and attempt authenticated polling.
- **Technical Specification & Acceptance Criteria**:
  1. **Auth State Listener**: Wrap `HomePage` or root navigation with a `BlocListener<AuthBloc, AuthState>` that intercepts `Unauthenticated` and triggers `Navigator.pushAndRemoveUntil` navigating cleanly to `LoginPage`.
  2. **WebSocket & Session Teardown**: Upon dispatch of `AuthLogoutRequested`:
     - Disconnect and unsubscribe from all active Laravel Reverb WebSocket channels via `WebSocketService.disconnect()`.
     - Purge cached session keys and user credentials in `E2eeManager.reset()`.
     - Clear local runtime state in `UsersBloc` and `ChatBloc`.
  3. **Global 401 Interceptor**: Ensure the Dio network interceptor catches any HTTP 401 response and dispatches `AuthLogoutRequested` automatically to prevent unresponsive dead-lock UI states.

### 2.2 BUG-02: Home Page Direct Call Initiation
- **Defect Description**: Tapping the Voice Call or Video Call action icons on user cards on `HomePage` displays a placeholder snackbar message (`Ready in task-13` / `Ready in task-14`) instead of starting the call.
- **Root Cause Analysis**: The `IconButton` onPressed handlers in `frontend/lib/features/users/presentation/pages/home_page.dart` contain hardcoded placeholder snackbars and are not connected to `CallBloc`.
- **Technical Specification & Acceptance Criteria**:
  1. **CallBloc Integration**: Connect `HomePage` call action buttons directly to `CallBloc.add(InitiateCallRequested(...))`.
  2. **Permission Check**: Validate microphone (for voice) and camera + microphone (for video) runtime permissions prior to dispatching call events.
  3. **Navigation Flow**:
     - Voice Call: Push `VoiceCallPage(peer: peerUser, isCaller: true)`.
     - Video Call: Push `VideoCallPage(peer: peerUser, isCaller: true)`.
  4. **Signaling Offer**: Ensure WebSockets and the signaling service emit the SDP offer immediately when initiated from `HomePage`, identical to `ChatPage`.

### 2.3 BUG-03: Sandboxed Decrypted Local Storage & Server Deletion Sync
- **Defect Description**: Messages, images, and videos are re-downloaded and re-decrypted from the server every time the chat is opened. Furthermore, if a message or media blob is deleted from the server, it must automatically be deleted from the client device.
- **Root Cause Analysis**: `ChatRepositoryImpl` currently maintains an ephemeral in-memory cache (`Map<int, String>`, `Map<int, Uint8List>`). There is no persistent local SQLite database or sandboxed local filesystem directory for decrypted media assets.
- **Technical Specification & Acceptance Criteria**:
  1. **Sandboxed Decrypted Storage Directory**:
     - Media files (images, videos, audio notes, documents) must be decrypted once and persisted into the app's internal private storage directory: `<AppDocumentsDir>/.chatapp_vault/{conversation_id}/`.
     - The directory must be hidden (prefixed with `.`) and excluded from system gallery scanners (e.g. Android `.nomedia` file present).
  2. **Local SQLite Persistence (`local_messages` table)**:
     - Store decrypted message text, local media paths, message status (sent, delivered, read), sender/receiver IDs, timestamps, and server message IDs.
     - Chat screens must load instantly from local SQLite storage first (offline-first UI), only querying the backend for incremental deltas (`last_sync_timestamp`).
  3. **Automated Server Deletion Synchronization**:
     - **Real-Time Event**: When Laravel broadcasts `message.deleted` via Reverb, the client intercepts the event, immediately deletes the message records from local SQLite, and hard-deletes the physical decrypted media files from the filesystem.
     - **Reconciliation on Fetch**: When fetching conversation history, any message ID previously stored locally that is absent from the server's non-deleted message set (or flagged as deleted) must be purged from local SQLite and disk.
     - **Disappearing Expiration**: Expired messages must be purged automatically as specified in Section 4.5.

### 2.4 BUG-04: WebRTC Signaling Schema Mismatch (SDP 422 Error)
- **Defect Description**: Initiating a voice call from `ChatPage` triggers an error: `APIException: The sdp field is required. (Status: 422)`.
- **Root Cause Analysis**:
  - Backend `CallOfferRequest.php` validates `'sdp' => ['required']`.
  - Frontend `CallSignalingRemoteDataSourceImpl.sendOffer()` sends `'sdp_offer': sdpOffer`.
  - Backend `CallAnswerRequest.php` validates `'receiver_id'` and `'sdp'`, whereas frontend was sending `'caller_id'` and `'sdp_answer'`.
- **Technical Specification & Acceptance Criteria**:
  1. **Standardized API Contract**:
     - Harmonize field naming across backend and frontend to use canonical WebRTC schema:
       - **Offer Endpoint (`POST /api/v1/call/offer`)**:
         - Payload: `{ "receiver_id": int, "call_type": "voice"|"video", "sdp": string, "call_id": string }`
       - **Answer Endpoint (`POST /api/v1/call/answer`)**:
         - Payload: `{ "receiver_id": int, "call_id": string, "sdp": string }`
       - **ICE Candidate Endpoint (`POST /api/v1/call/ice-candidate`)**:
         - Payload: `{ "target_user_id": int, "call_id": string, "candidate": { "candidate": string, "sdpMid": string, "sdpMLineIndex": int } }`
       - **End Call Endpoint (`POST /api/v1/call/end`)**:
         - Payload: `{ "target_user_id": int, "call_id": string, "reason": string }`
  2. Update `CallSignalingRemoteDataSourceImpl` to serialize `sdp` and matching parameters accurately, eliminating the 422 validation failure.

---

## 3. Technology Stack & Environment Configuration

### 3.1 Backend Stack
- **Framework**: Laravel 11.x on PHP 8.2+.
- **Authentication**: Laravel Sanctum (Bearer Token authentication).
- **WebSocket Server**: Laravel Reverb (`php artisan reverb:start --port=8080`).
- **Database**: MySQL 8.0 or SQLite (Localhost).
- **Encrypted Media Storage**: Local disk storage driver (`storage/app/public/encrypted_media/`).
- **Cron / Task Scheduler**: Laravel Scheduler (`php artisan schedule:work` / `chat:prune-disappearing`).

### 3.2 Frontend Stack (Mobile Application)
- **Framework**: Flutter 3.24+ (Dart 3.5+).
- **Architecture**: Clean Architecture with Feature-First structure and BLoC pattern (`flutter_bloc`).
- **Real-Time Client**: Reverb / Pusher client (`pusher_channels_flutter`).
- **WebRTC**: `flutter_webrtc: ^0.11.7` supporting peer-to-peer audio, video, and screen capture.
- **Cryptography Engine**: `cryptography: ^2.7.0` (X25519 key exchange, AES-256-GCM, HKDF-SHA256).
- **Local Persistence**: `sqflite` (SQLite database) & `flutter_secure_storage` (Private keys and auth tokens).
- **Media & File Handling**: `file_picker`, `image_picker`, `record` (Voice messaging audio recorder), `audioplayers` (Voice notes playback), `open_filex` (Document viewer).
- **Network Client**: `dio` with custom interceptors for authentication, retry, and base URL reconfiguration.

### 3.3 Network & Tunneling Constraints
- Backend running on host: HTTP (`127.0.0.1:8000`), WebSocket Reverb (`127.0.0.1:8080`).
- Exposed via public HTTPS/WSS tunnels (Cloudflare Named/Quick Tunnel or Ngrok).
- Mobile client accesses dynamically configurable base URL stored in `.env` or adjusted via in-app `NetworkSettingsDialog`.
- STUN Server: `stun:stun.l.google.com:19302` for NAT traversal; DTLS-SRTP for media encryption.

---

## 4. Phase 1 Functional Requirements & New Feature Specifications

### 4.1 Feature 1: WebRTC Screen Sharing in Video Calling
#### 4.1.1 Overview
Allows either participant during an active WebRTC 1-to-1 video call to share their mobile device's live screen with the peer in real time.

#### 4.1.2 Functional & Technical Requirements
1. **Screen Capture Provider**:
   - Utilize `flutter_webrtc`'s `navigator.mediaDevices.getDisplayMedia(...)`.
   - On Android: Integrates with Android `MediaProjection` API (foreground service notification requesting screen recording permission).
2. **Track Replacement & Renegotiation**:
   - The screen capture video track replaces the active camera video track on the existing `RTCPeerConnection` sender (`RTCRtpSender.replaceTrack(newTrack)`).
   - Audio transmission (microphone) remains uninterrupted during screen sharing.
   - If the peer's resolution constraints require renegotiation, send a WebRTC re-offer over the existing WebSocket signaling channel.
3. **User Interface & Controls**:
   - Add a "Screen Share" toggle button to the call toolbar on `VideoCallPage`.
   - Button states: `Inactive` (Camera active), `Active` (Screen sharing, highlighting the button in green/amber with a banner indicating "You are sharing your screen").
   - When the remote peer is sharing their screen, the local viewport switches to display the remote screen stream in full resolution with pinch-to-zoom capabilities.
4. **Reversion & Teardown**:
   - When screen sharing is stopped (either via in-app toggle or system notification), the app smoothly reverts the track back to the local camera stream without terminating the call.

---

### 4.2 Feature 2: Voice Messaging (Audio Notes / Push-to-Talk)
#### 4.2.1 Overview
Provides users with the ability to record, preview, send, and play encrypted audio notes inside 1-to-1 conversations.

#### 4.2.2 Functional & Technical Requirements
1. **Audio Recording**:
   - Codec: AAC-LC or Opus in `.m4a` / `.aac` container at 16kHz - 44.1kHz sample rate for high compression and speech clarity.
   - Recording Controls: Hold-to-record with lock option (swipe up to lock recording mode) and swipe-left to cancel.
   - Visual Feedback: Real-time recording duration timer and animated amplitude waveform.
2. **E2EE Encryption & Packaging**:
   - Recorded raw audio bytes are encrypted on-device with a random symmetric 256-bit key using AES-256-GCM.
   - Symmetric key is encrypted with the recipient's public identity key via X25519 key exchange.
   - Encrypted ciphertext blob uploaded to backend `/api/v1/media/upload`.
   - Message payload sent with `message_type: "audio"`, encrypted media URL, wrapped key payload, and audio duration metadata.
3. **Playback & Local Caching**:
   - Decrypted once upon receipt and persisted in `.chatapp_vault/audio/`.
   - Audio bubble in chat displays: Play/Pause button, interactive seekbar, duration elapsed/total, and playback speed toggle (1x, 1.5x, 2x).
   - Audio player pauses automatically when call events or app lifecycle backgrounding occurs.

---

### 4.3 Feature 3: Document & Contact Sharing
#### 4.3.1 Overview
Expands chat file-sharing capabilities beyond images and videos to include general documents (PDF, DOCX, XLSX, TXT, ZIP) and contact cards (vCard / phone contacts).

#### 4.3.2 Functional & Technical Requirements
1. **Document Sharing**:
   - **File Selection**: Integrate `file_picker` supporting all standard extensions with a configurable maximum size limit (e.g. 50MB for localhost tunnel efficiency).
   - **E2EE Pipeline**: Symmetric file encryption via AES-256-GCM. The encrypted file blob is uploaded to `/api/v1/media/upload`.
   - **Chat Bubble UI**: Displays file name, formatted file size (e.g. `2.4 MB`), file type icon (PDF, Word, Archive, Code), and download/open button.
   - **Viewing & Opening**: Upon tapping, decrypted file in `.chatapp_vault/documents/` is opened using system default viewer via `open_filex`.
2. **Contact Sharing**:
   - **Contact Selection**: Native contact picker or in-app contact selection interface extracting: Full Name, Phone Numbers, Email Addresses, and Organization.
   - **Payload Format**: Encapsulated into a structured JSON payload:
     ```json
     {
       "contact_name": "John Doe",
       "phone_numbers": ["+1234567890"],
       "emails": ["john@example.com"],
       "organization": "Company Inc."
     }
     ```
   - **E2EE Transmission**: Encrypted as a text message with `message_type: "contact"`.
   - **Chat Bubble UI**: Dedicated Contact Card widget featuring contact avatar, name, primary phone number, and action buttons:
     - "Message": Opens a chat if user exists in system directory.
     - "Save Contact": Triggers system intent to add contact to device address book.

---

### 4.4 Feature 4: User Profile Screen & Shared Media/Files Repository
#### 4.4.1 Overview
Provides a dedicated profile view for any contact, displaying user metadata, security safety numbers, and a segregated repository of all media, documents, and audio exchanged with that user.

#### 4.4.2 Functional & Technical Requirements
1. **User Profile View (`UserProfilePage`)**:
   - Accessible by tapping the contact's name/avatar in the chat app bar or home page user list.
   - Displays: Profile Avatar, Display Name, Email address, Online/Presence status, and Bio/Status text.
   - **E2EE Safety Number Verification**: Computes and displays a 60-digit fingerprint or QR code derived from the SHA-256 hash of the two users' sorted X25519 public identity keys, enabling out-of-band verification against man-in-the-middle attacks.
   - **Quick Action Bar**: Direct action icons for Chat, Voice Call, Video Call, and Disappearing Messages configuration.
2. **Shared Media, Docs & Audio Gallery (`SharedMediaPage`)**:
   - Segmented tab navigation:
     - **Tab 1: Media**: Photo and video thumbnail grid sorted by date, with fullscreen preview on tap.
     - **Tab 2: Documents**: Chronological list of shared files showing title, extension badge, size, and date.
     - **Tab 3: Audio**: List of shared voice notes with inline playback and duration.
   - **Data Sourcing**: Queries the client-side local SQLite database where `(sender_id == peer_id OR receiver_id == peer_id) AND message_type IN (...)`.
   - **Instant Offline Rendering**: Directly accesses decrypted files from `.chatapp_vault/` without making network requests.

---

### 4.5 Feature 5: Disappearing Messages Engine (Self-Destructing Messages)
#### 4.5.1 Overview
Allows users to configure self-destruct timers on a per-conversation basis. Messages sent within a disappearing-enabled conversation automatically expire and are purged permanently from both backend database/storage and client devices.

#### 4.5.2 Functional & Technical Requirements
1. **Expiration Timers**:
   - Supported durations:
     - `Off` (Default, persistent)
     - `1 Hour`
     - `12 Hours`
     - `24 Hours`
     - `7 Days`
2. **Configuration & Negotiation**:
   - Either user in a 1-to-1 conversation can update the timer setting from the `UserProfilePage` or Chat settings menu.
   - Updating the timer emits a REST request `POST /api/v1/conversations/{peerId}/disappearing` and triggers a real-time WebSocket event `conversation.disappearing_updated` to notify the peer.
   - A system event bubble appears in the chat: *"John set disappearing messages to 12 hours"*.
3. **Message Expiration Computation**:
   - When a message is sent while disappearing mode is active, the backend sets:
     `expires_at = now() + duration_seconds`.
   - The `expires_at` ISO-8601 timestamp is transmitted in the message payload.
4. **Backend Automated Cleanup**:
   - Scheduled Artisan command `php artisan chat:prune-disappearing` runs every 5 minutes.
   - Executes hard-delete on all messages where `expires_at IS NOT NULL AND expires_at <= NOW()`.
   - Deletes associated encrypted media blobs from server storage (`storage/app/public/encrypted_media/`).
5. **Client Local Database & Storage Auto-Purge**:
   - Client SQLite database maintains an indexed `expires_at` column.
   - A background timer/worker in Flutter checks every 60 seconds (and upon chat screen open) for expired local messages.
   - Hard-deletes expired records from `local_messages` and removes physical files from `.chatapp_vault/`.
   - UI visual cues: Message bubble displays a subtle hourglass/timer indicator when disappearing mode is enabled.

---

## 5. Database Schema & Storage Specifications

### 5.1 Backend Database Schema (MySQL / SQLite)

```sql
-- 1. Users Table
CREATE TABLE users (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    public_identity_key TEXT NULL,       -- Base64 X25519 identity key
    public_signed_prekey TEXT NULL,      -- Base64 X25519 signed pre-key
    avatar_url VARCHAR(500) NULL,
    bio VARCHAR(255) NULL,
    is_online BOOLEAN DEFAULT FALSE,
    last_seen_at TIMESTAMP NULL,
    created_at TIMESTAMP NULL,
    updated_at TIMESTAMP NULL
);

-- 2. Conversation Settings (Disappearing Messages)
CREATE TABLE conversation_settings (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_one_id BIGINT UNSIGNED NOT NULL,
    user_two_id BIGINT UNSIGNED NOT NULL,
    disappearing_duration_seconds INT UNSIGNED DEFAULT 0, -- 0 = Off, 43200 = 12h, etc.
    updated_by BIGINT UNSIGNED NOT NULL,
    updated_at TIMESTAMP NULL,
    FOREIGN KEY (user_one_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (user_two_id) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE KEY uq_conversation_users (user_one_id, user_two_id)
);

-- 3. Messages Table (Zero-Knowledge Ciphertexts)
CREATE TABLE messages (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    sender_id BIGINT UNSIGNED NOT NULL,
    receiver_id BIGINT UNSIGNED NOT NULL,
    message_type ENUM('text', 'image', 'video', 'audio', 'document', 'contact') NOT NULL DEFAULT 'text',
    ciphertext LONGTEXT NOT NULL,         -- Base64 AES-256-GCM encrypted payload
    iv VARCHAR(64) NOT NULL,              -- Base64 initialization vector
    mac VARCHAR(64) NOT NULL,             -- Base64 authentication tag
    media_url VARCHAR(500) NULL,          -- Path to encrypted media blob
    encrypted_media_key LONGTEXT NULL,    -- Wrapped symmetric key for peer
    file_name VARCHAR(255) NULL,          -- Document/media original file name
    file_size BIGINT UNSIGNED NULL,       -- Size in bytes
    media_metadata JSON NULL,             -- Duration (audio), dimensions (images), etc.
    reply_to_id BIGINT UNSIGNED NULL,
    reply_preview TEXT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    read_at TIMESTAMP NULL,
    expires_at TIMESTAMP NULL,            -- Disappearing message self-destruct timestamp
    created_at TIMESTAMP NULL,
    updated_at TIMESTAMP NULL,
    INDEX idx_conversation (sender_id, receiver_id, created_at),
    INDEX idx_expires_at (expires_at),
    FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (receiver_id) REFERENCES users(id) ON DELETE CASCADE
);

-- 4. Media Blobs Tracking Table
CREATE TABLE media_blobs (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    uuid VARCHAR(64) UNIQUE NOT NULL,
    file_path VARCHAR(500) NOT NULL,
    file_size BIGINT UNSIGNED NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    uploaded_by BIGINT UNSIGNED NOT NULL,
    created_at TIMESTAMP NULL,
    FOREIGN KEY (uploaded_by) REFERENCES users(id) ON DELETE CASCADE
);
```

### 5.2 Frontend Local Database Schema (Client SQLite: `chatapp_local.db`)

```sql
-- Local Decrypted Messages Table
CREATE TABLE local_messages (
    id INTEGER PRIMARY KEY,               -- Server Message ID
    conversation_peer_id INTEGER NOT NULL,
    sender_id INTEGER NOT NULL,
    receiver_id INTEGER NOT NULL,
    message_type TEXT NOT NULL,           -- 'text', 'image', 'video', 'audio', 'document', 'contact'
    plaintext_content TEXT,               -- Decrypted text, contact JSON, or caption
    local_file_path TEXT,                 -- Path to decrypted file in .chatapp_vault/
    file_name TEXT,
    file_size INTEGER,
    duration_seconds INTEGER,
    status TEXT NOT NULL,                 -- 'pending', 'sent', 'delivered', 'read'
    reply_to_id INTEGER,
    reply_preview TEXT,
    expires_at INTEGER,                   -- Epoch milliseconds self-destruct
    created_at INTEGER NOT NULL,          -- Epoch milliseconds
    is_read INTEGER DEFAULT 0
);

CREATE INDEX idx_local_msg_peer ON local_messages (conversation_peer_id, created_at);
CREATE INDEX idx_local_msg_expires ON local_messages (expires_at);

-- Local Conversation Preferences
CREATE TABLE local_conversation_prefs (
    peer_id INTEGER PRIMARY KEY,
    disappearing_duration_seconds INTEGER DEFAULT 0,
    last_synced_at INTEGER DEFAULT 0
);
```

### 5.3 Local Sandboxed Directory Layout (Client Device)
```text
<AppDocumentsDir>/
└── .chatapp_vault/
    ├── .nomedia                  # Prevents media indexing by Android Gallery
    ├── images/                   # Decrypted image cache ({message_id}.jpg)
    ├── videos/                   # Decrypted video cache ({message_id}.mp4)
    ├── audio/                    # Decrypted voice notes ({message_id}.m4a)
    └── documents/                # Decrypted documents ({message_id}_{name})
```

---

## 6. API Specifications & Signaling Protocols

### 6.1 Authentication & Profile APIs
| Method | Endpoint | Description | Auth Required |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/v1/auth/register` | Register new user with public identity key | No |
| `POST` | `/api/v1/auth/login` | Authenticate user, return Sanctum token | No |
| `POST` | `/api/v1/auth/logout` | Revoke current token and terminate session | Yes (Sanctum) |
| `GET` | `/api/v1/auth/me` | Fetch authenticated user profile & keys | Yes (Sanctum) |
| `GET` | `/api/v1/users` | List registered contacts with presence & keys | Yes (Sanctum) |
| `GET` | `/api/v1/users/{id}/profile` | View detailed profile and shared media summary | Yes (Sanctum) |

### 6.2 E2EE Messaging & Media APIs
| Method | Endpoint | Description | Auth Required |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/v1/messages/send` | Transmit encrypted message ciphertext | Yes (Sanctum) |
| `GET` | `/api/v1/messages/{peerId}` | Fetch message history with pagination & sync | Yes (Sanctum) |
| `POST` | `/api/v1/messages/{id}/read` | Mark individual message as read | Yes (Sanctum) |
| `POST` | `/api/v1/messages/conversation/{peerId}/read` | Mark all peer messages as read | Yes (Sanctum) |
| `DELETE`| `/api/v1/messages` | Delete message(s) for self or everyone | Yes (Sanctum) |
| `POST` | `/api/v1/media/upload` | Upload zero-knowledge encrypted binary blob | Yes (Sanctum) |
| `GET` | `/api/v1/media/{uuid}` | Download encrypted binary blob | Yes (Sanctum) |
| `POST` | `/api/v1/conversations/{peerId}/disappearing` | Update disappearing message duration | Yes (Sanctum) |

### 6.3 WebRTC Real-Time Signaling Endpoints
| Method | Endpoint | Description | Payload Schema |
| :--- | :--- | :--- | :--- |
| `POST` | `/api/v1/call/offer` | Dispatch SDP Offer | `{ "receiver_id": int, "call_type": "voice"\|"video", "sdp": string, "call_id": string }` |
| `POST` | `/api/v1/call/answer` | Dispatch SDP Answer | `{ "receiver_id": int, "call_id": string, "sdp": string }` |
| `POST` | `/api/v1/call/ice-candidate` | Relay ICE Candidate | `{ "target_user_id": int, "call_id": string, "candidate": object }` |
| `POST` | `/api/v1/call/end` | Terminate Call Session | `{ "target_user_id": int, "call_id": string, "reason": string }` |

### 6.4 WebSocket Events (Laravel Reverb)
- **Private Channel**: `private-user.{userId}`
  - `message.sent`: Dispatched when an incoming message is received.
  - `message.read`: Dispatched when peer reads messages.
  - `message.deleted`: Dispatched when messages are removed from server.
  - `conversation.disappearing_updated`: Dispatched when disappearing timer changes.
  - `call.offer`: Dispatched to callee with SDP offer and call parameters.
  - `call.answer`: Dispatched to caller with callee's SDP answer.
  - `call.ice_candidate`: Dispatched to relay trickle ICE candidates.
  - `call.ended`: Dispatched when a call session is hung up or rejected.

---

## 7. Security, Privacy & Non-Functional Requirements

### 7.1 Cryptographic Guarantees (Zero-Knowledge Backend)
1. **Confidentiality**: The server possesses neither the private keys nor the symmetric file/message keys. Decryption is mathematically impossible on the server or on untrusted transit networks.
2. **Integrity & Authenticity**: Every encrypted payload utilizes AES-256-GCM authentication tags (128-bit MAC) preventing ciphertext tampering.
3. **Forward Secrecy Foundation**: Ephemeral keys combined with X25519 guarantee that compromise of any single session does not decrypt previous communications.

### 7.2 Local Storage Security & Privacy
1. **Sandboxing**: All decrypted files reside strictly inside internal application storage (`getApplicationDocumentsDirectory()`), preventing access by third-party apps on non-rooted devices.
2. **Gallery Isolation**: Media folders must contain a `.nomedia` file to prevent indexing by public photo galleries or cloud backup sync agents.
3. **Residual Leak Prevention**: When messages or media are deleted (manually or via disappearing timer), local files are overwritten or unlinked immediately from the filesystem.

### 7.3 Performance & Network Resilience
1. **Offline-First Responsiveness**: Opening a chat loads messages from local SQLite in `< 50ms`, decoupled from network latency.
2. **Tunneling Reconnect Protocol**: The Flutter network layer must handle dynamic tunnel reconnections gracefully with exponential backoff on WebSocket reconnection.
3. **P2P Fallback**: WebRTC sessions negotiate STUN candidates to establish low-latency direct P2P connections, keeping bandwidth independent of the localhost tunnel.

---

## 8. Master Implementation Roadmap & Task Mapping

| Task ID | Component / Milestone | Phase | Scope & Description | Status |
| :--- | :--- | :--- | :--- | :--- |
| **TASK-01 to 17** | Core Infrastructure & MVP Base | Phase 1 | Laravel 11, Flutter scaffold, Auth, E2EE engine, Text/Media chat, WebRTC Voice & Video Calling | `COMPLETED` |
| **TASK-18** | **QA Hotfixes & Local Storage Engine** | Phase 1 | Fix Logout 401 routing, HomePage direct calling, SDP 422 schema fix, SQLite local cache & `.chatapp_vault/` sandboxing with server deletion sync | `COMPLETED` |
| **TASK-19** | **Voice Messaging & Media Sharing Expansion** | Phase 1 | Push-to-talk audio recording, waveform, E2EE audio messages, Document sharing (PDF/Office), and Contact card sharing | `COMPLETED` |
| **TASK-20** | **WebRTC Screen Sharing & User Profiles** | Phase 1 | Video call screen sharing track replacement, User Profile Page, E2EE safety numbers, and Shared Media/Docs/Audio Gallery | `COMPLETED` |
| **TASK-21** | **Disappearing Messages Engine** | Phase 1 | Per-conversation disappearing timers (1h, 12h, 24h, 7d), backend cron hard-pruning, real-time sync, and client local storage auto-purge | `COMPLETED` |

---

**End of Specification Document.**