# Message Deletion (Single/Multi-Select) & Swipe-to-Reply Specification

## 1. Overview
This document details the architecture, UX workflow, database design, API specification, and real-time synchronization for:
1. **Single & Multi-Select Contextual Message Deletion** ("Delete for Everyone" vs "Delete for Me").
2. **Left-to-Right Swipe-to-Reply** with active reply preview and quoted bubble rendering.

---

## 2. Contextual Message Deletion

### 2.1 User Experience & Interaction Rules
1. **Entering Selection Mode:**
   - **Long-press** on any message bubble (text, image, or video) selects the message and transitions the screen into **Selection Mode**.
2. **Multi-Selection:**
   - In Selection Mode, a **single tap** on any message bubble toggles its selection state (adds to or removes from selection).
   - Long-press in Selection Mode also toggles the message selection.
   - Selected bubbles display a visual highlight background and a checkmark indicator (`Icons.check_circle`).
3. **Contextual Action Bar (AppBar):**
   - The default chat header is replaced by:
     - **Close Button (`Icons.close`)**: Clears all selected items and exits selection mode.
     - **Selection Counter**: Displays `X Selected` dynamically.
     - **Delete Action (`Icons.delete_outline`)**: Opens the deletion confirmation dialog.
4. **Hardware Back Button Handling (`PopScope`):**
   - If the user presses the Android back button while selection mode is active, the app clears the selection first rather than popping/closing the chat screen.

---

### 2.2 Contextual Delete Dialog Rules (Strict Logic)
When the user taps the Delete button, the options shown in the dialog depend strictly on the ownership of the selected messages:

| Selection Scenario | Conditions | Allowed Dialog Actions |
| :--- | :--- | :--- |
| **All Selected Authored by Current User** | `every((m) => m.senderId == currentUserId \|\| m.senderId == 0)` | 1. **Delete for Everyone** (`for_everyone`)<br>2. **Delete for Me** (`for_me`)<br>3. **Cancel** |
| **Incoming Messages Authored by Peer** | `any((m) => m.senderId != currentUserId && m.senderId != 0)` | 1. **Delete for Me** (`for_me`)<br>2. **Cancel** |
| **Mixed Selection (Own + Peer's Messages)** | Contains at least one peer message and one own message | 1. **Delete for Me** (`for_me`)<br>2. **Cancel** |

> **Security Rule:** A user can NEVER delete peer-authored messages for everyone. The backend enforces ownership validation regardless of client input.

---

### 2.3 Real-Time WebSocket Synchronization
When **"Delete for Everyone"** is executed:
1. Backend marks `is_deleted_for_everyone = true` for the authorized messages.
2. Backend dispatches `MessageDeletedEvent` over Laravel Reverb to the recipient's private channel: `private-user.{peerId}`.
3. The peer's client listens to `messagesDeletedStream` in `ChatRepositoryImpl` and dispatches `MessagesDeletedRemotelyEvent`.
4. The peer's active `ChatBloc` immediately filters out the deleted IDs from `state.messages` in real time without refreshing.

When **"Delete for Me"** is executed:
1. If the user is the sender: `deleted_by_sender = true`.
2. If the user is the receiver: `deleted_by_receiver = true`.
3. The message is immediately removed from the initiating user's local state. No event is sent to the peer.

---

## 3. Left-to-Right Swipe-to-Reply

### 3.1 Gesture & Animation (`Dismissible`)
- Each `ChatBubble` is wrapped in a `Dismissible` with:
  - **Direction**: `DismissDirection.startToEnd` (Left to Right swipe).
  - **Confirm Dismiss**: Returns `false` so the bubble smoothly snaps back to its original position instead of being dismissed.
  - **Background**: Displays a circular reply icon (`Icons.reply_rounded`) with an accent tint.
  - **Guard**: In selection mode, swipe-to-reply is disabled to prevent accidental triggers while selecting messages.

### 3.2 Replying Preview Banner
- Positioned directly above `ChatInputField`:
  - Accent colored left border indicator (4px width).
  - Target author label: *"Replying to You"* or *"Replying to [Peer Name]"*.
  - Snippet preview: Plaintext preview (truncated to 50 chars) or media indicator (*📷 Photo* / *🎥 Video*).
  - Dismiss button (`Icons.close`) to cancel the active reply.

### 3.3 Quoted Bubble Rendering
- When a message contains `reply_preview`:
  - An inline quote container is rendered at the top of the bubble.
  - Includes a vertical accent line, a small reply icon, and the quoted message preview.

---

## 4. Database Schema & Migration

### Migration: `2026_10_17_193334_add_delete_and_reply_to_messages_table.php`
```sql
ALTER TABLE `messages`
  ADD COLUMN `reply_to_id` BIGINT UNSIGNED NULL AFTER `encrypted_media_key`,
  ADD COLUMN `reply_preview` VARCHAR(255) NULL AFTER `reply_to_id`,
  ADD COLUMN `deleted_by_sender` TINYINT(1) NOT NULL DEFAULT 0 AFTER `reply_preview`,
  ADD COLUMN `deleted_by_receiver` TINYINT(1) NOT NULL DEFAULT 0 AFTER `deleted_by_sender`,
  ADD COLUMN `is_deleted_for_everyone` TINYINT(1) NOT NULL DEFAULT 0 AFTER `deleted_by_receiver`,
  ADD CONSTRAINT `messages_reply_to_id_foreign` FOREIGN KEY (`reply_to_id`) REFERENCES `messages` (`id`) ON DELETE SET NULL;
```

---

## 5. API Reference

### 5.1 Delete Messages Endpoint
- **URL**: `DELETE /api/v1/messages`
- **Headers**: `Authorization: Bearer <token>`, `Accept: application/json`
- **Request Body**:
```json
{
  "message_ids": [101, 102],
  "type": "for_everyone" // or "for_me"
}
```
- **Response (`200 OK`)**:
```json
{
  "status": "success",
  "message": "Messages deleted successfully",
  "data": {
    "deleted_ids": [101, 102],
    "type": "for_everyone"
  }
}
```

### 5.2 Send Message (Updated with Reply Fields)
- **URL**: `POST /api/v1/messages`
- **Fields added**:
  - `reply_to_id` (integer, optional, exists in `messages,id`)
  - `reply_preview` (string, max: 255, optional)

### 5.3 WebSocket Event: `message.deleted`
- **Channel**: `private-user.{userId}`
- **Event**: `message.deleted`
- **Payload**:
```json
{
  "message_ids": [101, 102],
  "peer_id": 4
}
```

---

## 6. Architecture & Files Reference

### 6.1 Backend (Laravel 11)
- [MessageController.php](file:///d:/Projects/ChatAPP/backend/app/Http/Controllers/Api/v1/MessageController.php): `delete()` action validating input and invoking service.
- [MessageService.php](file:///d:/Projects/ChatAPP/backend/app/Services/MessageService.php): Orchestrates deletion, ownership validation, and dispatches `MessageDeletedEvent`.
- [MessageRepository.php](file:///d:/Projects/ChatAPP/backend/app/Repositories/Eloquent/MessageRepository.php): `deleteForEveryone()`, `deleteForMe()`, and filters out deleted messages from `getConversation()`.
- [MessageDeletedEvent.php](file:///d:/Projects/ChatAPP/backend/app/Events/MessageDeletedEvent.php): Broadcasts over Reverb private channel.
- [Message.php](file:///d:/Projects/ChatAPP/backend/app/Models/Message.php): Fillable attributes, casts, and `replyTo()` relationship.
- [SendMessageRequest.php](file:///d:/Projects/ChatAPP/backend/app/Http/Requests/Message/SendMessageRequest.php): Input validation rules for reply fields.

### 6.2 Frontend (Flutter)
- [chat_page.dart](file:///d:/Projects/ChatAPP/frontend/lib/features/chat/presentation/pages/chat_page.dart): Selection mode state, contextual AppBar, delete dialog with ownership check, reply banner, and `PopScope`.
- [chat_bubble.dart](file:///d:/Projects/ChatAPP/frontend/lib/features/chat/presentation/widgets/chat_bubble.dart): Selection highlight, checkmark badge, quote preview header, and `Dismissible` swipe-to-reply.
- [chat_bloc.dart](file:///d:/Projects/ChatAPP/frontend/lib/features/chat/presentation/bloc/chat_bloc.dart): Handles `DeleteMessagesEvent`, `MessagesDeletedRemotelyEvent`, and optimistic updates.
- [chat_event.dart](file:///d:/Projects/ChatAPP/frontend/lib/features/chat/presentation/bloc/chat_event.dart): Added `DeleteMessagesEvent`, `MessagesDeletedRemotelyEvent`, and reply parameters in send events.
- [delete_messages_usecase.dart](file:///d:/Projects/ChatAPP/frontend/lib/features/chat/domain/usecases/delete_messages_usecase.dart): Domain use case.
- [chat_repository_impl.dart](file:///d:/Projects/ChatAPP/frontend/lib/features/chat/data/repositories/chat_repository_impl.dart): Implements `deleteMessages` and exposes `messagesDeletedStream`.
- [chat_remote_datasource.dart](file:///d:/Projects/ChatAPP/frontend/lib/features/chat/data/datasources/chat_remote_datasource.dart): Executes `DELETE /api/v1/messages`.
- [message_entity.dart](file:///d:/Projects/ChatAPP/frontend/lib/features/chat/domain/entities/message_entity.dart) & [message_model.dart](file:///d:/Projects/ChatAPP/frontend/lib/features/chat/data/models/message_model.dart): Added `replyToId` and `replyPreview`.
