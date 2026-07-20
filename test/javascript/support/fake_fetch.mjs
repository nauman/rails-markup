export function createFakeFetch() {
  const calls = [];
  const results = [];

  const response = (body = {}, options = {}) => {
    const status = options.status ?? 200;
    const headers = new Headers(options.headers || { "Content-Type": "application/json" });
    const responseBody = status === 204 || status === 205
      ? null
      : (options.rawBody ? String(body) : JSON.stringify(body));
    return new Response(responseBody, { status, headers });
  };

  const fetch = async (url, options = {}) => {
    calls.push({ url: String(url), options });
    if (results.length === 0) throw new Error(`Unexpected fetch: ${url}`);

    const result = results.shift();
    if (result instanceof Error) throw result;
    return await result;
  };

  fetch.calls = calls;
  fetch.lastCall = () => calls.at(-1);
  fetch.respondWith = (body = {}, options = {}) => results.push(response(body, options));
  fetch.rejectWith = (error) => results.push(error);
  fetch.defer = () => {
    let resolve;
    let reject;
    const promise = new Promise((resolvePromise, rejectPromise) => {
      resolve = resolvePromise;
      reject = rejectPromise;
    });
    results.push(promise);

    return {
      resolve,
      reject,
      respondWith(body = {}, options = {}) {
        resolve(response(body, options));
      }
    };
  };

  return fetch;
}
