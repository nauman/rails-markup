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
  let timerNow = 0;
  let uuidIndex = 0;
  let online = options.online !== false;
  let nextStorageWriteError = null;
  let nextStorageRemovalFailure = null;
  const uuids = options.uuids || [];
  const fetch = options.fetch || createFakeFetch();

  Object.defineProperty(window.navigator, "onLine", {
    configurable: true,
    get: () => online
  });
  window.crypto.randomUUID = options.randomUUID === false
    ? undefined
    : () => uuids[uuidIndex++] || `00000000-0000-4000-8000-${String(uuidIndex).padStart(12, "0")}`;
  window.fetch = fetch;
  window.setInterval = (callback, delay) => {
    const id = ++timerId;
    const interval = Math.max(1, Number(delay) || 0);
    intervals.set(id, { callback, delay: interval, at: timerNow + interval });
    return id;
  };
  window.clearInterval = (id) => intervals.delete(id);
  window.setTimeout = (callback, delay) => {
    const id = ++timerId;
    timeouts.set(id, { callback, at: timerNow + Math.max(0, Number(delay) || 0) });
    return id;
  };
  window.clearTimeout = (id) => timeouts.delete(id);

  for (const [key, value] of Object.entries(options.storage || {})) {
    window.localStorage.setItem(key, typeof value === "string" ? value : JSON.stringify(value));
  }

  const setStorageItem = window.localStorage.setItem.bind(window.localStorage);
  Object.defineProperty(window.localStorage, "setItem", {
    configurable: true,
    value(key, value) {
      if (nextStorageWriteError) {
        const error = nextStorageWriteError;
        nextStorageWriteError = null;
        throw error;
      }
      setStorageItem(key, value);
    }
  });
  const removeStorageItem = window.localStorage.removeItem.bind(window.localStorage);
  Object.defineProperty(window.localStorage, "removeItem", {
    configurable: true,
    value(key) {
      if (nextStorageRemovalFailure?.key === key) {
        const error = nextStorageRemovalFailure.error;
        nextStorageRemovalFailure = null;
        throw error;
      }
      removeStorageItem(key);
    }
  });

  window.eval(toolbarSource);

  const nextTimer = (target) => {
    const candidates = [
      ...Array.from(timeouts, ([id, timer]) => ({ id, type: "timeout", ...timer })),
      ...Array.from(intervals, ([id, timer]) => ({ id, type: "interval", ...timer }))
    ].filter(timer => timer.at <= target);
    candidates.sort((left, right) => {
      if (left.at !== right.at) return left.at - right.at;
      if (left.type !== right.type) return left.type === "timeout" ? -1 : 1;
      return left.id - right.id;
    });
    return candidates[0];
  };

  const advanceTimersBy = async (milliseconds) => {
    const target = timerNow + milliseconds;
    let timer;
    while ((timer = nextTimer(target))) {
      timerNow = timer.at;
      if (timer.type === "timeout") timeouts.delete(timer.id);
      else intervals.get(timer.id).at += timer.delay;
      await timer.callback();
    }
    timerNow = target;
  };

  return {
    window,
    toolbar: window.RailsMarkupToolbar,
    fetch,
    setOnline(value) {
      online = Boolean(value);
    },
    advanceTimersBy,
    async runNextTimer() {
      const timer = nextTimer(Infinity);
      if (timer) await advanceTimersBy(timer.at - timerNow);
    },
    pendingTimerCount() {
      return intervals.size + timeouts.size;
    },
    failNextStorageWrite(error = new Error("localStorage write failed")) {
      nextStorageWriteError = error;
    },
    failNextStorageRemoval(key, error = new Error("localStorage removal failed")) {
      nextStorageRemovalFailure = { key, error };
    },
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
