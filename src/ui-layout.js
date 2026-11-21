// Layout problems the page found in itself (layout.js). The top bar shows the count.
// Click it for the list: one click on one issue shows it on the page. Each issue has
// one checkbox for "Fix selected" and one Dismiss button. One issue that was sent for
// fixing and is found again says "Still there".
// "Still there" needs two facts: the issue went out in one sent note, and one page load
// after that send found it again. Clicking "Fix selected" only queues the note.
// Nothing here reaches the agent until the reviewer asks. Dismissed and sent issues
// live in this tab's sessionStorage, keyed by problem, selector and text: one selector
// alone can point at another element after the agent's edit.
const el = (id) => document.getElementById(id);
const keyOf = (issue) => issue.problem + " " + issue.selector + " " + issue.text;

// The one issue list of this panel. createLayout fills it in.
const list = {
    key: "",
    tell: () => {},
    onFix: () => {},
    issues: [],
    dismissed: new Set(),
    skipped: new Set(), // unchecked in this menu
    sentAt: {}, // issue key -> time of the send that carried it
    loadedAt: 0, // time of the page load that this list comes from
};

const store = (name) => "showme:layout-" + name + ":" + list.key;
const still = (k) => list.sentAt[k] !== undefined && list.loadedAt > list.sentAt[k];
const shown = () => list.issues.filter((i) => !list.dismissed.has(keyOf(i)));

function read(name, fallback) {
    try { return JSON.parse(sessionStorage.getItem(store(name))) || fallback; } catch (e) { return fallback; }
}

function write(name, value) {
    try { sessionStorage.setItem(store(name), JSON.stringify(value)); } catch (e) {}
}

function open(show) {
    el("layoutMenu").hidden = !show;
    el("layout").setAttribute("aria-expanded", String(show));
}

function row(issue) {
    const k = keyOf(issue);
    const line = Object.assign(document.createElement("div"), { className: "issue" });
    const box = Object.assign(document.createElement("input"), { type: "checkbox", checked: !list.skipped.has(k), title: "Fix this one" });
    const show = Object.assign(document.createElement("button"), { type: "button", textContent: issue.text || issue.selector });
    const small = Object.assign(document.createElement("small"), { textContent: issue.problem + (still(k) ? " · Still there" : "") });
    const drop = Object.assign(document.createElement("button"), { type: "button", className: "dismiss", textContent: "Dismiss" });
    box.onchange = () => { if (box.checked) list.skipped.delete(k); else list.skipped.add(k); draw(); };
    show.onclick = () => list.tell({ type: "reveal", selector: issue.selector });
    drop.onclick = () => { list.dismissed.add(k); write("dismissed", [...list.dismissed]); update(); };
    show.append(small);
    line.append(box, show, drop);
    return line;
}

function draw() {
    const picked = shown().filter((i) => !list.skipped.has(keyOf(i)));
    const fix = Object.assign(document.createElement("button"), { type: "button", className: "primary", textContent: "Fix selected" });
    fix.disabled = picked.length === 0;
    fix.onclick = () => {
        open(false);
        list.onFix(picked.map(({ selector, problem, text }) => ({ selector, problem, text })));
    };
    el("layoutMenu").replaceChildren(...shown().map(row), fix);
}

function update() {
    const n = shown().length;
    el("layout").hidden = n === 0;
    el("layout").textContent = n === 1 ? "1 layout issue" : n + " layout issues";
    if (n === 0) open(false);
    draw();
}

export function createLayout(key, tell, onFix) {
    Object.assign(list, { key, tell, onFix });
    list.dismissed = new Set(read("dismissed", []));
    list.sentAt = read("sent", {});
    el("layout").onclick = () => open(el("layoutMenu").hidden);
    addEventListener("mousedown", (e) => {
        if (!el("layoutMenu").hidden && !e.target.closest("#layoutBox")) open(false);
    });
    addEventListener("keydown", (e) => {
        if (e.key === "Escape") open(false);
    });
    return {
        // Call after one send went out with these issues in it.
        sent(issues) {
            issues.forEach((i) => { list.sentAt[keyOf(i)] = Date.now(); });
            write("sent", list.sentAt);
        },
        onMessage(m) {
            if (m.type === "ready") list.loadedAt = Date.now();
            if (m.type !== "layout") return;
            list.issues = m.issues;
            update();
        },
    };
}
