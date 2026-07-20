# Rails Markup 1.2 security and synchronization design

Date: 2026-07-20

## Objective

Close the three release blockers assigned to Codex without changing the FAB or
install work owned by Claude:

1. protect the browser toolbar API with the same host authentication boundary as
   the dashboard and normal Rails CSRF protection;
2. remove MCP credential-forwarding and make tool failures recoverable;
3. make the browser toolbar and Rails database converge across create, edit,
   status, delete, offline periods, and server-side agent actions.

Turbo cache lifecycle, dashboard pagination, standalone WEBrick parity, and
mobile interaction work are separate follow-up scopes.

## Chosen approach

Use Rails as the authoritative store and keep localStorage as an offline cache
plus durable desired-state outbox. Synchronization uses the annotation's client
UUID as its idempotency key; the numeric Rails ID returned by the server is kept
as a convenient mapping, not as the only way to identify a queued mutation.

The MCP server exposes five safe canonical tools and retains old names as
deprecated adapters through 1.3.0. Adapters translate names and arguments but do
not preserve caller-controlled URL/token behavior or mutating reads.

This approach is preferred over replaying a chronological request log because a
single desired state per client UUID naturally collapses create-followed-by-edit
and repeated offline changes. It is preferred over localStorage-only behavior
because dashboard and MCP actions must be visible in the browser.

## Browser API security boundary

`RailsMarkup::AnnotationsController` will inherit from
`RailsMarkup.config.base_controller_class.constantize`, matching the dashboard.
It explicitly declares `protect_from_forgery with: :exception`; the current
`null_session` override is removed. Installation requires an
`ActionController::Base`-compatible configured base controller and normal Rails
forgery protection in deployed environments. Toolbar fetches continue to send
same-origin credentials and the page CSRF token.

Consequences:

- host authentication callbacks on the configured base controller protect both
  dashboard and toolbar API;
- a request without a valid Rails session/host authorization is rejected by the
  host controller;
- a state-changing request without a valid CSRF token is rejected;
- health and pull endpoints also share the host authentication boundary;
- external MCP/CLI endpoints remain separate and use configured bearer-token
  authentication outside development.

The generated auth controller remains the explicit host customization point. Its
documentation will state that the chosen base controller must actually enforce
authorization; inheriting a public controller intentionally produces a public
toolbar.

## Idempotent synchronization API

Add authenticated browser endpoints:

- `GET /api/annotations?page_url=...`
  returns annotations for the exact page URL, ordered deterministically;
- `PUT /api/annotations/:client_uuid`
  creates or updates the annotation identified by the client UUID and returns
  the complete server representation;
- `DELETE /api/annotations/:client_uuid`
  idempotently removes that annotation and returns 204 even when already absent.

The existing session/create and numeric transition routes remain during 1.2 for
compatibility, but the toolbar uses the UUID synchronization endpoints.

The PUT request accepts the same bounded content, page, target, metadata, and
selection fields as create plus a validated status. `client_uuid` is taken from
the route and must be nonblank after trimming and no longer than 64 characters.
An absent path segment does not match a route and returns 404; whitespace or an
otherwise invalid UUID returns 422. The compatibility POST endpoint normalizes a
blank `clientId` to nil so it cannot store an empty unique value. A database
unique index remains the final concurrency guard.

For PUT, an existing UUID defines the same logical browser object. Differences
in editable fields are updates, not collisions, so PUT never returns an
“incompatible UUID” 409. The server accepts browser-owned fields (`content`,
`intent`, `severity`, `selected_text`, `target`, and `page_url`) and only these
browser metadata keys: `tool`, `url`, `localId`, `sessionId`, and `screenshot`.
It merges those keys into existing metadata while preserving server-owned
`author` and unknown server-side keys. It does not accept `thread`, author/user
identity, timestamps, or a browser-supplied server ID. Status is accepted only
for the toolbar's explicit status action. Validation failures return 422. The
old POST replay endpoint keeps its exact-replay/409 behavior for compatibility
and also rejects client-supplied author metadata.

## Toolbar state and outbox

Each local annotation gains:

- `clientId`: durable UUID and synchronization identity;
- `serverId`: numeric Rails ID from the latest server response;
- `syncState`: `pending`, `synced`, or `failed`;
- `serverUpdatedAt`: latest server timestamp observed.

The existing localStorage document gains an `outbox` object keyed by client UUID.
Each value is one of:

- `upsert`: the annotation's complete current desired state plus `dirtyFields`,
  identifying browser-owned fields explicitly changed while unsynchronized;
- `delete`: a tombstone containing the UUID.

Every local create, edit, and status change stores the local annotation and
replaces its outbox entry with `upsert`. Delete removes the local annotation and
replaces any queued upsert with a delete tombstone. Persisting local state and
outbox happens before network work.

Flush is serial and single-flight:

1. skip while offline or while another flush is running;
2. send each current desired-state entry;
3. on success, merge the server response and remove that exact outbox entry only
   if it was not replaced while the request was in flight;
4. on 3xx, 401, 403, or a 2xx HTML/non-JSON response, stop and surface an
   authorization/session state while retaining the outbox;
5. on 400/404/409/422 or another non-retryable 4xx, mark the annotation failed,
   retain the entry, and require a user-visible retry after correction;
6. on 408/425/429, timeout/network failure, or 5xx, retain the entry and retry
   after the next successful health check with bounded exponential backoff;
7. honor `Retry-After` for 429 when present, capped by maximum backoff;
8. on malformed JSON from an otherwise successful JSON response, retain and
   retry with bounded attempts before marking the operation failed.

No timer duplicates are allowed; retries share the existing health/visibility
lifecycle and one scheduled backoff timer.

## Pull and reconciliation

After session initialization and after connectivity returns, the toolbar pulls
the exact current page URL, then flushes queued state. A failed pull is recorded
and retried but does not block flushing an already-durable outbox; absence-based
deletion is applied only after a complete successful pull.

Merge rules:

- match records by `clientId`;
- if no local outbox entry exists, the server representation is authoritative for
  content, status, thread, metadata, and server timestamps;
- a pending local upsert remains locally visible for browser-owned editable
  fields and is flushed after the pull;
- server thread, author/user identity, and server timestamps always win;
- server status wins when `status` is not dirty; an explicit queued local status
  intent remains visible and is sent even when a pull reports another status;
- after a successful response, returned server status clears the dirty status
  intent and becomes authoritative;
- a local delete tombstone prevents the pull from resurrecting the record;
- server-only records are added locally with a stable local numeric display ID;
- after a successful complete pull, a locally synced record for that exact page
  that is absent on the server is removed; pending upserts and delete tombstones
  are never removed by absence;
- successful upsert response becomes authoritative and marks the record synced;
- local records from older toolbars without a UUID are assigned one and queued
  for upsert;
- duplicate local records with the same UUID collapse to one newest local record.

`serverUpdatedAt` is used to ignore an older pull/response that arrives after a
newer server representation. It is not a browser last-write-wins clock. The
ownership split plus `dirtyFields` is the conflict rule: explicitly dirty
browser fields, including status, win until successfully sent; server thread,
identity, and non-dirty fields win on pull.

Page identity uses `pathname + search`, not pathname alone, so query variants do
not share pins or server page scope. The server stores that exact relative page
URL; full origin remains metadata only.

## MCP contract

Canonical tools:

1. `rails_markup_read`
   - `resource`: `pending`, `sessions`, `session`, or `annotation`
   - optional configured `environment`
   - IDs only when required by the resource
   - strictly read-only; never acknowledges
2. `rails_markup_watch`
   - development watch behavior with bounded timeout/window
3. `rails_markup_transition`
   - `action`: `acknowledge` or `resolve`
   - annotation ID and optional resolution summary
4. `rails_markup_reply`
   - annotation ID and message
5. `rails_markup_dismiss`
   - separate destructive action with annotation ID and reason

Production/development URL and bearer token are read only from trusted
configuration. No tool schema or server handler accepts `baseUrl`, `url`, or
`token` overrides. URLs are parsed once, require HTTP(S), and production requires
HTTPS except explicitly local development targets.

Existing tool names remain as deprecated adapters through 1.3.0. Their
caller-supplied URL/token arguments are rejected with `isError: true`, production
reads do not acknowledge, and the adapter emits a redacted deprecation warning.
Unexpected arguments are rejected for canonical tools and adapters; handlers
validate enum values and conditionally required IDs/messages before dispatch.

Adapter mapping is explicit:

- `rails_markup_sessions` and `rails_markup_list_sessions` ->
  `rails_markup_read(resource: "sessions")`;
- `rails_markup_session` and `rails_markup_get_session` ->
  `rails_markup_read(resource: "session")`;
- `rails_markup_pending`, `rails_markup_get_pending`,
  `rails_markup_get_all_pending`, and `rails_markup_fetch_production` ->
  `rails_markup_read(resource: "pending")`;
- `rails_markup_watch_annotations` -> `rails_markup_watch`;
- `rails_markup_acknowledge` ->
  `rails_markup_transition(action: "acknowledge")`;
- `rails_markup_resolve` and `rails_markup_resolve_production` ->
  `rails_markup_transition(action: "resolve")`;
- `rails_markup_reply_production` -> `rails_markup_reply`;
- `rails_markup_dismiss_production` -> `rails_markup_dismiss`.

Legacy `environment: production` injection remains, but `baseUrl`, `token`, and
`markAcknowledged` are rejected. The adapter never performs the removed
auto-acknowledge behavior.

All tool failures return MCP tool results with `isError: true` and a concise
steering message. Per-request JSON, URI, timeout, socket, HTTP, and response-JSON
exceptions are contained so the stdio loop continues and a subsequent ping is
answered. Protocol/unknown-method failures remain JSON-RPC errors.

## Error handling and observability

- Never log bearer tokens, screenshots, annotation content, or full request
  payloads.
- Browser sync logs only operation kind, client UUID suffix, HTTP status, and
  retry state in development console warnings.
- MCP errors distinguish configuration, validation, authentication, remote HTTP,
  malformed response, and transport failures without echoing secrets.
- Host authentication owns its response and may return JSON 401/403 or an HTML
  redirect/login page. The toolbar uses the response classification above,
  retains its outbox, and shows an unavailable/auth-required state for auth
  responses. A non-JSON 5xx remains retryable. Rails CSRF failure remains the
  framework's 422 response. Validation uses JSON 422; old POST UUID conflicts
  use 409; 5xx is reserved for unexpected faults.

## Testing strategy

Tests are added before production changes and observed failing for the intended
reason.

Rails integration tests cover:

- configured base-controller auth rejection, including redirect/non-JSON
  handling in the toolbar;
- CSRF rejection and a valid same-origin request;
- blank UUID returns 422 instead of uniqueness 500;
- idempotent PUT create/update and idempotent DELETE;
- exact page pull and query-string separation;
- concurrent UUID create resolves to one record.

MCP tests cover:

- exactly five canonical advertised tools;
- aliases still dispatch with deprecation;
- hidden/caller URL and token cannot change configured destination/credential;
- reads do not acknowledge;
- tool failures set `isError: true`;
- malformed URI, timeout, connection failure, non-2xx, and invalid JSON do not
  terminate stdio and a following ping succeeds;
- secrets do not appear in output or stderr.

JavaScript behavioral tests use a DOM-capable Node harness around the toolbar to
cover:

- create/edit/status/delete enqueue the expected desired state;
- create response stores `serverId`;
- non-2xx and offline operations remain queued;
- successful reconnect pulls then flushes;
- server-only and server-updated records reconcile;
- delete tombstones prevent resurrection;
- offline status intent survives a conflicting pull and clears only after a
  successful response;
- browser metadata updates preserve server-owned author metadata;
- response classification covers 2xx, auth/3xx, terminal 4xx, retryable
  408/425/429, 5xx, invalid JSON, and network failures;
- query variants have distinct page identity;
- reload preserves outbox and resumes flush.

The final gate is the complete Ruby suite, isolated new tests, JavaScript syntax
and behavior suite, gem build/contents, anonymous/CSRF probe, MCP exfiltration
probe, malformed-request-followed-by-ping probe, and a real browser smoke using a
dummy app that actually loads Turbo and the toolbar.

## Compatibility and migration

The client UUID upgrade uses a rolling expand/backfill/contract sequence. The
1.2 migration adds the column when needed, replaces blank or noncanonical
legacy values with unique canonical UUIDs, and ensures a unique index, while
leaving the upgrade column nullable until every old writer is drained. Operators
then run the idempotent `rails_markup:client_uuids:repair` and
`rails_markup:client_uuids:verify` tasks. A later explicit contract migration
may add `NOT NULL` only after verification remains clean. Fresh installs create
the column as `NOT NULL`. Pull reads containing a lingering invalid identity
fail closed and never repair data as a side effect.

Blank compatibility POST identities receive a new server UUID. Nonblank legacy
IDs are never stored raw: a validated route session identity plus the raw legacy
ID is mapped through a fixed engine UUID namespace. This preserves exact replay,
conflict, and concurrency semantics within one session while the same reset
local ID in a later session maps to a different UUID.

Existing localStorage documents are upgraded in place by adding UUIDs and sync
fields. Every legacy local annotation that is not already represented by a
server mapping is added to the new outbox as an upsert; therefore the migrated
outbox is empty only when there is no unsynchronized legacy data. Existing MCP
callers keep functioning through deprecated adapters. The unsafe URL/token
overrides and production auto-ack are intentionally rejected because retaining
them would retain the security/correctness defects.
