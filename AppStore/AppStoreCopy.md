# Scanny — App Store Connect copy & metadata

Everything you need to paste into App Store Connect (and TestFlight) for the
first submission. Character limits are noted; the provided text fits.

> Two things you must supply yourself before you can submit (see **URLs you
> still need** at the bottom): a **Privacy Policy URL** and a **Support URL**.
> A ready-to-host privacy policy is in `AppStore/PrivacyPolicy.md`.

---

## App Information (set once, applies to all versions)

**App Name** — max 30 chars. Must be unique across the App Store.
```
Scanny
```
If "Scanny" is taken, use one of these (each ≤30 and adds a search keyword):
- `Scanny: PDF Scanner` (21)
- `Scanny – Document Scanner` (27)

**Subtitle** — max 30 chars (shown under the name; great for keywords).
```
Free, on-device PDF scanner
```
Alternatives: `Scan documents to PDF, free` (27) · `Private on-device scanner` (25)

**Primary Category:** Productivity
**Secondary Category:** Utilities

**Content Rights:** Does NOT contain, show, or access third-party content → **No**.

**Age Rating:** answer every question in the questionnaire **None / No**.
Result: **4+**. (No objectionable content, no web access, no ads, no gambling.)

---

## Version Information (for 1.0)

**Promotional Text** — max 170 chars. Can be changed any time without review.
```
Turn paper into clean, searchable PDFs on your iPhone. Auto-crop, OCR, and scanner-style filters. 100% on-device, completely free — no ads, accounts, or tracking.
```
Alternative (mission-led):
```
Clean, searchable PDFs — free and 100% on your device. No subscriptions, no ads, no data harvesting. Basic tools should be free and private. This one is.
```

**Description** — max 4000 chars.
```
Scanny turns your iPhone into a fast, private document scanner. Point your camera at a page — or pick photos you already have — and get a clean, professional PDF in seconds. Everything happens on your device. Nothing is ever uploaded.

WHY IS IT FREE? (WHAT'S THE CATCH?)
There's no catch. Scanning a document is about as basic as it gets, and tools this basic shouldn't cost you a subscription, bury you in ads, or quietly sell your data. Too many everyday utilities have been turned into traps that nickel-and-dime you or harvest your information — Scanny is the opposite. It does one job well, it stays free, and your documents never leave your device. I built the app I wanted to use, and you get to use it too.

WHY SCAN2PDF
• Completely free. No in-app purchases, no subscriptions, no ads.
• 100% on-device. Your documents never leave your iPhone — no servers, no accounts, no tracking.
• Fast and focused. Just the scanning tools you actually need, nothing else.

SCAN ANYTHING
• Capture pages with the camera, with automatic edge detection and perspective correction.
• Multi-page scanning — build a whole document in one session.
• Import existing photos — Scanny finds the page automatically, and you can fine-tune the crop by dragging the corners (with a magnifier for precision) before it's straightened.

LOOKS LIKE A REAL SCAN
Choose the look that fits your page:
• Black & White — a high-contrast "photocopy" that removes shadows and uneven lighting so the paper looks pure white, with brightness and contrast controls to fine-tune it.
• Grayscale — crisp, neutral grayscale.
• Original — keep the photo exactly as captured.

SEARCHABLE PDFs
Scanny reads the text on your pages and embeds it as an invisible layer in the PDF — so you can search, select, and copy text straight from the finished file. Text recognition runs entirely on-device.

ORGANIZE & SHARE
• Reorder or delete pages and rename documents.
• Export a polished PDF and share it anywhere — AirDrop, Files, Mail, Messages, and more.

PRIVATE BY DESIGN
Scanny has no analytics, no ads, no login, and no network access. The app collects no data of any kind. What you scan stays with you.

Perfect for receipts, invoices, contracts, notes, IDs, forms, homework, and anything else you need as a clean, searchable PDF.
```

**Keywords** — max 100 chars, comma-separated, no spaces after commas. (Don't
repeat words already in the name/subtitle; Apple combines terms automatically.)
```
scanner,pdf,document,scan to pdf,ocr,searchable,airdrop,paperless,receipt,notes,doc scan,free
```
(93 characters.)

**What's New in This Version** — for 1.0 you can use:
```
First release of Scanny. Scan with the camera or import photos, auto-crop pages, recognize text, and export clean, searchable PDFs — completely on-device and free.
```

**Marketing URL** (optional): leave blank, or your repo / a simple landing page.

---

## App Privacy ("nutrition label")

This is the part that backs up your promise. In App Store Connect ▸ App Privacy:

- **Data Collection:** choose **"No, we do not collect data from this app."**
  → The label shows **"Data Not Collected."**
- The app uses the **camera** and lets you pick **photos**, but it processes them
  on-device and never transmits them, so neither is "collected."
- **IDFA / Advertising:** No.

Already handled in the build:
- A privacy manifest (`PrivacyInfo.xcprivacy`) declaring **no tracking, no data
  collected, no tracking domains** ships inside the app.
- **Export compliance:** `ITSAppUsesNonExemptEncryption = NO` is set, so App
  Store Connect won't ask about encryption on every build.

---

## TestFlight (Test Information)

**Beta App Description**
```
Scanny is a free, fully on-device document scanner. Scan with the camera or import photos, get automatic cropping and a "scanner" look, then export a searchable PDF you can AirDrop. No accounts, no ads, no data leaves your device.
```

**What to Test**
```
- Scan a multi-page document with the camera (auto edge-detection and cropping).
- Import one or more photos, then drag the corners (a loupe appears) to fine-tune the crop.
- Switch between Color, Grayscale, and B&W looks.
- Export the PDF and confirm you can search/select the recognized text.
- Share/AirDrop the PDF.
- Reorder and delete pages; rename a document.
```

**Feedback Email:** matranc03@gmail.com
**Marketing URL / Privacy Policy:** see URLs below.
**Beta sign-in required:** No.

---

## App Review Information

- **Sign-in required:** No. (No account or login anywhere in the app.)
- **Demo account:** Not needed.
- **Contact:** Mathieu — matranc03@gmail.com
- **Notes for the reviewer:**
```
Scanny is a free, entirely on-device document scanner. There is no account, no backend, and no network connectivity — all image processing and text recognition (OCR) run locally using Apple's Vision and Core Image frameworks.

Camera access is used only for live document scanning. Photo selection uses the system photo picker (PHPicker), which does not require photo-library permission. The app collects no data and includes a privacy manifest declaring this.

To test: tap +, choose "Scan Document" (camera) or "Import Photos", pick the look, then tap "Share PDF" to export a searchable PDF.
```

---

## URLs you still need (required to submit)

App Store Connect requires a working **Privacy Policy URL** and **Support URL**.
You don't have to build a website — easy options:

1. **GitHub Pages / repo (free):** push this repo to GitHub, then use:
   - Privacy Policy URL: `https://github.com/<you>/Scanny/blob/main/AppStore/PrivacyPolicy.md`
   - Support URL: `https://github.com/<you>/Scanny` (or `.../issues`)
2. **A GitHub Gist:** paste `PrivacyPolicy.md` into a public gist and use its URL.
3. **A one-page site** (Carrd, Notion public page, etc.) with the policy and a
   contact email.

Support URL can be as simple as a page that lists your contact email
(matranc03@gmail.com). The Privacy Policy URL must point at the policy text in
`AppStore/PrivacyPolicy.md`.

---

## Screenshots (not copy, but required)

You need screenshots for at least one iPhone size. The simplest accepted set:
- **6.9" iPhone** (e.g. iPhone 16 Pro Max / 17 Pro Max) — 1320 × 2868 px.
- Optionally **6.5"/6.7"** and a **13" iPad** if you enable iPad.

Capture from a real device or the simulator (the list, the page viewer with the
filter bar, and the share sheet make good shots).
```
xcrun simctl io booted screenshot shot1.png
```
