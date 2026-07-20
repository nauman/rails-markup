export function createFakeFetch() {
  const calls = [];
  const results = [];

  const fetch = async (url, options = {}) => {
    calls.push({ url: String(url), options });
    if (results.length === 0) throw new Error(`Unexpected fetch: ${url}`);

    const result = results.shift();
    if (result instanceof Error) throw result;
    return result;
  };

  fetch.calls = calls;
  fetch.respondWith = (body = {}, options = {}) => {
    const status = options.status || 200;
    const headers = new Headers(options.headers || { "Content-Type": "application/json" });
    results.push(new Response(JSON.stringify(body), { status, headers }));
  };
  fetch.rejectWith = (error) => results.push(error);

  return fetch;
}
