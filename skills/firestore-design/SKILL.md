---
name: firestore-design
description: >-
  INVOKE/LOAD WHEN designing, reviewing, debugging, or optimizing Firestore
  data models and access patterns. Especially use when a feature reads many
  documents, uses per-item `get()`/`getAll()`/BatchGet, has sparse optional
  per-user metadata, reports high Firestore read counts, high NOT_FOUND reads,
  listener/read bloat, or asks whether a Firestore schema is KISS/native.
  Keywords: Firestore, read bloat, sparse docs, NOT_FOUND, BatchGetDocuments,
  RunQuery, Listen, onSnapshot, documentId in query, data access audit,
  collection layout, tags, cursors, overlays, query fanout, cost.
---

# Firestore Design

## Core lesson

Firestore is cheap and pleasant when a query naturally returns the few documents
that matter. It becomes expensive and misleading when the app asks Firestore to
prove absence for many documents.

The prime failure mode:

```ts
// Bad for sparse optional state.
const refs = visibleThreadIds.map((id) => overlays.doc(id));
const snaps = await db.getAll(...refs);
```

If most overlay docs do not exist, this still creates billable reads and
`NOT_FOUND` audit noise. The app did not need 200 proofs of absence; it needed
the 3 overlay rows that exist.

Prefer:

```ts
// Better: query existing rows, then intersect with known-visible IDs.
for (const batch of chunks(uniqueVisibleIds, 30)) {
  const snap = await overlays.where(FieldPath.documentId(), 'in', batch).get();
  for (const doc of snap.docs) applyOverlay(doc.id, doc.data());
}
```

Or, if the overlay can be queried by owner/status/tag directly, model it so the
query returns the target rows without scanning or sparse lookup.

## Golden rules

1. **Query for existence; do not prove absence at scale.**
   Missing docs are not free. Avoid per-visible-item `get()` / `getAll()` for
   optional sparse records.

2. **Make document existence mean something.**
   If `thread_assignments/{threadId}` exists, it should mean “this thread has
   tags.” Delete empty assignment docs. Do not keep empty marker docs just to
   remember absence.

3. **Start from the user/system story, not from collections.**
   Ask: “The user opens X. What small set of rows does the UI actually need?”
   Then design the collection/query so Firestore naturally returns that set.

4. **Keep canonical ownership clear.**
   If Gateway owns visible threads, let Gateway produce the visible set. Local
   app metadata can decorate those rows, but must not redefine visibility unless
   that is explicitly the product contract.

5. **Bound every fanout.**
   If a query has to fan out by document ID, chunk it to Firestore limits and
   ensure the input list is already bounded by the user-facing page size.

6. **Treat listeners as reads.**
   `onSnapshot` / Listen is not magic. Initial listener hydration and every
   matching change consumes reads. A page with 7 listeners per open thread is a
   read architecture, not just a realtime convenience.

7. **Do not refresh the same doc from every listener callback.**
   A common listener bloat pattern is: open N listeners, then each callback does
   `sessionRef.get()` for auth/visibility. Prefer one session listener as the
   authoritative local state, or a shared cached visibility gate.

8. **Indexes are part of the schema.**
   Any query requiring a composite index is not “just code.” If deploy needs a
   manual index or migration, stop and surface it.

9. **Measure by path and principal before redesigning.**
   Cloud Monitoring’s Firestore read metric is project-wide. It tells you the
   fire exists, not who lit it. Use temporary Data Access audit logs for path
   and service-account attribution, then disable them.

## Design patterns that usually work

### Sparse per-user overlays

Use an owner-scoped collection whose docs exist only when there is actual state:

```txt
user_overlay_owners/{ownerHash}/thread_assignments/{threadId}
```

Read strategy:

- Get canonical visible thread IDs from the owning service/query.
- Query existing overlay docs with document-ID `in` chunks, or query by a real
  indexed field such as `tag_ids array-contains tagId`.
- Intersect results with visible IDs in memory.
- Missing doc means the default (`[]`, `null`, unseen, unpinned, etc.).
- Clearing state deletes the doc.

### Tags

Good semantics:

```txt
thread_assignments/{threadId} exists => tag_ids.length > 0
```

Operations:

- `setThreadTags(threadId, [])` deletes the assignment doc.
- Deleting a tag removes it from assignments; if no tags remain, delete the
  assignment doc.
- Listing visible rows queries existing assignments and decorates the visible
  row set.

Avoid:

- Writing `tag_ids: []` docs.
- Batch-getting one assignment doc per visible thread.

### Read cursors / freshness markers

Good semantics:

```txt
thread_cursors/{threadId} exists => user has explicitly seen marker state
missing doc => unseen/fresh/default
```

Read strategy:

- Query existing cursor docs for visible thread IDs.
- Missing cursor defaults in memory.
- If the cursor is purely client-local product state, question whether it needs
  Firestore at all.

### Realtime thread view

Before adding listeners, count them:

```txt
open thread:
  1 session doc listener
  1 outbox listener
  1 transcript listener
  1 inbox listener
  1 attention listener
  1 active dream listener
  1 active subagent listener
  N child outbox listeners
```

That is a lot. It may be correct, but it must be deliberate.

Ask whether a single materialized `thread_activity/{threadId}` doc, one
append-only stream, RTDB token stream, or Gateway-side event feed can replace
multiple Firestore listeners.

## Audit workflow for production read bloat

### 1. Confirm aggregate shape

Use Cloud Monitoring for `firestore.googleapis.com/document/read_count`, grouped
by `metric.labels.type`:

- `LOOKUP` — document gets / batch gets.
- `QUERY` — query reads.
- `NOT_FOUND` — missing document lookups; often sparse-read poison.

### 2. Temporarily enable Data Access audit logging

For Firestore Native, enable audit config on `datastore.googleapis.com` with
`DATA_READ`. Entries appear under `protoPayload.serviceName="firestore.googleapis.com"`.

Keep the window short. This can be noisy/billable.

### 3. Query the correct log

```bash
gcloud logging read \
  'logName:cloudaudit.googleapis.com%2Fdata_access AND protoPayload.serviceName="firestore.googleapis.com" AND timestamp>="START_ISO"' \
  --project=symph-aria \
  --limit=50000 \
  --format=json
```

Attribute by:

- `protoPayload.authenticationInfo.principalEmail`
- `protoPayload.methodName` (`BatchGetDocuments`, `RunQuery`, `Listen`, etc.)
- `protoPayload.metadata.keys` path prefixes
- status code (`1` commonly maps to not found/cancel-ish noise depending method)

### 4. Disable audit logging and verify

Do not leave DATA_READ on.

Verification must show the datastore audit config has no DATA_READ entry, or no
`datastore.googleapis.com` audit config at all.

## Review checklist

Before approving a Firestore design or diff, answer:

- What user action causes this read?
- What exact document/query/listener path fires?
- Is the result set naturally small, or are we asking Firestore to prove many
  negatives?
- What is the maximum fanout per page/session/user?
- What does missing data mean, and is that represented by absence instead of an
  empty doc?
- Are listeners necessary, and how many initial documents do they hydrate?
- Are we accidentally doing a document `get()` inside every listener callback?
- Are writes deleting rows when state becomes empty?
- What other services read/write the same collections?
- How will we verify in production by principal + path, not vibes?

## Red flags

- `Promise.all(ids.map((id) => ref.doc(id).get()))` on optional docs.
- `db.getAll(...refs)` where `refs` came from visible UI rows and many may not
  exist.
- Empty docs retained to mean “nothing here.”
- One page opening many `onSnapshot` listeners without a read budget.
- Listener callbacks each performing their own auth/session `get()`.
- Cloud Monitoring read spikes investigated without Data Access attribution.
- A schema where the only way to answer “which rows matter?” is to first read
  every candidate row.
