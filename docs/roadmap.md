# Roadmap: roles, sharing, status flow

Agreed rules for the admin / lab / dentist rework. Every phase builds against this file.

## 1. Rules

### Accounts and signup
- One **admin**. Anyone can sign up as a **dentist** or a **lab**; each lab is one login.
- The admin approves or rejects **every** signup.
- **Reject**:
  - deletes the account and puts the email on the **reject list**;
  - signing up again with that email shows a "registration rejected" error; so does trying to sign in.
- **Removing someone from the reject list** only lets them sign up again; it doesn't approve them.
- **Approving a dentist**: the admin may also choose their lab, or leave it empty.
- **Clinic name** is collected at signup and is display-only. Dentists are always shown with **lab name + clinic name**.
- The admin can see everything, do everything, and override anything. **Every action a lab or dentist can take, the admin can take too**: each endpoint built in later phases accepts the admin as well as the role it's for.

### Lab membership
- **Dentist without a lab**:
  - sees a **lab picker** and can't do anything else until a lab accepts them;
  - one pending request at a time;
  - if the lab rejects them they can ask again (labs keep no reject list).
- **Admin** can move a dentist straight to any lab; that lab's approval isn't needed.
- **Lab** can request a dentist's removal; the **admin approves**. Dentists can't leave on their own.
- **When a dentist is removed**:
  - they go back to having no lab (lab picker, plus the admin's "unassigned dentists" list);
  - their patients stay theirs, and sharing with other dentists stays in place;
  - the old lab loses access to open cases, and any case under review goes back to "in progress";
  - the old lab keeps **view-only access to completed cases**.

### Who can find whom
| Who | Sees |
|---|---|
| Dentist choosing a lab, or starting a transfer | Lab names only, searchable; hidden labs left out |
| Lab, in the directory page (built later) | Labs with their dentists listed under them, respecting both hide settings |
| Admin | Everything |

- **Lab settings**: "hide us from other labs" and "hide our dentists from other labs". Both off by default.
- A hidden lab can't be found by new dentists, so it only gets dentists the admin assigns to it.

### Patients: ownership and access
- **Owner**: every patient is owned by a dentist.
- **Creating patients**:
  - a dentist creates patients for themselves;
  - a lab creates them for **one of its own dentists**, or **asks another lab to take the case**. The receiving lab then chooses one of its dentists.
- **When a lab creates a patient**:
  - the lab is recorded as the creator in the audit log and the case history;
  - the patient is shared with that lab automatically.
- **A lab can move a patient** to a different dentist in the same lab, but only a patient the lab has access to (shared with it, or created by it). Labs never have standing access to their dentists' patients. The previous dentist loses access; it's a move, not a share.
- **A lab only sees patients shared with it.**
- **Sharing with your own lab**: immediate.
- **Sharing with a dentist in the same lab**: the dentist raises a ticket and the lab approves or rejects it.
  - While the ticket is open, the lab can see the full patient record.
  - Raising a ticket does **not** count as sharing with the lab.
- **Sharing with a dentist in another lab**:
  - the dentist raises a ticket with their own lab;
  - their lab sends it on to the other lab;
  - the other lab accepts it and chooses which of its dentists gets the patient;
  - both sides keep access.
- **Uploading scans, shade analyses and smile previews**:
  - **dentists** the patient is shared with can, and their uploads move the status;
  - **labs cannot**: they only review and give remarks.

### Messaging (one-to-one only; no group chat)
Two users can message each other if any of these is true:
- they're dentists in the same lab;
- one is a dentist and the other is their own lab;
- both are labs;
- one of them is the admin;
- both have access to the same patient. This lets dentists in different labs talk once a patient is shared between them.

### Status flow (decided only on the server)
| From | To | Trigger |
|---|---|---|
| awaiting scans | in progress | A dentist uploads a scan, or assigns one from the Scan Inbox |
| in progress | under review | **Automatically** when a scan, a saved shade analysis and a saved smile preview all exist **and** the patient is shared with the lab. Also re-checked whenever the patient gets shared with the lab. |
| in progress | under review | **"Submit to lab"** button. If items are missing, a warning names them and the dentist must confirm. |
| under review | completed | Lab approves |
| under review | rejected | Lab rejects; **remarks required** and kept in the case history |
| rejected | in progress | The dentist's first change to any item. **Automatic submission stays off** until the dentist submits by hand. |
| under review | (stays) | A scan, shade or smile is replaced; the lab is notified |
| completed | under review | A scan, shade or smile is replaced, after a "this will reopen the case" prompt; the lab is notified |

- **Which lab reviews**: the patient owner's lab. Other labs it's shared with only see the status.
- **Under review or completed**: items can only be **replaced**, not deleted.
- **Manual status dropdown**: removed. The admin can still change any status, and each change is logged.

### Deactivate vs delete
- **Deactivate**: they can't sign in (existing sessions stop on their next request). Lab, patients and sharing are kept. The admin can reactivate.
- **Delete permanently**: the rules below. Can't be undone.

### Admin powers
- **Moving a dentist** to another lab = leaving the old lab (same effects as a removal) and joining the new one. The admin can also remove a dentist from their lab directly.
- **Changing a status** works like the matching normal action. The note becomes the event's remarks; setting **rejected** uses it as the rejection remarks and turns automatic submission off. The automatic rules are not re-run. The dentist and the reviewing lab are notified.
- **Reassigning a patient**: to a lab, optionally straight to one of its dentists. Without a dentist, the patient waits for that lab, which gets access so it can choose.

### Deletion
- **Patients are never deleted** when an account is deleted.
- **Deleting a dentist** (by the admin, or the dentist themselves from Settings):
  - the account is deactivated and the personal details cleared;
  - their patients and uploads stay;
  - their patients become **unassigned**.
- **Unassigned patients**:
  - the admin sees them in a separate list, with full history;
  - the admin can reassign them to any lab, which then chooses the dentist;
  - until then, the old lab and everyone the patient was shared with keep the access they had.
- **Deleting a lab**:
  - its dentists go back to having no lab (lab picker, plus "unassigned dentists");
  - cases it was reviewing go back to "in progress";
  - patients are untouched.
- **Never-approved accounts** (pending or rejected signups) are deleted completely. Every approved account is kept as a tombstone instead: name "Deleted user", contact details cleared, login removed, email freed for a future signup.

## 2. Database changes
| Change | Purpose |
|---|---|
| `profiles.lab_id`, `profiles.hidden_from_labs`, `profiles.hide_dentists` | Lab membership; the lab hide settings |
| `profiles.unassigned_reason`, `profiles.unassigned_at` | Why a dentist has no lab (`no_lab` / `removed` / `lab_deleted`) and since when |
| `profiles.created_at`, `profiles.anonymized_at` | Signup date; set when an account is permanently deleted |
| New `rejected_signups` table | The reject list |
| New `lab_requests` table (join / remove) | Dentist join requests and lab removal requests |
| `patient_access` (already exists, already has pending/approved/rejected) | Sharing tickets |
| New `lab_transfers` table (Phase 3) | Cross-lab transfers, both from a dentist and from a lab asking another lab to take the case: the request, both labs' decisions, the chosen dentist |
| `patients.auto_submit` | Turns automatic submission off after a rejection |
| `patients.unassigned_at`, `patients.waiting_lab_id` | Marks patients whose owner was deleted, or that are waiting for a lab (`waiting_lab_id`) to choose a dentist. While a lab-created patient waits, the creating lab is the temporary owner and the admin's list labels the patient "waiting for lab". |
| New `case_events` table | Case history: created, submitted, approved, rejected with remarks, updated, reassigned, admin override |
| **Delete** (Phase 2): `api/cases.py`, the `Case` model, and the `/api/cases` calls in `mobile/lib/core/api/api_client.dart` | All unused; the legacy models are tangled into reports and exports, so this goes with the status-flow work |
| **Rewrite**: `services/account_deletion.py` | Deactivate instead of wiping, and never delete patients |

All access checks go through **one function**: what is this user's relationship to this patient (owner, shared dentist, lab, admin), and can these two users message each other.

## 3. Phases
0. **Foundation** (done: `backend/migrations/018_labs_admin.sql`): the database changes above, the deletion rewrite, admin read access through the shared access check.
1. **Admin** (backend done: `backend/app/api/admin.py`):
   - dashboard with counts and a queue of pending signups;
   - approve (optionally choosing a lab) or reject;
   - reject list with a remove option;
   - users grouped by lab;
   - **unassigned dentists**, with assign / move to a lab;
   - approving lab requests to remove a dentist;
   - all patients, including **unassigned patients**, with reassignment;
   - changing any case's status.
2. **Status flow**:
   - the automatic status rules, and the submit and review endpoints;
   - replace instead of delete, and the lab notified of changes;
   - removing the manual dropdown;
   - uploads blocked for labs;
   - notifications;
   - a basic Approve / Reject-with-remarks screen for labs.
3. **Lab**:
   - creating patients (for its own dentist, or asking another lab);
   - moving a patient to another of its dentists;
   - dentist join requests, the dentist list, removal requests;
   - the sharing-ticket inbox and cross-lab transfers;
   - the review queue with case history;
   - hide settings;
   - the lab directory comes later.
4. **Dentist**:
   - the blocking lab picker, and lab and clinic names shown everywhere;
   - the new sharing flow;
   - "Submit to lab" with the missing-items warning;
   - a banner showing rejection remarks;
   - replace instead of delete;
   - messaging limited to the rules above.
