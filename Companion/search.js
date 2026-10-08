export function safeURL(value) {
  if (typeof value !== 'string') return undefined;
  try { const url = new URL(value); return ['https:', 'http:'].includes(url.protocol) ? url.href : undefined; } catch { return undefined; }
}
export function parseSuggestions(data, query) {
  if (!Array.isArray(data) || !Array.isArray(data[1])) return [];
  return data[1].filter(text => typeof text === 'string' && text.length <= 2000 && text.toLowerCase() !== query.toLowerCase())
    .slice(0, 6).map(text => ({ text, kind: 'Google' }));
}
export function rankHistory(history, query) {
  const lower = query.toLowerCase();
  return history.map(entry => {
    const url = safeURL(entry.url);
    if (!url) return undefined;
    const parsed = new URL(url);
    const isGoogle = /(^|\.)google\.[a-z.]+$/.test(parsed.hostname) && parsed.pathname === '/search';
    const search = isGoogle ? parsed.searchParams.get('q') : undefined;
    const text = search || entry.title || parsed.hostname;
    if (!text || !`${text} ${url}`.toLowerCase().includes(lower)) return undefined;
    // Prefer a prior query starting with the input, then frequently visited pages.
    const score = (text.toLowerCase().startsWith(lower) ? 100 : 0) + (search ? 40 : 0) + Math.min(20, entry.visitCount || 0);
    return { text, kind: search ? 'Your searches' : 'History', url: search ? undefined : url, detail: search ? undefined : parsed.hostname, score, lastVisitTime: entry.lastVisitTime || 0 };
  }).filter(Boolean).sort((a, b) => b.score - a.score || b.lastVisitTime - a.lastVisitTime).slice(0, 4);
}
export function mergeSuggestions(history, google, query) {
  const seen = new Set([query.toLowerCase()]);
  return [...history, ...google].filter(row => {
    const key = row.text.toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key); return true;
  }).slice(0, 6).map(({ text, kind, url, detail }) => ({ text, kind, url, detail }));
}
