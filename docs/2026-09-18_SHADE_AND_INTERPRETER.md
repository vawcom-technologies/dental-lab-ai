# Shade detection, interpreter, and camera — 18 Sep 2026

Uncommitted work 

---

## Shade detection

Goal: feel faster without changing KAIST outlines (same `CP_teeth_seg.pth`, same canvas, same snake/init iters, classical gap-fill still always runs).

### Implemented

**Client (gallery / camera analyze)**

- Preview JPEG is shown immediately, before the API returns.
- Persist (`POST …/shade-detections`) and analyze (`POST /api/ai/shade/suggest`) run in parallel on the **same** prepared JPEG.
- The analyze path no longer bakes JPEG a second time (preview pixels stay aligned with Lab / overlay).

**Server**

- KAIST weights warm in the background after the API starts listening (does not block `/health` / Railway). First chairside shot after boot should not pay the ~20 s `.pth` load.
- Dual-arch photos: upper and lower snake jobs overlap. CNN (`pseudoER`) stays under `_KAIST_LOCK` (MPS is not dual-safe); initContour / snake / TEM run per arch on CPU.
- Flip retry only when that crop found **no** teeth (unchanged).
- Classical missing-arch fill + uncovered-crown gap-fill still **always** run when needed; they now share **one** classical pass per photo (was up to twice).
- Stage logs: `decode_ms`, `segment_ms`, `classical_ms`, per-crop KAIST `ms` / work size / snake iters, `zones_ms`, `gum_ms`.

### What did not change

- Model, vendor pipeline (pseudoER → initContour → snake → TEM).
- Work-image clamp 256–320 (wide strips keep crown height).
- Chairside defaults `snake=8 / bring_back=48 / evolve=22` in repo config.
- 90 s suggest timeout. Shade is still local-first (not a Railway-only path).

### Timing (from today’s logs)


| Photo                       | Wall  | Breakdown                                                             |
| --------------------------- | ----- | --------------------------------------------------------------------- |
| Tiny single-arch test       | ~13 s | KAIST ~11 s; classical once ~50 ms                                    |
| Real dual-arch ~50 KB smile | ~30 s | Upper KAIST ~17 s then overlapping lower; persist already 201 mid-run |


Almost all remaining wait is CPU snakes, not upload or VITA matching.

---

## Interpreter

Goal: hold-to-talk is **Apple Speech on the iPad**, not Whisper / `/interpreter` audio. Translation is **Apple Translate on-device** when Apple can do the pair; backend only if Apple cannot.

### Implemented

**Speech**

- Hold-to-talk uses `SFSpeechRecognizer` only (no audio upload).
- Hold stays available whenever the catalog language has a speech locale. Missing Apple Speech packs do **not** hide or disable the mic.
- `onDevice: false` so Apple can use network dictation while a pack is still downloading.
- Picking a language (and speech init) warms `SFSpeechRecognizer` in the background so Apple can start fetching assets without locking the button. Listen is still attempted immediately on hold.
- Short tap starts listen and keeps it running (permission sheet / accidental pointer-cancel must not abort). Second tap or a real hold-release (≥450 ms) stops.
- Empty Apple “final” results no longer wipe the live transcript. Stop uses the last non-empty words.
- Mic permission is requested from an on-stage widget.

**Translation (typed text — all catalog languages)**

- Type + Send is **not** gated on Apple Speech. No mic does not mean no Apple Translate.
- Default for every typed pair is Apple Translate. Backend (DeepL → Google → OpenAI → gtx) runs only when Apple reports `unsupported` (or iOS &lt; 18 / missing plugin).
- No language-pack prefetch. Spanish (and other already-on-device pairs) stay instant; German/Arabic/Farsi may still show Apple’s install sheet the **first** time that pair is used (`supported` but not installed is not `unsupported`).
- 503 text lists which keys failed. gtx 429 is logged.

**UX**

- Hint box tap focuses the type field.
- Recent-turn chips are tappable (replay TTS).
- Copy for Apple Translate failure and “nothing heard in {lang}”.

### Tests

- Widget tests mock Apple Translate; fallback test uses `PlatformException(code: unsupported)`.
- `mobile/test/apple_translate_test.dart` for the channel wrapper.

---

## Camera tab

Portrait stills in the inspector and fullscreen viewer used `BoxFit.contain` on a dark grey plate (`#111827`). On an iPad held portrait, a 4:3 still is slightly wider than the pane, so grey bands showed **above and below**. Thumbnails already used `BoxFit.cover`.

`_FilledNetworkPhoto` now defaults to **cover** (same as the grid). The image fills the pane; a sliver of the left/right may crop. Fullscreen pinch-zoom is unchanged.

Live capture already cover-fits the sensor preview; that path was not changed.

---

## Local Debug signing

Release/Profile stay `JUBUU3MW7R` + `com.elitedent.dentalLabAi` in the pbxproj (deployment).

Debug team is **not** in the pbxproj. `Debug.xcconfig` defaults to `JUBUU3MW7R`, then includes gitignored `ios/Flutter/Local.xcconfig`, which on this Mac sets Personal Team `86BF9785N6`. `flutter run` (Debug) uses that; Archive/Release is unchanged.

---

## Decisions (closed)

- **Shade quality is a hard floor.** Do not cut snake/init iters, shrink the KAIST canvas, or skip classical gap-fill. Remaining wait is accepted until a quality-preserving approach exists. Prefer local `10 / 60 / 30` over repo `8 / 48 / 22` if there is any outline difference. Dentist Adjust edges stays the outline workaround.
- **Interpreter fallback is API keys, not pack policy.** Keep Apple Translate first; do not prefetch or treat “supported but not installed” as unsupported. Put `DEEPL_API_KEY` (and/or Google / OpenAI) in `**backend/.env`** so Kurdish and any Apple-unsupported pair skip public gtx. First German/Arabic/Farsi may still show Apple’s install sheet.
- **Commit after device testing.** Nothing is held for a product decision.
- **Apple Speech packs** — never block hold-to-talk on `isAvailable` / pack download. `onDevice: false` (network dictation). Warm the locale in the background when the language is selected so Apple can fetch while they type. Locales that still require a pack may take time or show Apple’s own sheet; the mic stays usable. No Whisper / audio API.

## Files (product)


| Area               | Paths                                                                                                  |
| ------------------ | ------------------------------------------------------------------------------------------------------ |
| Shade server       | `backend/app/ai/shade_analyze.py`, `shade_segment.py`, `shade_segment_kaist.py`, `backend/app/main.py` |
| Shade client       | `mobile/lib/features/shade/shade_page.dart`                                                            |
| Shade tests        | `backend/tests/ai/test_shade_segment_kaist.py`                                                         |
| Interpreter server | `backend/app/ai/interpreter.py`                                                                        |
| Interpreter client | `interpreter_page.dart`, `apple_translate.dart`, `AppDelegate.swift`, l10n                             |
| Interpreter tests  | `mobile/test/interpreter_page_test.dart`, `apple_translate_test.dart`                                  |
| Camera             | `mobile/lib/features/camera/camera_page.dart` (`_FilledNetworkPhoto` → `BoxFit.cover`)                 |                                                                 


