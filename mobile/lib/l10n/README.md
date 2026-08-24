# Localization (Elite Dent)

**Strategy:** English is the source of truth. German is machine-filled to 100% coverage. Developers write EN; users mainly use DE.

## Runtime (today)

`lib/core/l10n/app_localizations.dart` — hand-maintained `_en` / `_de` maps + getters.  
Use `AppLocalizations.of(context).…` for all user-visible chrome.

Default locale for new installs: **`de`** (`LocaleController`).

## Long-term pipeline (ARB)

| File | Role |
|------|------|
| `lib/l10n/app_en.arb` | Template / source (exported from `_en`) |
| `lib/l10n/app_de.arb` | German (filled by script) |
| `l10n.yaml.pending` | Flutter gen-l10n scaffolding — **not active** (see below) |

### Why `l10n.yaml.pending` (not `l10n.yaml`)

Flutter treats a root `l10n.yaml` as a signal to run gen-l10n. That requires `flutter: generate: true` in `pubspec.yaml`. Enabling generation today would conflict with the hand-written `AppLocalizations` in `lib/core/l10n/`. Until call sites migrate, keep the config renamed so `flutter pub get` / builds do not try to generate.

When migrating: rename to `l10n.yaml`, set `flutter: generate: true`, and keep `output-class: AppLocalizationsGen` (already in the pending file) to avoid colliding with the existing class.

### Commands (from `mobile/`)

```bash
# 1) Dump current maps → ARB
dart run tool/export_l10n_arb.dart

# 2) Fill any DE keys missing vs EN
dart run tool/fill_missing_de.dart

# Optional: higher-quality MT
DEEPL_API_KEY=your_key dart run tool/fill_missing_de.dart
```

### Future PRs

1. Add the EN string + getter to `AppLocalizations` (and `_en` map).
2. Run `export_l10n_arb.dart` then `fill_missing_de.dart` so DE stays at 100%.
3. Spot-check DE in the app — do **not** hand-translate every key.
4. When ready, migrate to `flutter gen-l10n` using these ARB files; keep EN as template.
