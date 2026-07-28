# Scan fixtures (Week 3)

Synthetic PLYs used to calibrate `backend/app/ai/scan_quality.py` until the client
sends labeled Medit samples (good / bad / blurry / missing margin).

| File | Expected |
|------|----------|
| `good_dense_arch.ply` | `good` |
| `bad_sparse_incomplete.ply` | `bad` + `prompt_rescan` |
| `blurry_noisy_surface.ply` | `blurry` / grainy + `prompt_rescan` |
| `missing_margin_flat.ply` | `missing_margin` + `prompt_rescan` |

Drop real client PLYs here and re-tune thresholds when they arrive.
