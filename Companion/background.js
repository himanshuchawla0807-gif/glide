import { rankHistory, parseSuggestions, mergeSuggestions, safeURL } from './search.js';

let port;
async function profileID() {
  let { glideProfileID } = await chrome.storage.local.get('glideProfileID');
  if (!glideProfileID) { glideProfileID = crypto.randomUUID(); await chrome.storage.local.set({ glideProfileID }); }
  return glideProfileID;
}
function connect() {
  if (port) return;
  port = chrome.runtime.connectNative('com.himanshu.glide');
  const current = port;
  current.onDisconnect.addListener(() => {
    void chrome.runtime.lastError;
    if (port === current) port = undefined;
    setTimeout(connect, 1500);
  });
  current.onMessage.addListener(async message => {
    try {
      if (message.type === 'handshake') {
        current.postMessage({ type: 'hello', profileID: await profileID() });
        return;
      }
      if (typeof message.id !== 'string') return;
      if (message.type === 'suggest' && typeof message.query === 'string' && message.query.length <= 2000) {
        const query = message.query;
        const historyTask = message.history ? chrome.history.search({ text: query, startTime: 0, maxResults: 60 }) : Promise.resolve([]);
        const googleTask = message.google ? fetch(`https://www.google.com/complete/search?client=chrome&authuser=0&q=${encodeURIComponent(query)}`, {
          credentials: 'include', cache: 'no-store', signal: AbortSignal.timeout(3500)
        }).then(async response => {
          if (!response.ok) throw new Error('Google suggestions unavailable');
          // The endpoint sometimes prepends an XSSI guard.
          const text = (await response.text()).replace(/^\)\]\}'\s*/, '');
          return parseSuggestions(JSON.parse(text), query);
        }) : Promise.resolve([]);
        const [history, google] = await Promise.allSettled([historyTask, googleTask]);
        current.postMessage({ id: message.id, rows: mergeSuggestions(
          history.status === 'fulfilled' ? rankHistory(history.value, query) : [],
          google.status === 'fulfilled' ? google.value : [], query
        ), googleUnavailable: google.status === 'rejected' });
      } else if (message.type === 'open') {
        const url = safeURL(message.url);
        if (!url) throw new Error('Only HTTP and HTTPS websites can be opened.');
        const windows = (await chrome.windows.getAll({ windowTypes: ['normal'] })).filter(window => !window.incognito);
        const lastFocused = await chrome.windows.getLastFocused({ windowTypes: ['normal'] }).catch(() => undefined);
        const target = windows.find(window => window.id === lastFocused?.id) ?? windows.find(window => window.focused) ?? windows[0];
        if (target) {
          await chrome.tabs.create({ windowId: target.id, url, active: true });
          await chrome.windows.update(target.id, { focused: true });
        } else { await chrome.windows.create({ url, type: 'normal', focused: true }); }
        current.postMessage({ id: message.id, ok: true });
      }
    } catch (error) {
      if (typeof message.id === 'string') {
        try { current.postMessage({ id: message.id, error: error.message || 'Chrome request failed' }); } catch {}
      }
    }
  });
}
chrome.runtime.onInstalled.addListener(connect);
chrome.runtime.onStartup.addListener(connect);
chrome.action.onClicked.addListener(async () => { connect(); try { port.postMessage({ type: 'pair', profileID: await profileID() }); } catch {} });
chrome.alarms.create('glide-reconnect', { periodInMinutes: 0.5 });
chrome.alarms.onAlarm.addListener(connect);
connect();
