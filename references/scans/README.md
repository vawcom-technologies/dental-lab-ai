# Scan fixtures

Synthetic point clouds for `backend/app/ai/scan_quality.py` (see
`test_reference_fixtures`). The real calibration set is the labelled Medit
"Anatomy" exports noted next to each threshold in that file.

| File | Expected |
|------|----------|
| `good_dense_arch.ply` | `good` (plus the low "point cloud" note) |
| `bad_sparse_incomplete.ply` | `bad` — too few points, flat |
| `blurry_noisy_surface.ply` | `bad` — noisy surface, flat |
| `missing_margin_flat.ply` | `bad` — flat / collapsed export |
