// The review panel: holds the unsent notes, sends them, and shows what the agent did.
// Unsent notes and the draft live in this tab's sessionStorage. Sent notes, replies and
// the ended state come back from the daemon's log.
import { sentRow, queuedRow } from "/ui-view.js";
import { initBar } from "/ui-bar.js";

const key = location.pathname.split("/").pop();
const el = (id) => document.getElementById(id);
const page = el("page");
const note = el("note");
const AGENT = { nobody: "No agent listens", listening: "Agent listens", working: "Agent works on your notes" };
const saved = (name, fallback) => {
    try { return JSON.parse(sessionStorage.getItem("showme:" + name + ":" + key)) ?? fallback; } catch (e) { return fallback; }
};
const save = (name, value) => {
    try { sessionStorage.setItem("showme:" + name + ":" + key, JSON.stringify(value)); } catch (e) {}
};
const tell = (msg) => page.contentWindow.postMessage(Object.assign({ source: "showme-panel" }, msg), "*");

let sent = [];
let states = [];
let queue = saved("queue", []);
let file = "";
let ended = false;
let scrollY = saved("scroll", 0);
let rowCount = -1;
let replies = -1;
let unseenReply = false;

const bar = initBar({
    mode: setMode,
    file: () => file,
    reload: reloadPage,
    end: () => send(true),
});

function setMode(on) {
    bar.setMode(on);
    save("mode", on);
    tell({ type: "mode", on });
}

function reloadPage() {
    page.classList.add("loading");
    page.src = "/a/" + key + "/?t=" + Date.now();
}

function render() {
    save("queue", queue);
    const list = el("list");
    const rows = sent.map((s, i) => sentRow(s, states[i] !== undefined && states[i] !== s.state, reveal));
    states = sent.map((s) => s.state);
    queue.forEach((n, i) => rows.push(queuedRow(n, {
        reveal,
        remove: () => { queue.splice(i, 1); render(); },
        save: (text) => { if (text) n.note = text; else queue.splice(i, 1); render(); },
    })));
    // Rows that were not there at the last render slide in. The first render does not move.
    const added = rowCount >= 0 && rows.length > rowCount;
    if (rowCount >= 0) rows.slice(rowCount).forEach((r) => r.classList.add("enter"));
    rowCount = rows.length;
    list.replaceChildren(...rows);
    if (added) list.scrollTop = list.scrollHeight;
    el("count").textContent = queue.length || "";
    const idle = queue.length === 0 && !note.value.trim();
    el("send").disabled = ended || idle;
    el("sendEnd").disabled = ended;
    note.disabled = ended;
    bar.setBadge(queue.length, unseenReply);
    bar.setEnded(ended);
}

function reveal(selector) {
    tell({ type: "reveal", selector });
}

// The log is the record: notes, acks from the agent's command, replies, end and start.
async function loadLog() {
    const lines = (await (await fetch("/log/" + key)).text()).split("\n");
    const out = [];
    let over = false;
    for (const line of lines) {
        let e;
        try { e = JSON.parse(line); } catch (err) { continue; }
        const notes = out.filter((s) => !s.agent);
        if (e.t === "open") file = e.file;
        if (e.t === "note") out.push({ note: e.data, state: "Not seen yet" });
        if (e.t === "ack") notes.slice(0, e.n).forEach((s) => { if (s.state === "Not seen yet") s.state = "Seen"; });
        if (e.t === "reply") {
            notes.forEach((s) => { if (s.state === "Seen") s.state = "Done"; });
            out.push({ agent: true, text: e.text });
        }
        if (e.t === "end") over = true;
        if (e.t === "start") over = false;
    }
    const count = out.filter((s) => s.agent).length;
    if (replies >= 0 && count > replies && document.body.classList.contains("collapsed")) unseenReply = true;
    replies = count;
    sent = out;
    ended = over;
    render();
}

// Sends the queued notes, plus the composer text as one message. `andEnd` ends the review after.
async function send(andEnd) {
    const text = note.value.trim();
    if (text) queue.push({ kind: "message", note: text });
    note.value = "";
    save("draft", "");
    try {
        if (queue.length) {
            const r = await fetch("/send/" + key, { method: "POST", body: JSON.stringify(queue) });
            if (!r.ok) throw new Error(r.status);
            rowCount -= queue.length;
            queue = [];
            el("send").classList.add("sent");
            setTimeout(() => el("send").classList.remove("sent"), 900);
        }
        if (andEnd) await fetch("/end/" + key, { method: "POST" });
        showBanner("");
    } catch (e) {
        showBanner("Not sent. Run show-me open again, then press Send.");
    }
    render();
}

function showBanner(text) {
    el("banner").textContent = text;
    el("banner").hidden = !text;
}

addEventListener("message", (e) => {
    const m = e.data;
    if (e.source !== page.contentWindow || !m || m.source !== "showme") return;
    if (m.type === "ready") {
        bar.setTitle(m.title);
        setMode(saved("mode", m.annotate));
        tell({ type: "restore", y: scrollY });
    } else if (m.type === "scroll") {
        save("scroll", scrollY = m.y);
    } else if (m.type === "toggleMode") {
        setMode(!bar.isAnnotate());
    } else if (m.type === "note") {
        const { type, source, sendNow, ...n } = m;
        queue.push(n);
        if (sendNow) return send(false);
        render();
    }
});

el("form").onsubmit = (e) => { e.preventDefault(); send(false); };
el("sendEnd").onclick = () => send(true);
el("toggle").addEventListener("click", () => { unseenReply = false; render(); });
page.onload = () => page.classList.remove("loading");
note.value = saved("draft", "");
note.oninput = () => { save("draft", note.value); render(); };
note.onkeydown = (e) => {
    if (e.key !== "Enter" || e.shiftKey || e.isComposing) return;
    e.preventDefault();
    send(false);
};

// When the daemon goes away, say so. When it comes back it may be a newer build, so reload.
const stream = new EventSource("/events/" + key);
let lost = null;
stream.onerror = () => {
    lost = lost || setTimeout(() => showBanner("show-me stopped. Run show-me open again."), 3000);
};
stream.onopen = () => {
    if (lost) location.reload();
};
stream.onmessage = (e) => {
    if (e.data === "reload") reloadPage();
    if (e.data === "log") loadLog();
    if (!e.data.startsWith("presence ")) return;
    el("agent").dataset.state = e.data.slice(9);
    el("agent").lastElementChild.textContent = AGENT[e.data.slice(9)] || "";
};
page.src = "/a/" + key + "/";
loadLog();
