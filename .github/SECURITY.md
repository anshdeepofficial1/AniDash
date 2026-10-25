# Security Policy

At AniDash, we take the security of our application, our users' privacy, and sensitive credentials seriously. This document outlines the security procedures, supported versions, and responsible disclosure processes for the repository.

---

## Supported Versions

We actively provide security updates, bug fixes, and vulnerability patches for the current major release stream:

| Version | Supported | Status |
| :--- | :---: | :--- |
| **2.1.x** | :white_check_mark: | Active (Current Release) |
| **2.0.x** | :white_check_mark: | Maintenance Only |
| **< 2.0.0** | :x: | End of Life (Deprecated) |

Users are strongly encouraged to upgrade to the latest available release from [GitHub Releases](https://github.com/anshdeepofficial1/AniDash/releases).

---

## Reporting a Vulnerability

If you discover a security vulnerability, sensitive token exposure, or security-related flaw in AniDash, please report it **responsibly and privately**. **Do not open a public GitHub issue for security vulnerabilities.**

### Preferred Reporting Channels

1. **GitHub Private Vulnerability Reporting**:
   - Navigate to the **[Security Advisories](https://github.com/anshdeepofficial1/AniDash/security/advisories/new)** tab in this repository.
   - Click **"Report a vulnerability"** to open a confidential draft advisory directly to repository maintainers.

2. **Direct Maintainer Contact**:
   - **Email**: `anshdeepofficial1@gmail.com`
   - **AniList**: [Profile #8013267](https://anilist.co/user/8013267/)
   - Subject line: `[SECURITY] AniDash Vulnerability Report - <Brief Description>`

### Information to Include in Your Report

To help us triage and resolve the issue quickly, please include:
- Description of the vulnerability and its potential impact.
- Step-by-step reproduction instructions or Proof of Concept (PoC).
- Affected version(s) and operating platform (Android, macOS, iOS).
- Any proposed mitigations or patch suggestions (if known).

---

## Response & Disclosure Process

1. **Acknowledgment**: We aim to acknowledge receipt of security reports within **24 to 48 hours**.
2. **Investigation & Triage**: Maintainers will verify the vulnerability, evaluate severity, and determine root cause.
3. **Patch Development & Testing**: A fix will be developed in a private branch or advisory fork and tested across target platforms.
4. **Release & Advisory**: A patched release will be published on GitHub, followed by a coordinated public security disclosure acknowledging the researcher (with permission).

---

## Security Best Practices in AniDash

- **Zero Hardcoded Secrets**: Production API keys, developer tokens, and sensitive signing materials are never stored in plain text within public repository tracking.
- **Sandboxed Local Storage**: User preferences, session tokens, and AniList credentials are stored using platform-encrypted sandboxed secure storage.
- **Client-Side Privacy**: AniDash does not collect, log, or sell personally identifiable information (PII). All playback tracking and sync operations communicate directly with official user-authorized services (e.g. AniList, SIMKL, MAL).
