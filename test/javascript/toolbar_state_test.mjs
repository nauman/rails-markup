import assert from "node:assert/strict";
import test from "node:test";

import { createFakeFetch } from "./support/fake_fetch.mjs";
import { createToolbarHarness } from "./support/toolbar_harness.mjs";

const uuidA = "11111111-1111-4111-8111-111111111111";
const uuidB = "22222222-2222-4222-8222-222222222222";

test("client identities remain UUIDs without crypto.randomUUID", (t) => {
  const harness = createToolbarHarness({ randomUUID: false });
  t.after(() => harness.reset());

  assert.match(harness.toolbar._newClientId(), /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
});

test("page identity and server page_url include pathname and search", async (t) => {
  const fetch = createFakeFetch();
  fetch.respondWith({});
  const harness = createToolbarHarness({ url: "https://example.test/products?status=open", fetch });
  t.after(() => harness.reset());

  assert.equal(harness.toolbar._pageStorageKey(), "rm-annotations:/products?status=open");
  harness.toolbar.serverOnline = true;
  await harness.toolbar._pushToServer({
    id: 1,
    clientId: uuidA,
    comment: "Fix this",
    intent: "fix",
    severity: "important",
    pathname: "/products?status=open",
    url: "https://example.test/products?status=open"
  });

  assert.equal(JSON.parse(fetch.calls[0].options.body).page_url, "/products?status=open");

  const other = createToolbarHarness({ url: "https://example.test/products?status=closed" });
  t.after(() => other.reset());
  assert.notEqual(harness.toolbar._pageStorageKey(), other.toolbar._pageStorageKey());
});

test("legacy records gain sync fields and only unmapped records enter the outbox", (t) => {
  const harness = createToolbarHarness({
    uuids: [uuidA, uuidB],
    storage: {
      "rm-annotations": {
        annotations: [
          { id: 1, comment: "Local only", pathname: "/products", status: "pending" },
          { id: 2, serverId: 42, comment: "Already mapped", pathname: "/products", status: "resolved" }
        ],
        nextId: 3
      }
    }
  });
  t.after(() => harness.reset());

  harness.toolbar._loadFromStorage();

  const [unmapped, mapped] = harness.toolbar.annotations;
  assert.equal(unmapped.clientId, uuidA);
  assert.equal(unmapped.serverId, null);
  assert.equal(unmapped.syncState, "pending");
  assert.equal(unmapped.serverUpdatedAt, null);
  assert.ok(Array.isArray(unmapped.dirtyFields));
  assert.equal(mapped.clientId, uuidB);
  assert.equal(mapped.serverId, 42);
  assert.equal(mapped.syncState, "synced");
  assert.deepEqual(Object.keys(harness.toolbar.outbox), [uuidA]);
  assert.equal(harness.toolbar.outbox[uuidA].type, "upsert");
  assert.equal(harness.toolbar.outbox[uuidA].annotation.clientId, uuidA);
  assert.equal(harness.toolbar.outbox[uuidA].annotation.syncState, "pending");
});

test("an existing mapping or outbox is not requeued or overwritten", (t) => {
  const existingEntry = { type: "upsert", annotation: { clientId: uuidA, comment: "Newest intent" }, dirtyFields: ["content"] };
  const harness = createToolbarHarness({
    storage: {
      "rm-annotations": {
        annotations: [
          { id: 1, clientId: uuidA, comment: "Older local", pathname: "/", syncState: "pending" },
          { id: 2, clientId: uuidB, serverId: 9, comment: "Mapped", pathname: "/" }
        ],
        nextId: 3,
        outbox: { [uuidA]: existingEntry }
      }
    }
  });
  t.after(() => harness.reset());

  harness.toolbar._loadFromStorage();

  assert.deepEqual(JSON.parse(JSON.stringify(harness.toolbar.outbox)), { [uuidA]: existingEntry });
});

test("invalid legacy client IDs are replaced and their outbox entries rekeyed", (t) => {
  const invalidClientId = "rm-legacy-client";
  const harness = createToolbarHarness({
    uuids: [uuidA],
    storage: {
      "rm-annotations": {
        annotations: [{ id: 1, clientId: invalidClientId, comment: "Legacy", pathname: "/" }],
        nextId: 2,
        outbox: {
          [invalidClientId]: {
            type: "upsert",
            annotation: { clientId: invalidClientId, comment: "Legacy" },
            dirtyFields: ["content"]
          }
        }
      }
    }
  });
  t.after(() => harness.reset());

  harness.toolbar._loadFromStorage();

  assert.equal(harness.toolbar.annotations[0].clientId, uuidA);
  assert.equal(harness.toolbar.outbox[invalidClientId], undefined);
  assert.equal(harness.toolbar.outbox[uuidA].annotation.clientId, uuidA);
});

test("legacy per-page migration preserves records with colliding local IDs", (t) => {
  const harness = createToolbarHarness({
    uuids: [uuidA, uuidB, "33333333-3333-4333-8333-333333333333"],
    storage: {
      "rm-annotations": { annotations: [{ id: 1, comment: "Global", pathname: "/one" }], nextId: 1 },
      "rm-annotations:/one": { annotations: [{ id: 1, comment: "Page one", pathname: "/one" }], nextId: 2 },
      "rm-annotations:/two": { annotations: [{ id: 1, comment: "Page two", pathname: "/two" }], nextId: 2 }
    }
  });
  t.after(() => harness.reset());

  harness.toolbar._loadFromStorage();

  assert.deepEqual(Array.from(harness.toolbar.annotations, (annotation) => annotation.comment).sort(), ["Global", "Page one", "Page two"]);
  assert.equal(new Set(harness.toolbar.annotations.map((annotation) => annotation.id)).size, 3);
  assert.equal(Object.keys(harness.toolbar.outbox).length, 3);
  assert.equal(harness.window.localStorage.getItem("rm-annotations:/one"), null);
  assert.equal(harness.window.localStorage.getItem("rm-annotations:/two"), null);
});

test("legacy migration preserves malformed and unrecognized prefixed keys", (t) => {
  const harness = createToolbarHarness({
    uuids: [uuidA],
    storage: {
      "rm-annotations:recognized": { annotations: [{ id: 1, comment: "Migrated", pathname: "/recognized" }] },
      "rm-annotations:malformed": "{not-json",
      "rm-annotations:unrecognized": { annotations: "not-an-array" }
    }
  });
  t.after(() => harness.reset());

  harness.toolbar._loadFromStorage();

  assert.equal(harness.window.localStorage.getItem("rm-annotations:recognized"), null);
  assert.equal(harness.window.localStorage.getItem("rm-annotations:malformed"), "{not-json");
  assert.notEqual(harness.window.localStorage.getItem("rm-annotations:unrecognized"), null);
});

test("legacy migration retains source keys when consolidated persistence fails", (t) => {
  const harness = createToolbarHarness({
    uuids: [uuidA],
    storage: {
      "rm-annotations": { annotations: [], nextId: 1, outbox: {} },
      "rm-annotations:/legacy": { annotations: [{ id: 1, comment: "Keep me", pathname: "/legacy" }] }
    }
  });
  t.after(() => harness.reset());
  harness.failNextStorageWrite(new Error("quota exceeded"));

  harness.toolbar._loadFromStorage();

  assert.notEqual(harness.window.localStorage.getItem("rm-annotations:/legacy"), null);
  assert.equal(harness.storageDocument().annotations.length, 0);
});

test("duplicate client IDs collapse to the deterministically newest local record", (t) => {
  const harness = createToolbarHarness({
    storage: {
      "rm-annotations": {
        annotations: [
          { id: 7, clientId: uuidA, comment: "old", updatedAt: "2026-01-01T00:00:00Z" },
          { id: 8, clientId: uuidA, comment: "new-first", updatedAt: "2026-02-01T00:00:00Z", serverUpdatedAt: "2026-02-02T00:00:00Z" },
          { id: 9, clientId: uuidA, comment: "new-stable-winner", updatedAt: "2026-02-01T00:00:00Z", serverUpdatedAt: "2026-02-02T00:00:00Z" },
          { id: 9, clientId: uuidB, comment: "unrelated" }
        ],
        nextId: 2,
        outbox: {}
      }
    }
  });
  t.after(() => harness.reset());

  harness.toolbar._loadFromStorage();

  assert.equal(harness.toolbar.annotations.length, 2);
  assert.equal(harness.toolbar.annotations.find((annotation) => annotation.clientId === uuidA).comment, "new-stable-winner");
  assert.equal(harness.toolbar.annotations.find((annotation) => annotation.clientId === uuidB).comment, "unrelated");
  assert.equal(new Set(harness.toolbar.annotations.map((annotation) => annotation.id)).size, 2);
});

test("server-only records receive stable collision-free display IDs across reload", (t) => {
  const first = createToolbarHarness({
    storage: {
      "rm-annotations": {
        annotations: [
          { id: 5, clientId: uuidA, serverId: 10, comment: "Existing" },
          { clientId: uuidB, serverId: 11, comment: "Imported" }
        ],
        nextId: 2,
        outbox: {}
      }
    }
  });
  t.after(() => first.reset());
  first.toolbar._loadFromStorage();

  const firstIds = Array.from(first.toolbar.annotations, (annotation) => annotation.id);
  const persisted = first.storageDocument();
  assert.deepEqual(firstIds, [5, 6]);
  assert.equal(first.toolbar.nextId, 7);

  const reloaded = createToolbarHarness({ storage: { "rm-annotations": persisted } });
  t.after(() => reloaded.reset());
  reloaded.toolbar._loadFromStorage();
  assert.deepEqual(Array.from(reloaded.toolbar.annotations, (annotation) => annotation.id), firstIds);
  assert.equal(reloaded.toolbar.nextId, 7);
});

test("new UI annotations have the complete sync schema before storage", (t) => {
  const harness = createToolbarHarness({ uuids: [uuidA] });
  t.after(() => harness.reset());
  harness.toolbar._injectStyles();
  harness.toolbar._injectDOM();
  harness.window.document.getElementById("rm-popup-input").value = "Created locally";
  harness.toolbar._currentElement = { selector: "main" };

  harness.toolbar.submitAnnotation();

  const annotation = harness.toolbar.annotations[0];
  assert.equal(annotation.clientId, uuidA);
  assert.equal(annotation.serverId, null);
  assert.equal(annotation.syncState, "pending");
  assert.equal(annotation.serverUpdatedAt, null);
  assert.deepEqual(Array.from(annotation.dirtyFields), []);
  assert.equal(harness.storageDocument().annotations[0].syncState, "pending");
});

test("harness reset destroys toolbar intervals and global state", (t) => {
  const fetch = createFakeFetch();
  fetch.rejectWith(new Error("offline"));
  const harness = createToolbarHarness({ fetch });
  t.after(() => harness.reset());

  harness.toolbar.init();
  assert.equal(harness.pendingIntervalCount(), 1);
  harness.reset();
  assert.equal(harness.pendingIntervalCount(), 0);
  assert.equal(harness.window.RailsMarkupToolbar, undefined);
});
