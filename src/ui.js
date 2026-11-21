// The review panel: holds the unsent notes, sends them, and shows what the agent did.
// Unsent notes and the draft live in this tab's sessionStorage. Sent notes, replies and
// the ended state come back from the daemon's log.
import { sentRow, queuedRow } from "/ui-view.js";
import { initBar } from "/ui-bar.js";
import { createImages } from "/ui-images.js";
import { createChanges } from "/ui-changes.js";
import { parseLog } from "/ui-log.js";
import { createLayout } from "/ui-layout.js";
import { createAnchors } from "/ui-anchors.js";
import { connect } from "/ui-stream.js";
import { watchTabs } from "/ui-tabs.js";
import { createQueue } from "/ui-queue.js";
import { createDrafts } from "/ui-drafts.js";

const key = location.pathname.split("/").pop();
const el = (id) => document.getElementById(id);
const page = el("page");
const note = el("note");
const saved = (name, fallback) => {
    try { return JSON.parse(sessionStorage.getItem("showme:" + name + ":" + key)) ?? fallback; } catch (e) { return fallback; }
};
const save = (name, value) => {
    try { sessionStorage.setItem("showme:" + name + ":" + key, JSON.stringify(value)); } catch (e) {}
};
const tell = (msg) => page.contentWindow.postMessage(Object.assign({ source: "showme-panel" }, msg), "*");

let sent = [];
let states = [];
const queue = createQueue(key);
let file = "";
let ended = false;
let scrollY = saved("scroll", 0);
let rowCount = -1;
let replies = -1;
let unseenReply = false;
const images = createImages(key, () => render());
const changes = createChanges(key, tell);
const anchors = createAnchors(tell, () => queue.items);
const drafts = createDrafts(key, tell);
const layout = createLayout(key, tell, (issues) => {
    queue.add({ kind: "layout", note: "Fix these layout issues.", issues });
    render();
});

const bar = initBar({
    mode: setMode,
    file: () => file,
    reload: reloadPage,
    download: () => { location.href = "/export/" + key; },
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
    const list = el("list");
    const rows = sent.map((s, i) => sentRow(s, states[i] !== undefined && states[i] !== s.state, reveal, images.url));
    states = sent.map((s) => s.state);
    queue.items.forEach((n, i) => rows.push(queuedRow(n, {
        reveal,
        url: images.url,
        remove: () => { queue.remove(i); render(); },
        save: (text) => { queue.edit(i, text); render(); },
    })));
    // Rows that were not there at the last render slide in. The first render does not move.
    const added = rowCount >= 0 && rows.length > rowCount;
    if (rowCount >= 0) rows.slice(rowCount).forEach((r) => r.classList.add("enter"));
    rowCount = rows.length;
    list.replaceChildren(...rows);
    if (added) list.scrollTop = list.scrollHeight;
    el("count").textContent = queue.items.length || "";
    const idle = queue.items.length === 0 && !note.value.trim() && !images.count();
    el("send").disabled = ended || idle || !images.ready();
    note.disabled = ended;
    bar.setBadge(queue.items.length, unseenReply);
    bar.setEnded(ended);
    anchors.sync();
}

function reveal(selector) {
    tell({ type: "reveal", selector });
}

async function loadLog() {
    const log = parseLog(await (await fetch("/log/" + key)).text());
    if (replies >= 0 && log.replies > replies && document.body.classList.contains("collapsed")) unseenReply = true;
    replies = log.replies;
    sent = log.rows;
    file = log.file;
    ended = log.ended;
    render();
}

// Sends the queued notes, plus the composer text as one message. `andEnd` ends the review after.
async function send(andEnd) {
    // Enter, End review and Ctrl+Enter in the card all come here, not only the Send button.
    if (!images.ready()) return showBanner("Wait for the images to upload, or remove the one that failed.");
    const text = note.value.trim();
    const pics = images.take();
    if (text || pics.length) queue.add(Object.assign({ kind: "message", note: text }, pics.length ? { images: pics } : {}));
    note.value = "";
    save("draft", "");
    try {
        if (queue.items.length) {
            const r = await fetch("/send/" + key, { method: "POST", body: JSON.stringify(queue.items) });
            if (!r.ok) throw new Error(r.status);
            rowCount -= queue.items.length;
            changes.reset();
            if (queue.items.some((n) => n.kind === "page")) drafts.answered();
            queue.clear();
            el("send").classList.add("sent");
            setTimeout(() => el("send").classList.remove("sent"), 900);
        }
        if (andEnd) await fetch("/end/" + key, { method: "POST" });
        showBanner("");
    } catch (e) {
        showBanner("Couldn't send. Run show-me open again, then retry.");
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
    changes.onMessage(m);
    layout.onMessage(m);
    drafts.onMessage(m);
    if (m.type === "ready") {
        bar.setTitle(m.title);
        setMode(saved("mode", m.annotate));
        tell({ type: "restore", y: scrollY });
        anchors.sync();
    } else if (m.type === "meta") {
        bar.setMeta(m);
    } else if (m.type === "scroll") {
        save("scroll", scrollY = m.y);
    } else if (m.type === "edit") {
        anchors.edit(m.id);
    } else if (m.type === "toggleMode") {
        setMode(!bar.isAnnotate());
    } else if (m.type === "image") {
        images.upload(m.blob).then((r) => tell(r.id ? { type: "imageDone", id: r.id, url: images.url(r.id) } : { type: "imageFailed", error: r.error }));
    } else if (m.type === "note") {
        // sendNow and end are orders for this panel, not part of the note.
        const { type, source, sendNow, end, ...n } = m;
        queue.add(n);
        if (sendNow || end) return send(!!end);
        render();
    }
});

el("form").onsubmit = (e) => { e.preventDefault(); send(false); };
el("toggle").addEventListener("click", () => { unseenReply = false; render(); });
page.onload = () => page.classList.remove("loading");
note.value = saved("draft", "");
note.oninput = () => {
    save("draft", note.value);
    note.style.height = "auto";
    note.style.height = Math.min(note.scrollHeight, 140) + "px";
    render();
};
note.onkeydown = (e) => {
    if (e.key !== "Enter" || e.shiftKey || e.isComposing) return;
    e.preventDefault();
    send(false);
};

connect(key, { reload: reloadPage, log: loadLog, banner: showBanner });
watchTabs(key);
page.src = "/a/" + key + "/";
loadLog();
