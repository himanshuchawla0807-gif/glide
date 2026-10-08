import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parseSuggestions, rankHistory, mergeSuggestions, safeURL } from '../Companion/search.js';

assert.equal(safeURL('javascript:alert(1)'), undefined);
assert.equal(safeURL('file:///etc/passwd'), undefined);
assert.equal(safeURL('https://example.com/a?b=c'), 'https://example.com/a?b=c');
const history = [
  { title: 'Swift search - Google Search', url: 'https://www.google.com/search?q=swift+native+app', visitCount: 2 },
  { title: 'Swift documentation', url: 'https://www.swift.org/documentation/', visitCount: 10 },
  { title: 'Swift unsafe', url: 'javascript:alert(1)', visitCount: 100 },
];
const ranked = rankHistory(history, 'swift');
assert.equal(ranked[0].text, 'swift native app');
assert.equal(ranked[0].kind, 'Your searches');
assert.equal(ranked[1].url, 'https://www.swift.org/documentation/');
assert.equal(ranked.length, 2);
assert.equal(mergeSuggestions(ranked, parseSuggestions(['swift', ['swift', 'swift native app', 'swift programming']], 'swift'), 'swift').length, 3);
assert.deepEqual(parseSuggestions({}, 'test'), []);

let handler, actionHandler;
let messages = [], created = [], focused = [];
let available = [{ id: 23, incognito: false, focused: false }, { id: 42, incognito: true, focused: true }];
globalThis.chrome = {
  runtime: { connectNative: () => ({ postMessage: message => messages.push(message), onMessage: { addListener: fn => { handler = fn; } }, onDisconnect: { addListener() {} } }), onInstalled: { addListener() {} }, onStartup: { addListener() {} } },
  storage: { local: { get: async () => ({glideProfileID: '00000000-0000-4000-8000-000000000001'}), set: async () => {} } },
  action: { onClicked: { addListener(fn) { actionHandler = fn; } } },
  alarms: { create() {}, onAlarm: { addListener() {} } },
  windows: {
    getAll: async () => available,
    getLastFocused: async () => ({ id: 42 }),
    update: async (...args) => focused.push(args),
    create: async config => created.push(['window', config]),
  },
  tabs: { create: async config => created.push(['tab', config]) },
  history: { search: async () => history },
};
let cookieMode;
globalThis.fetch = async (_url, options) => { cookieMode = options.credentials; return { ok: true, text: async () => JSON.stringify(['swift', ['swift programming']]) }; };
await import('../Companion/background.js');
await handler({ type: 'handshake' });
assert.equal(messages.at(-1).profileID, '00000000-0000-4000-8000-000000000001');
assert.equal(messages.at(-1).email, undefined);
await actionHandler();
assert.equal(messages.at(-1).type, "pair");
assert.equal(messages.at(-1).profileID, "00000000-0000-4000-8000-000000000001");
await handler({ id: '1', type: 'suggest', query: 'swift', google: true, history: true });
assert.equal(cookieMode, 'include');
assert.equal(messages.at(-1).rows[0].kind, 'Your searches');
await handler({ id: '2', type: 'open', url: 'https://example.com' });
assert.equal(created.at(-1)[0], 'tab');
assert.equal(created.at(-1)[1].windowId, 23, 'Reuse a normal window in the extension’s profile, excluding incognito');
assert.equal(focused.at(-1)[0], 23);
available = [];
await handler({ id: '3', type: 'open', url: 'https://example.com' });
assert.equal(created.at(-1)[0], 'window', 'Create a window only if this profile has none');
const count = created.length;
await handler({ id: '4', type: 'open', url: 'javascript:alert(1)' });
assert.equal(created.length, count);
assert.ok(messages.at(-1).error);
globalThis.fetch = async () => { throw Error('Offline'); };
await handler({ id: '5', type: 'suggest', query: 'swift', google: true, history: true });
assert.equal(messages.at(-1).googleUnavailable, true);
assert.ok(messages.at(-1).rows.some(row => row.kind === 'History'));
console.log('Passed: local anonymous pairing, signed-in suggestion requests, personal-history ranking, deduplication, window reuse, incognito exclusion, cold-window fallback, unsafe-URL rejection, offline history');
