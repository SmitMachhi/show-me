// Layout problems the page found in itself (layout.js). The top bar shows the count.
// Click it for the list: one click on one issue shows it on the page. Each issue has
// one checkbox for "Fix selected" and one Dismiss button. One issue that was sent for
// fixing and is found again says "Still there".
// Nothing here reaches the agent until the reviewer asks. Dismissed and sent issues
// live in this tab's sessionStorage, keyed by problem and selector.
const el = (id) => document.getElementById(id);
const keyOf = (issue) => issue.problem + " " + issue.selector;

export function createLayout(key, tell, onFix) {
    const chip = el("layout");
    const menu = el("layoutMenu");
    const store = (name) => "showme:layout-" + name + ":" + key;
    const load = (name) => { try { return new Set(JSON.parse(sessionStorage.getItem(store(name))) || []); } catch (e) { return new Set(); } };
    const keep = (name, set) => { try { sessionStorage.setItem(store(name), JSON.stringify([...set])); } catch (e) {} };
    const dismissed = load("dismissed");
    const sent = load("sent");
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
        const small = Object.assign(document.createElement("small"), { textContent: issue.problem + (sent.has(k) ? " · Still there" : "") });
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
            picked.forEach((i) => sent.add(keyOf(i)));
            keep("sent", sent);
            onFix(picked.map(({ selector, problem }) => ({ selector, problem })));
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
        onMessage(m) {
            if (m.type !== "layout") return;
            issues = m.issues;
            update();
        },
    };
}
