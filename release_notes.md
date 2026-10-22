# AniDash v2.1.4 — Story Arc Auto-Alignment & Next Up Episode Parity

AniDash v2.1.4 introduces automatic story arc alignment, smooth horizontal arc chip centering, precise episode list auto-scrolling, and resolves next-up episode parity between the Home Screen and the Episodes view.

## 🌟 What's New in v2.1.4

### ⛩️ Automatic Story Arc & Range Alignment
- **Target Arc Auto-Selection**: Opening any anime with story arcs (e.g. One Piece, Bleach, Naruto, Black Clover, Hunter x Hunter) automatically determines your current progress and activates the exact arc containing your current episode.
- **Horizontal Arc Centering**: The top horizontal arc bar now automatically scrolls to center the active story arc chip, giving immediate visual clarity without manual horizontal scrolling.
- **Direct Episode Focus**: The episode list below immediately displays the active arc's episodes and auto-scrolls smoothly to your exact current episode.
- **Numeric Range Parity**: For series without predefined story arcs or when numeric ranges are preferred, the matching 50-episode range (e.g. 251–300, 301–350) is automatically activated and centered.

### 🎯 Next Up Episode Parity & Accurate Continuation
- **Unified Next-Up Engine**: Eliminated the off-by-one bug where the Episodes area was prematurely advancing to the following episode (e.g. jumping to Episode 338 when Episode 337 was yet to be watched).
- **Home & Details Synchronization**: The "NEXT UP / CONTINUE" card in the Episodes view now uses the identical progress and completion verification algorithm as the Home Screen's Continue Watching card and Watch History.
- **Seamless Player Sync**: The In-Player Episodes Panel also honors story arcs and auto-aligns with your active playback episode.

### 📚 Expanded Verified Story Arcs
- Added verified saga boundaries for **Hunter x Hunter (2011)** (Hunter Exam, Heavens Arena, Yorknew City, Greed Island, Chimera Ant, 13th Chairman Election).
- Hardened AniList ID, MAL ID, and title variations matching across all verified series.

## 🛠️ Verification
- Static analysis verified: 0 errors, 0 warnings (`dart analyze`).
- Full unit test suite verified: 119/119 tests passed (`flutter test test/unit/`).
- Available APK Variants: Universal, arm64-v8a, armeabi-v7a, x86_64.

**Version:** 2.1.4 (Build 149)
