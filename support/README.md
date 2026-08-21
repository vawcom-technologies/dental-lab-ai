# Elite Dent — App Store legal / support pages

Static HTTPS pages for **App Store Connect**. No backend, no login.

App: **Elite Dent** · Bundle ID `com.elitedent.dentalLabAi` · Version **1.0.0** · iPad (clinic + lab staff).

## 1. App Store Connect fields

In App Store Connect → the Elite Dent iPad app → **App Information**:

| Field | URL to paste |
| --- | --- |
| **Support URL** | `https://<their-domain>/support` |
| **Privacy Policy URL** | `https://<their-domain>/privacy` |

Impressum (German TMG; not an App Store field, but required on Elite Dent’s public site): `https://<their-domain>/impressum`

## 2. Both URLs must be public HTTPS

Apple opens these in a browser. They must be:

- `https://` (not `http://`)
- on a real public host (not `localhost`, not `127.0.0.1`, not a LAN IP)
- reachable without login, VPN, or basic-auth

Host the folders `support/`, `privacy/`, and `impressum/` at the domain root (each `index.html` becomes `/support`, `/privacy`, `/impressum`). The existing `forgot-password/` page can live on the same host.

## 3. PLACEHOLDERS the client must replace before submit

Search the HTML for `PLACEHOLDER` (visually dashed). Replace every one with real Elite Dent details:

| Placeholder | Where | Replace with |
| --- | --- | --- |
| `support@elitedent.example` | Support, Privacy, Impressum | Real support inbox (mailto must work) |
| `[LEGAL NAME — PLACEHOLDER]` | Privacy, Impressum | Registered company name (e.g. GmbH) |
| `[STREET ADDRESS — PLACEHOLDER]` | Privacy, Impressum | Street + house number |
| `[POSTCODE CITY — PLACEHOLDER]` | Privacy, Impressum | Postcode and city in Germany |
| `[PHONE — PLACEHOLDER]` | Impressum | Public contact phone (TMG) |
| `[VAT ID — PLACEHOLDER]` | Privacy, Impressum | USt-IdNr. if you have one |
| `[HANDELSREGISTER — PLACEHOLDER]` | Impressum | Court + HRB number (if registered) |
| `[MANAGING DIRECTOR — PLACEHOLDER]` | Impressum | Geschäftsführer / owner of record (Erlan Djaniev if that is correct) |
| `[DPO — PLACEHOLDER]` | Privacy | Data protection officer, or “none appointed — contact the controller” |
| `[HOSTING / SUBPROCESSORS — PLACEHOLDER]` | Privacy | EU host, Supabase project region, other processors + DPAs |
| `[DPA / RETENTION — PLACEHOLDER]` | Privacy | Signed clinic DPA and retention periods |

Do **not** put demo passwords, API keys, or patient data on these pages.

## 4. Suggested production paths

```
https://<their-domain>/support
https://<their-domain>/privacy
https://<their-domain>/impressum
```

Optional same-host page already in this repo: `https://<their-domain>/forgot-password`

Pages default to **German**, with an **EN** toggle (stored in `localStorage`). Append `?lang=en` or `?lang=de` to force a language.

## Pages in this set

| Path | File | Purpose |
| --- | --- | --- |
| `/support` | `support/index.html` | Support URL — how to get help, FAQ, reviewer note |
| `/privacy` | `privacy/index.html` | Privacy Policy URL — GDPR notice |
| `/impressum` | `impressum/index.html` | TMG legal notice |

Do not change the Flutter iOS app, `Info.plist`, or signing for these URLs. Paste the HTTPS links in App Store Connect after the client replaces placeholders and the host is live.
