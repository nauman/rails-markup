import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { Window } from "happy-dom";

import { createFakeFetch } from "./fake_fetch.mjs";

const toolbarPath = fileURLToPath(new URL("../../../app/assets/javascripts/rails_markup/toolbar.js", import.meta.url));
const toolbarSource = await readFile(toolbarPath, "utf8");

export function createToolbarHarness(options = {}) {
  const window = new Window({ url: options.url || "https://example.test/" });
  const intervals = new Map();
  const timeouts = new Map();
  let timerId = 0;
  let uuidIndex = 0;
  const uuids = options.uuids || [];
  const fetch = options.fetch || createFakeFetch();

  Object.defineProperty(window.navigator, "onLine", {
    configurable: true,
    get: () => options.online !== false
  });
  window.crypto.randomUUID = options.randomUUID === false
    ? undefined
    : () => uuids[uuidIndex++] || `00000000-0000-4000-8000-${String(uuidIndex).padStart(12, "0")}`;
  window.fetch = fetch;
  window.setInterval = (callback, delay) => {
    const id = ++timerId;
    intervals.set(id, { callback, delay });
    return id;
  };
  window.clearInterval = (id) => intervals.delete(id);
  window.setTimeout = (callback, delay) => {
    const id = ++timerId;
    timeouts.set(id, { callback, delay });
    return id;
  };
  window.clearTimeout = (id) => timeouts.delete(id);

  for (const [key, value] of Object.entries(options.storage || {})) {
    window.localStorage.setItem(key, typeof value === "string" ? value : JSON.stringify(value));
  }

  window.eval(toolbarSource);

  return {
    window,
    toolbar: window.RailsMarkupToolbar,
    fetch,
    storageDocument() {
      return JSON.parse(window.localStorage.getItem("rm-annotations"));
    },
    pendingIntervalCount() {
      return intervals.size;
    },
    reset() {
      window.RailsMarkupToolbar?.destroy();
      intervals.clear();
      timeouts.clear();
      delete window.RailsMarkupToolbar;
      window.close();
    }
  };
}
