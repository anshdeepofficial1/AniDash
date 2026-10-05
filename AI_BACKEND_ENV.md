# AniDash AI backend configuration

The Android client talks only to `https://anidashweb.vercel.app/api/ai`. Provider secrets belong in the Vercel environment and must never be added to `keys.json`, Dart source, Gradle, or the APK.

Supported server-side variables:

- `CEREBRAS_API_KEY`, optional `CEREBRAS_API_URL`, `CEREBRAS_MODEL`
- `GROQ_API_KEY`, optional `GROQ_API_URL`, `GROQ_MODEL`
- `GEMINI_API_KEY`, optional `GEMINI_MODEL`
- `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_AI_TOKEN`, optional `CLOUDFLARE_ACTION_MODEL`
- `MISTRAL_API_KEY`, optional `MISTRAL_API_URL`, `MISTRAL_MODEL`
- `OPENROUTER_API_KEY`, optional `OPENROUTER_API_URL`, `OPENROUTER_MODEL`, `OPENROUTER_SITE_URL`, `OPENROUTER_APP_NAME`

Provider fallback order keeps the existing specialist routes first, followed by Cerebras, Groq, and Mistral. OpenRouter is attempted last as the emergency fallback. Providers that do not have their required server-side key configured are skipped automatically.

The app builds and keeps native AniDash features available when none are configured. AI requests then return a user-friendly unavailable state instead of fabricated answers.
