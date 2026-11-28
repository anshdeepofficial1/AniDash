# AniDash Go device pairing contract

This contract is the website counterpart of **AniDash → Settings → Devices**.

## Required flow

1. AniDash Go creates a cryptographically random, single-use session that expires in five minutes.
2. The website displays both a QR link and a manual code.
3. The Android app reads the code and calls the session endpoint to show the requesting device before asking the user to approve it.
4. The app sends credentials and sync preferences only after the user taps **Yes, connect**.
5. The website browser polls the status endpoint. After approval, the server establishes the browser login using a Secure, HttpOnly, SameSite cookie and invalidates the pairing code.

## QR format

```text
https://anidashgo.vercel.app/connect?code=<PAIRING_CODE>
```

The QR code must contain only the one-time pairing code. It must never contain an AniList/MAL token, password, or user data.

## Inspect a pending device

`GET /api/device-pair/session?code=<PAIRING_CODE>`

Success (`200`):

```json
{
  "success": true,
  "session": {
    "expiresAt": "2026-11-26T12:05:00.000Z",
    "device": {
      "name": "Chrome on Windows PC",
      "browser": "Chrome 142",
      "os": "Windows 11",
      "location": "Punjab, India"
    }
  }
}
```

Use `400` for an invalid code and `410` for an expired or consumed code. Never return IP addresses or browser fingerprints to the app.

## Approve a device

`POST /api/device-pair/approve`

The app sends:

```json
{
  "code": "<PAIRING_CODE>",
  "accounts": {
    "anilist": {
      "accessToken": "<SERVER_ONLY_SECRET>",
      "userId": "123",
      "username": "Example"
    },
    "myanimelist": {
      "accessToken": "<SERVER_ONLY_SECRET>",
      "refreshToken": "<SERVER_ONLY_SECRET>",
      "userId": "456",
      "username": "Example"
    }
  },
  "sync": {
    "schemaVersion": 1,
    "preferences": {
      "playbackSourceKind": "native",
      "nativeSource": "hianime",
      "player": {
        "preferredAudioLanguage": "dub",
        "defaultQuality": "Auto",
        "autoEnableSubtitles": true
      },
      "hindiSource": null,
      "hindiSourceEnabled": false
    },
    "capabilities": [
      "tracker_lists",
      "watch_progress",
      "source_preference",
      "audio_language",
      "hindi_source_state"
    ]
  },
  "client": {
    "platform": "android",
    "appVersion": "1.0.0",
    "buildNumber": "1"
  }
}
```

Return `200` or `201` only after the approval has been atomically stored. Return `400` for an invalid code, `409` for an already-consumed code, and `410` for an expired code.

## Browser completion

The browser should poll a status endpoint such as:

`GET /api/device-pair/status?code=<PAIRING_CODE>`

While pending, return `202`. After approval, establish the website session and return `200`. After denial/expiry, return `410`. Do not send tracker tokens to browser JavaScript or local storage.

## Sync rules

- AniList/MAL lists and watch progress remain the source of truth and sync when the same tracker account is active on both clients.
- Preserve the pairing-time playback language (`sub`, `dub`, and source-specific Hindi availability), source identity, and quality snapshot. Do not silently replace an unavailable Hindi source with a different language.
- Treat app source IDs as hints because a website provider may use a different ID. Map by normalized provider/language capability and show the selected fallback to the user.
- Downloads, cached images, and device-only settings remain local.
- The current website API does not expose a device-list, last-active, or remote-revoke endpoint. Android therefore keeps a local verified pairing history and never presents it as live server activity.
- Encrypt provider credentials at rest, redact request bodies from logs, rate-limit every pairing endpoint, and invalidate the pairing code immediately after first use.
