# Cross-Network Tunneling & WebRTC NAT Traversal Setup Guide

This guide details how to expose your locally running Laravel 11 backend (`php artisan serve` on port 8000) and Laravel Reverb WebSocket server (`php artisan reverb:start` on port 8080) to physical mobile devices connected across different networks (e.g. 4G/5G mobile cellular or remote Wi-Fi), and how WebRTC traverses NAT/firewalls.

---

## 1. Architecture Overview

```text
[ Physical Android Device (4G/LTE) ]
                 │
                 ├── HTTPS requests (API / Auth / Media) ──────────┐
                 │                                                 ▼
                 ├── WSS WebSocket events (Reverb private-user.*) ─┼──► [ Cloudflare Tunnel / Ngrok ]
                 │                                                 │              │
                 └── WebRTC DTLS-SRTP P2P Audio/Video Streams ─────┤              ▼
                                                                   │   [ Developer Workstation ]
                                                                   │   ├── Laravel HTTP (127.0.0.1:8000)
                                                                   │   └── Laravel Reverb (127.0.0.1:8080)
                                                                   ▼
                                                       [ Google STUN / TURN Relay ]
                                                       (stun.l.google.com:19302)
```

---

## 2. Option A: Cloudflare Tunnel (`cloudflared`) [Recommended]

Cloudflare Tunnels are completely free, provide stable HTTPS/WSS URLs, and do not expire after a few hours like Ngrok free tiers.

### Step 1: Install `cloudflared`
- **Windows (winget)**:
  ```powershell
  winget install Cloudflare.cloudflared
  ```
- Or download the binary from [Cloudflare Releases](https://github.com/cloudflare/cloudflared/releases).

### Step 2: Configure Ingress Rules
Copy `scripts/tunnel/cloudflared-config.example.yml` to `scripts/tunnel/config.yml`:

```yaml
tunnel: <YOUR-TUNNEL-UUID>
credentials-file: C:\Users\<USER>\.cloudflared\<YOUR-TUNNEL-UUID>.json

ingress:
  # Route 1: Reverb WebSockets
  - hostname: ws.yourdomain.com
    service: http://127.0.0.1:8080
    originRequest:
      noTLSVerify: true

  # Route 2: Laravel API & Media
  - hostname: api.yourdomain.com
    service: http://127.0.0.1:8000
    originRequest:
      noTLSVerify: true

  - service: http_status:404
```

### Step 3: Run the Tunnel
Run the launcher script:
```powershell
.\scripts\tunnel\start-cloudflare-tunnel.ps1
```

---

## 3. Option B: Ngrok Multi-Port Tunnel

If you prefer Ngrok:

### Step 1: Install `ngrok`
```powershell
winget install Inconshreveable.Ngrok
ngrok config add-authtoken <YOUR_TOKEN>
```

### Step 2: Configure `ngrok-config.yml`
Copy `scripts/tunnel/ngrok-config.example.yml` to `scripts/tunnel/ngrok-config.yml`:
```yaml
version: "2"
authtoken: <YOUR_TOKEN>

tunnels:
  api:
    proto: http
    addr: 8000
  ws:
    proto: http
    addr: 8080
```

### Step 3: Start Tunnels
```powershell
.\scripts\tunnel\start-ngrok.ps1
```

Ngrok will provide two HTTPS forwarding addresses:
- `https://xxxx-api.ngrok-free.app` -> Port 8000
- `https://yyyy-ws.ngrok-free.app` -> Port 8080

---

## 4. In-App Dynamic Server Configuration (Zero-Recompile)

You **never need to recompile the Flutter APK** when your tunnel URL changes:

1. Open the ChatAPP application on your physical Android phone.
2. On either the **Sign In** screen or **Home** screen, tap the **Tune / Sliders icon** in the top AppBar.
3. The **Server & Tunnel Settings** dialog appears:
   - **API Base URL**: `https://api.yourdomain.com/api/v1` (or your Ngrok API URL).
   - **WebSocket Host**: `ws.yourdomain.com` (or `yyyy-ws.ngrok-free.app`).
   - **Port**: `443`.
   - **Scheme**: `wss`.
4. Tap **Test API Connection** to verify health check with `GET /api/v1/health`.
5. Tap **Save & Apply**. The app immediately switches all HTTP requests and WebSocket connections to the new tunnel without losing credentials.

---

## 5. WebRTC NAT Traversal (STUN & TURN)

When mobile devices connect over cellular carrier networks (4G/5G LTE), carrier-grade symmetric NATs block direct peer-to-peer UDP packet transmission.

### 5.1 STUN Configuration
The app includes Google public STUN servers for standard NAT hole punching:
- `stun:stun.l.google.com:19302`
- `stun:stun1.l.google.com:19302`
- `stun:stun2.l.google.com:19302`

### 5.2 TURN Relay Fallback
For strict symmetric firewalls where STUN alone cannot discover reflexive candidates:
1. In the in-app **Server & Tunnel Settings** dialog, tap **WebRTC TURN / NAT Relay (Optional)**.
2. Enter your TURN relay server parameters:
   - **TURN Server URL**: e.g., `turn:openrelay.metered.ca:80` (or your Coturn server)
   - **TURN Username**: `<username>`
   - **TURN Credential**: `<password>`
3. Or set them in `frontend/.env`:
   ```ini
   TURN_SERVER_URL=turn:openrelay.metered.ca:80
   TURN_USERNAME=openrelayproject
   TURN_CREDENTIAL=openrelayproject
   ```
4. WebRTC will automatically fallback to encrypted TURN relay if direct P2P connectivity cannot be established within the ICE gathering phase.

---

## 6. Troubleshooting & Verification Checklist

| Symptom | Cause | Solution |
| :--- | :--- | :--- |
| **"Connection failed" in settings test** | Local Laravel server not running or wrong tunnel URL | Run `php artisan serve --host=0.0.0.0 --port=8000` and verify tunnel URL ends with `/api/v1`. |
| **WebSocket disconnected / reconnecting** | Port 8080 not tunneled or WSS scheme not selected | Ensure Reverb is running (`php artisan reverb:start`) and WebSocket scheme is set to `wss` with port `443`. |
| **Audio/Video connected but no stream** | Strict carrier symmetric NAT | Configure TURN relay server in app settings as described in section 5.2. |
| **CORS error on broadcast auth** | Missing CORS path | Verified: `backend/config/cors.php` includes `broadcasting/*`. |
