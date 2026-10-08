const { test } = require("node:test");
const assert = require("node:assert/strict");
const { JSDOM } = require("jsdom");
const fs = require("node:fs");
const path = require("node:path");
const html = fs.readFileSync(path.join(__dirname, "../ui/index.html"), "utf8");
const script = fs.readFileSync(path.join(__dirname, "../ui/app.js"), "utf8");
const delay = (ms) => new Promise((r) => setTimeout(r, ms));
function setup({ paired = true, suggest } = {}) {
  const dom = new JSDOM(html, {
    runScripts: "outside-only",
    pretendToBeVisual: true,
  });
  const window = dom.window,
    calls = [],
    events = {};
  let state = {
    settings: {
      theme: "Purple",
      google: true,
      history: true,
      profile: "Default",
      paired: paired ? "paired-id" : null,
    },
    connected: paired,
    pairPending: false,
    error: null,
  };
  window.__TAURI__ = {
    core: {
      invoke: async (command, args) => {
        calls.push({ command, args });
        if (command === "status") return structuredClone(state);
        if (command === "preferences") {
          state.settings = { ...state.settings, ...args };
          return structuredClone(state);
        }
        if (command === "suggest")
          return suggest ? suggest(args.query) : { rows: [] };
        if (command === "unpair") {
          state.settings.paired = null;
          state.connected = false;
          return structuredClone(state);
        }
        return null;
      },
    },
    event: {
      listen: (name, cb) => {
        events[name] = cb;
        return Promise.resolve(() => {});
      },
    },
  };
  window.eval(script);
  const input = (text) => {
    window.document.getElementById("query").value = text;
    window.document
      .getElementById("query")
      .dispatchEvent(new window.Event("input"));
  };
  return {
    dom,
    window,
    calls,
    events,
    input,
    $: (id) => window.document.getElementById(id),
  };
}
test("first run requires pairing and has six palette choices", async () => {
  const app = setup({ paired: false });
  try {
    await delay(0);
    assert.equal(app.$("settings").hidden, false);
    assert.equal(app.$("themes").children.length, 6);
    assert.equal(app.$("pair").disabled, true);
    assert.equal(app.$("disconnect").hidden, true);
    app.$("back").click();
    app.input("hello");
    app.window.document.dispatchEvent(
      new app.window.KeyboardEvent("keydown", { key: "Enter" }),
    );
    await delay(0);
    assert.equal(app.$("settings").hidden, false);
    assert(!app.calls.some((c) => c.command === "open_query"));
  } finally {
    app.dom.window.close();
  }
});
test("typing preserves the header and does not replay row entrance on each letter", async () => {
  const app = setup();
  try {
    await delay(0);
    assert.equal(app.$("results").querySelectorAll("button").length, 0);
    const header = app.window.document.querySelector("header");
    app.input("h");
    assert.equal(app.$("results").querySelectorAll(".entering").length, 1);
    app.input("he");
    assert.equal(app.$("results").querySelectorAll(".entering").length, 0);
    assert.equal(app.window.document.querySelector("header"), header);
    assert.equal(app.$("query").value, "he");
    assert.equal(
      app.calls.filter(
        (c) => c.command === "panel_height" && c.args.height === 213,
      ).length,
      1,
    );
    app.input("");
    assert.equal(app.$("results").querySelectorAll("button").length, 0);
  } finally {
    app.dom.window.close();
  }
});
test("stale suggestions cannot overwrite newer input; untrusted text is never HTML", async () => {
  const pending = {};
  const app = setup({
    suggest: (q) =>
      new Promise((resolve) => {
        pending[q] = resolve;
      }),
  });
  try {
    await delay(0);
    app.input("old");
    await delay(210);
    app.input("new");
    await delay(210);
    pending.new({
      rows: [
        {
          text: "<img src=x onerror=alert(1)>",
          kind: "history",
          url: "https://example.com/",
        },
      ],
    });
    await delay(0);
    assert.equal(app.$("results").querySelector("img"), null);
    assert(app.$("results").textContent.includes("<img"));
    pending.old({ rows: [{ text: "STALE", kind: "search" }] });
    await delay(0);
    assert(!app.$("results").textContent.includes("STALE"));
  } finally {
    app.dom.window.close();
  }
});
test("keyboard selects a history URL and duplicate Enter opens once", async () => {
  const app = setup({
    suggest: async () => ({
      rows: [{ text: "A site", kind: "history", url: "https://example.com/" }],
    }),
  });
  try {
    await delay(0);
    app.input("site");
    await delay(210);
    app.window.document.dispatchEvent(
      new app.window.KeyboardEvent("keydown", { key: "ArrowDown" }),
    );
    app.window.document.dispatchEvent(
      new app.window.KeyboardEvent("keydown", { key: "Enter" }),
    );
    app.window.document.dispatchEvent(
      new app.window.KeyboardEvent("keydown", { key: "Enter" }),
    );
    await delay(0);
    const calls = app.calls.filter((c) => c.command === "open_query");
    assert.equal(calls.length, 1);
    assert.equal(calls[0].args.input, "https://example.com/");
    await delay(700);
    assert(app.calls.some((c) => c.command === "hide"));
    assert.equal(app.$("query").value, "");
  } finally {
    app.dom.window.close();
  }
});
