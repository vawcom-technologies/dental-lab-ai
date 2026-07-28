# Dental Lab AI — Flutter feature scaffolds
#
# Implement each feature in its folder. Keep screens thin; put logic in
# services/ and models/ beside the UI when features grow.

# Existing (Week 1)
#   auth/          login
#   patients/      list + create

# Week 2
#   camera/        frontal/left/right, ≤10 photos
#   scans/         PLY pick + validation result + rescan prompt
#   offline/       Drift/SQLite cache + sync queue  → also core/offline/

# Week 3
#   shade/         AI suggest + mandatory manual override
#   shapes/        overlay position/resize/rotate
#   scan_body/     diameter → manufacturer UI

# Week 4
#   chat/          text / voice / image + read receipts
#   notifications/ inbox

# Shared
#   cases/         case list/detail hub linking the above
