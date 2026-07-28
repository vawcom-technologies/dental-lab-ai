# Branding Directions — Elite Dent

Derived from logo: navy → royal blue gradient, white, soft silver/grey, implant/clinical cues.

Present these three options to Erlan in Week 1. App theme code lives in `mobile/lib/core/theme/`.

---

## Direction A — Clinical Navy (recommended default)

**Feel:** Clean clinic tablet, trustworthy, low distraction chairside.

| Token | Hex | Use |
|-------|-----|-----|
| Primary | `#0B1F3A` | Nav, headers, primary buttons |
| Accent | `#2F6FED` | CTAs, links, focus |
| Surface | `#F5F7FB` | App background |
| Card / panel | `#FFFFFF` | Forms, lists |
| Text | `#0B1F3A` | Body |
| Muted | `#6B7A90` | Secondary labels |
| Success | `#1F8A5B` | Good scan |
| Warning | `#C47B16` | Review / override |
| Danger | `#C0392B` | Bad scan / errors |
| Silver | `#A8B0BD` | Dividers, subtle icons |

**Typography:** `Source Serif 4` for brand wordmark moments; `DM Sans` for UI.

**Motion:** Soft fade + 180ms slide on screen transitions; pulse only on “rescan needed”.

---

## Direction B — Bright Clinical Blue

**Feel:** More modern/product-y; stronger blue from the “Dent” side of the logo.

| Token | Hex |
|-------|-----|
| Primary | `#1A4FBF` |
| Accent | `#4C8DFF` |
| Surface | `#EEF3FF` |
| Text | `#102A56` |
| Muted | `#5A6F94` |

Same type pairing as A. Slightly bolder CTAs; good if client wants a “tech/AI” read.

---

## Direction C — Soft Studio

**Feel:** Quieter waiting-room calm; navy only for brand + critical actions.

| Token | Hex |
|-------|-----|
| Primary | `#132A45` |
| Accent | `#3D6EA8` |
| Surface | `#F8F6F3` |
| Text | `#1A2433` |
| Muted | `#7A8494` |
| Highlight | `#E8EEF6` |

Serif used more often for patient names / case titles. Avoid cream-terracotta look — keep cool undertones so it still reads Elite Dent.

---

## Recommendation

Ship **Direction A** as the working default in the Flutter app until Erlan picks. Swapping is a theme-file change.

---

## Client message (optional short)

> Based on your Elite Dent logo (navy → blue), here are 3 directions:  
> **A Clinical Navy** (clean chairside — my recommendation)  
> **B Bright Clinical Blue** (more tech/product feel)  
> **C Soft Studio** (calmer, navy only for key actions)  
> Tell me which you prefer, or mix (e.g. A colors + C typography).
