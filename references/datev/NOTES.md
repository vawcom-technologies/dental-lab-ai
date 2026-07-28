# DATEV XML dataset (client-provided structure)

**Clarification:** Earlier notes said “Datext” — this sample is **DATEV** (German accounting / document exchange). Treat DATEV as the XML target unless the client corrects us.

## What’s in this folder

| File | Purpose |
|------|---------|
| `datev_demo.xml` | Simplified DATEV-like sample (Header + Invoice/Customer) |
| `NOTES.md` | This file |

## Known gaps vs real DATEV import

- Must validate against **official DATEV XSD**
- Missing typical fields: Beraternummer, Mandantennummer, Formatkennung
- Production packages are often a **ZIP** with `document.xml` + receipts (PDF/JPG)
- Encryption method for patient-related exports still TBD (GDPR)

## Mapping for dental lab (working assumption)

| Dental field | DATEV-ish placement |
|--------------|---------------------|
| Patient name / address | `Customer` |
| Case / invoice id | `InvoiceNumber` |
| Case date | `InvoiceDate` |
| Amount (if billing) | `Amount` |
| Shade / scan / notes | Extended custom nodes until official schema confirmed |

Ask client: Is export for **billing/DATEV accounting**, or a **lab case packet** that only *looks* DATEV-like?
