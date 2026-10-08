const { invoke } = window.__TAURI__.core,
  { listen } = window.__TAURI__.event;
const $ = (id) => document.getElementById(id),
  panel = $("panel"),
  query = $("query");
const themes = {
  Purple: ["#c6b2ff", "171,132,255", "#171322", "#a184d5"],
  Blue: ["#a3cdff", "95,166,245", "#111b2c", "#7ba9d7"],
  Black: ["#dddde3", "156,156,168", "#09090b", "#17171c"],
  Graphite: ["#c4cbd3", "135,151,173", "#1b1d23", "#6a7180"],
  Midnight: ["#b4bffe", "106,125,219", "#101328", "#394780"],
  Rose: ["#f3bfd4", "216,131,170", "#23141e", "#b77291"],
};
let state,
  rows = [],
  selected = 0,
  sequence = 0,
  timer,
  busy = false,
  lastHeight = 0,
  nativeHeight = 0,
  shrinkTimer;
function resize() {
  const height = $("settings").hidden
    ? 158 + rows.length * 55 + ($("notice").hidden ? 0 : 48)
    : 560;
  if (height !== lastHeight) {
    lastHeight = height;
    clearTimeout(shrinkTimer);
    const applyHeight = () => {
      nativeHeight = height;
      invoke("panel_height", { height }).catch(() => {});
    };
    if (height < nativeHeight) shrinkTimer = setTimeout(applyHeight, 520);
    else applyHeight();
  }
}
function notice(text = "") {
  $("notice").textContent = text;
  $("notice").hidden = !text;
  resize();
}
function apply(s) {
  state = s;
  const setting = s.settings,
    colors = themes[setting.theme] || themes.Purple;
  ["--accent", "--rgb", "--surface"].forEach((key, i) =>
    document.documentElement.style.setProperty(key, colors[i]),
  );
  $("google").checked = setting.google;
  $("history").checked = setting.history;
  $("profile").value = setting.profile;
  $("connection").textContent = s.connected
    ? "Chrome connected"
    : setting.paired
      ? "Chrome offline"
      : "Connect Chrome";
  $("connection").classList.toggle("online", s.connected);
  $("pair").disabled = !s.pairPending;
  $("pair").hidden = !!setting.paired && !s.pairPending;
  $("disconnect").hidden = !setting.paired;
  $("pairText").textContent = s.pairPending
    ? "Approve the Chrome profile whose companion you just clicked."
    : s.connected
      ? "Connected. Searches open in this profile’s normal window."
      : setting.paired
        ? "Profile paired. Open Chrome to reconnect, or search to launch it."
        : "In chrome://extensions, enable Developer mode and load the companion folder. Then click Glide Companion in that profile.";
  for (const b of $("themes").children)
    b.classList.toggle("active", b.title === setting.theme);
  if (s.error) notice(s.error);
}
for (const [name, colors] of Object.entries(themes)) {
  const b = document.createElement("button");
  b.title = name;
  b.setAttribute("aria-label", `${name} appearance`);
  b.style.setProperty("--swatch", colors[3]);
  b.onclick = () => save(name);
  $("themes").append(b);
}
async function save(theme = state.settings.theme) {
  try {
    apply(
      await invoke("preferences", {
        theme,
        google: $("google").checked,
        history: $("history").checked,
        profile: $("profile").value.trim(),
      }),
    );
    notice();
  } catch (e) {
    notice(String(e));
  }
}
function settings(show) {
  $("search").hidden = show;
  $("settings").hidden = !show;
  panel.classList.remove("has-results");
  notice();
  resize();
  if (!show) {
    render();
    query.focus();
  }
}
function render() {
  const root = $("results");
  root.replaceChildren();
  const list = document.createElement("div");
  list.className = "rows";
  rows.forEach((row, i) => {
    const b = document.createElement("button");
    b.className = "result" + (i === selected ? " selected" : "");
    b.setAttribute("role", "option");
    b.setAttribute("aria-selected", String(i === selected));
    b.style.setProperty("--i", i);
    if (root.dataset.count === "0") b.classList.add("entering");
    const symbol = document.createElement("span");
    symbol.className = "symbol";
    symbol.textContent = row.kind === "history" ? "↶" : "↗";
    const copy = document.createElement("span");
    copy.className = "copy";
    const title = document.createElement("strong");
    title.textContent = row.text;
    const detail = document.createElement("small");
    detail.textContent =
      row.detail ||
      (row.kind === "history" ? "Chrome history" : "Search in Chrome");
    copy.append(title, detail);
    b.append(symbol, copy);
    b.onclick = () => submit(row.url || row.text);
    list.append(b);
  });
  root.append(list);
  root.dataset.count = String(rows.length);
  root.style.height = `${rows.length * 55}px`;
  panel.classList.toggle("has-results", rows.length > 0);
  resize();
}
function localRows(text) {
  return text.trim()
    ? [
        {
          text: text.trim(),
          kind: "search",
          detail: "Open in your paired Chrome profile",
        },
      ]
    : [];
}
function input() {
  if (busy) return;
  const serial = ++sequence,
    text = query.value;
  selected = 0;
  rows = text.trim() ? localRows(text).concat(rows.slice(1)) : [];
  render();
  panel.classList.remove("typed");
  void $("typeLight").offsetWidth;
  panel.classList.add("typed");
  clearTimeout(timer);
  timer = setTimeout(async () => {
    if (
      !text.trim() ||
      !state?.connected ||
      (!state.settings.google && !state.settings.history)
    )
      return;
    try {
      const result = await invoke("suggest", { query: text });
      if (serial !== sequence || busy) return;
      rows = localRows(text).concat(
        (result.rows || []).filter((r) => r.text !== text.trim()).slice(0, 5),
      );
      render();
      if (result.googleUnavailable)
        notice("Google suggestions unavailable. You can still search.");
    } catch (e) {
      if (serial === sequence) notice(String(e));
    }
  }, 180);
}
async function submit(input) {
  if (busy || !input.trim()) return;
  if (!state?.settings.paired) {
    settings(true);
    notice("Connect your Chrome profile first.");
    return;
  }
  busy = true;
  ++sequence;
  clearTimeout(timer);
  query.disabled = true;
  panel.classList.add("launching");
  const start = performance.now();
  try {
    await invoke("open_query", { input });
    await new Promise((r) =>
      setTimeout(r, Math.max(0, 650 - (performance.now() - start))),
    );
    await invoke("hide");
    query.value = "";
    rows = [];
    selected = 0;
    render();
    notice();
  } catch (e) {
    panel.classList.remove("launching");
    notice(String(e));
  } finally {
    busy = false;
    query.disabled = false;
    panel.classList.remove("launching");
    query.focus();
  }
}
query.addEventListener("input", input);
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    e.preventDefault();
    invoke("hide");
  }
  if (e.ctrlKey && e.key === ",") {
    e.preventDefault();
    settings(true);
  }
  if ($("search").hidden || busy) return;
  if (e.key === "Enter") {
    e.preventDefault();
    submit(rows[selected]?.url || rows[selected]?.text || query.value);
  }
  if (rows.length && ["ArrowDown", "ArrowUp"].includes(e.key)) {
    e.preventDefault();
    selected =
      (selected + (e.key === "ArrowDown" ? 1 : -1) + rows.length) % rows.length;
    for (const [i, b] of Array.from(
      $("results").querySelectorAll(".result"),
    ).entries()) {
      b.classList.toggle("selected", i === selected);
      b.setAttribute("aria-selected", String(i === selected));
    }
  }
  if (e.key === "Tab" && rows[selected]) {
    e.preventDefault();
    query.value = rows[selected].text;
    input();
  }
});
$("settingsButton").onclick = () => settings($("settings").hidden);
$("back").onclick = () => settings(false);
$("close").onclick = () => invoke("hide");
$("google").onchange = () => save();
$("history").onchange = () => save();
$("profile").onchange = () => save();
$("folder").onclick = () =>
  invoke("companion_folder").catch((e) => notice(String(e)));
$("pair").onclick = async () => {
  try {
    apply(await invoke("approve_pair"));
    notice();
  } catch (e) {
    notice(String(e));
  }
};
$("disconnect").onclick = async () => {
  try {
    apply(await invoke("unpair"));
  } catch (e) {
    notice(String(e));
  }
};
listen("status", (e) => apply(e.payload));
listen("show", (e) => {
  clearTimeout(shrinkTimer);
  lastHeight = 0;
  nativeHeight = 0;
  panel.classList.remove("launching");
  settings(e.payload.settings || !state?.settings.paired);
  panel.classList.remove("arriving");
  void panel.offsetWidth;
  panel.classList.add("arriving");
});
$("results").dataset.count = "0";
invoke("status")
  .then((s) => {
    apply(s);
    settings(!s.settings.paired);
  })
  .catch((e) => notice(String(e)));
