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

export function createLayout(key, tell, onFix) {
    const chip = el("layout");
    const menu = el("layoutMenu");
    const store = (name) => "showme:layout-" + name + ":" + key;
    const load = (name) => { try { return new Set(JSON.parse(sessionStorage.getItem(store(name))) || []); } catch (e) { return new Set(); } };
    const keep = (name, set) => { try { sessionStorage.setItem(store(name), JSON.stringify([...set])); } catch (e) {} };
    const dismissed = load("dismissed");
    let sentAt = {}; // issue key -> time of the send that carried it
    try { sentAt = JSON.parse(sessionStorage.getItem(store("sent"))) || {}; } catch (e) {}
    let loadedAt = 0; // time of the page load that this list comes from
    const still = (k) => sentAt[k] !== undefined && loadedAt > sentAt[k];
    const skipped = new Set(); // unchecked in this menu
    let issues = [];

    function open(show) {
        menu.hidden = !show;
        chip.setAttribute("aria-expanded", String(show));
    }

    function shown() {
        return issues.filter((i) => !dismissed.has(keyOf(i)));
    }

    function row(issue) {
        const k = keyOf(issue);
        const line = document.createElement("div");
        const box = Object.assign(document.createElement("input"), { type: "checkbox", checked: !skipped.has(k), title: "Fix this one" });
        const show = Object.assign(document.createElement("button"), { type: "button", textContent: issue.text || issue.selector });
        const small = Object.assign(document.createElement("small"), { textContent: issue.problem + (still(k) ? " · Still there" : "") });
        const drop = Object.assign(document.createElement("button"), { type: "button", className: "dismiss", textContent: "Dismiss" });
        line.className = "issue";
        box.onchange = () => { if (box.checked) skipped.delete(k); else skipped.add(k); draw(); };
        show.onclick = () => tell({ type: "reveal", selector: issue.selector });
        drop.onclick = () => { dismissed.add(k); keep("dismissed", dismissed); update(); };
        show.append(small);
        line.append(box, show, drop);
        return line;
    }

    function draw() {
        const picked = shown().filter((i) => !skipped.has(keyOf(i)));
        const fix = Object.assign(document.createElement("button"), { type: "button", className: "primary", textContent: "Fix selected" });
        fix.disabled = picked.length === 0;
        fix.onclick = () => {
            open(false);
            onFix(picked.map(({ selector, problem, text }) => ({ selector, problem, text })));
        };
        menu.replaceChildren(...shown().map(row), fix);
    }

    function update() {
        const n = shown().length;
        chip.hidden = n === 0;
        chip.textContent = n === 1 ? "1 layout issue" : n + " layout issues";
        if (n === 0) open(false);
        draw();
    }

    chip.onclick = () => open(menu.hidden);
    addEventListener("mousedown", (e) => {
        if (!menu.hidden && !e.target.closest("#layoutBox")) open(false);
    });
    addEventListener("keydown", (e) => {
        if (e.key === "Escape") open(false);
    });

    return {
        // Call after one send went out with these issues in it.
        sent(list) {
            list.forEach((i) => { sentAt[keyOf(i)] = Date.now(); });
            try { sessionStorage.setItem(store("sent"), JSON.stringify(sentAt)); } catch (e) {}
        },
        onMessage(m) {
            if (m.type === "ready") loadedAt = Date.now();
            if (m.type !== "layout") return;
            issues = m.issues;
            update();
        },
    };
}
