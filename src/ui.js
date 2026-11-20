// The review panel: queue notes, send them, and show what the agent did with them.
// Unsent notes live in this tab's sessionStorage. Sent notes come back from the log.
const key = location.pathname.split("/").pop();
const el = (id) => document.getElementById(id);
const page = el("page");
const note = el("note");
const store = "showme:" + key;
const SVG = "http://www.w3.org/2000/svg";
const AGENT = {
    nobody: "No agent listens",
    listening: "Agent listens",
    working: "Agent works on your notes",
};
const RECEIPT = { "Not seen yet": "clock", Seen: "check", Done: "checks" };
let sent = [];
let queue = [];
let target = null;
let shown = -1;
try { queue = JSON.parse(sessionStorage.getItem(store)) || []; } catch (e) { queue = []; }

function icon(name) {
    const svg = document.createElementNS(SVG, "svg");
    const use = document.createElementNS(SVG, "use");
    svg.setAttribute("class", "icon");
    use.setAttribute("href", "#i-" + name);
    svg.append(use);
    return svg;
}

function kindIcon(n) {
    if (n.node) return "graph";
    if (n.kind === "text") return "text";
    if (n.selector) return "pointer";
    return n.kind === "page" ? "page" : "message";
}

function label(n) {
    if (n.node) return n.node;
    if (n.kind === "text") return "“" + n.text.slice(0, 80) + "”";
    if (n.selector) return n.text ? n.text.slice(0, 60) : n.selector;
    return n.kind === "page" ? "From the page" : "Message";
}

// One row: small head line (icon, where, receipt or remove), then the words.
function row(cls, iconName, where, text, tail) {
    const li = document.createElement("li");
    const head = document.createElement("div");
    const span = document.createElement("span");
    const p = document.createElement("p");
    li.className = cls;
    head.className = "head";
    span.textContent = where;
    p.textContent = text;
    head.append(icon(iconName), span);
    if (tail) head.append(tail);
    li.append(head, p);
    return li;
}

function receipt(state) {
    const em = document.createElement("em");
    if (state === "Done") em.className = "done";
    em.append(icon(RECEIPT[state]), state);
    return em;
}

function removeButton(i) {
    const b = document.createElement("button");
    b.className = "plain";
    b.setAttribute("aria-label", "Remove this note");
    b.append(icon("x"));
    b.onclick = () => { queue.splice(i, 1); render(); };
    return b;
}

function render() {
    try { sessionStorage.setItem(store, JSON.stringify(queue)); } catch (e) {}
    const list = el("list");
    const rows = sent.map((s) => s.agent
        ? row("agent", "agent", "Agent", s.text)
        : row("", kindIcon(s.note), label(s.note), s.note.note || "", receipt(s.state)));
    queue.forEach((n, i) => rows.push(row("queued", kindIcon(n), label(n), n.note, removeButton(i))));
    // Rows that were not there at the last render slide in. The first render does not move.
    if (shown >= 0) rows.slice(shown).forEach((r) => r.classList.add("enter"));
    shown = rows.length;
    list.replaceChildren(...rows);
    list.scrollTop = list.scrollHeight;
    const chip = el("target");
    chip.hidden = !target;
    if (target) {
        chip.querySelector("use").setAttribute("href", "#i-" + kindIcon(target));
        chip.querySelector("span").textContent = label(target);
    }
    el("count").textContent = queue.length || "";
    el("send").disabled = queue.length === 0 && !note.value.trim();
}

// The log is the record: notes, then acks from the agent's command, then replies.
async function loadLog() {
    const lines = (await (await fetch("/log/" + key)).text()).split("\n");
    const out = [];
    for (const line of lines) {
        let e;
        try { e = JSON.parse(line); } catch (err) { continue; }
        if (e.t === "note") out.push({ note: e.data, state: "Not seen yet" });
        const notes = out.filter((s) => !s.agent);
        if (e.t === "ack") notes.slice(0, e.n).forEach((s) => { if (s.state === "Not seen yet") s.state = "Seen"; });
        if (e.t === "reply") {
            notes.forEach((s) => { if (s.state === "Seen") s.state = "Done"; });
            out.push({ agent: true, text: e.text });
        }
    }
    sent = out;
    render();
}

function clearTarget() {
    target = null;
    page.contentWindow.postMessage({ source: "showme-panel", type: "clear" }, "*");
}

function add() {
    const text = note.value.trim();
    if (!text) return;
    queue.push(Object.assign({ kind: "message" }, target, { note: text }));
    note.value = "";
    clearTarget();
    render();
}

async function send() {
    add();
    if (!queue.length) return;
    try {
        const r = await fetch("/send/" + key, { method: "POST", body: JSON.stringify(queue) });
        if (!r.ok) throw new Error(r.status);
        el("status").textContent = "";
        shown -= queue.length;
        queue = [];
        el("send").classList.add("sent");
        setTimeout(() => el("send").classList.remove("sent"), 900);
    } catch (e) {
        el("status").textContent = "Not sent. Run show-me open again, then press Send.";
    }
    render();
}

addEventListener("message", (e) => {
    const m = e.data;
    if (e.source !== page.contentWindow || !m || m.source !== "showme") return;
    if (m.type === "pick") {
        target = { kind: m.kind, selector: m.selector, text: m.text, node: m.node };
        note.focus();
    } else if (m.type === "note") {
        queue.push({ kind: "page", note: m.note, data: m.data });
    }
    render();
});

el("form").onsubmit = (e) => { e.preventDefault(); add(); };
el("send").onclick = send;
el("clear").onclick = () => { clearTarget(); render(); };
note.oninput = render;
note.onkeydown = (e) => {
    if (e.key !== "Enter" || e.shiftKey) return;
    e.preventDefault();
    if (e.ctrlKey || e.metaKey) send(); else add();
};
new EventSource("/events/" + key).onmessage = (e) => {
    if (e.data === "reload") page.src = "/a/" + key + "/?t=" + Date.now();
    if (e.data === "log") loadLog();
    if (!e.data.startsWith("presence ")) return;
    el("agent").dataset.state = e.data.slice(9);
    el("agent").lastElementChild.textContent = AGENT[e.data.slice(9)] || "";
};
page.src = "/a/" + key + "/";
loadLog();
