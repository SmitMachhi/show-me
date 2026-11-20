// Layout problems the page found in itself (layout.js). The top bar shows the count.
// Click it for the list: click one to see it on the page, or ask the agent to fix all.
// Nothing here reaches the agent until the reviewer asks.
const el = (id) => document.getElementById(id);

export function createLayout(tell, onFix) {
    const chip = el("layout");
    const menu = el("layoutMenu");
    let issues = [];

    function open(show) {
        menu.hidden = !show;
        chip.setAttribute("aria-expanded", String(show));
    }

    function draw() {
        const rows = issues.map((issue) => {
            const b = document.createElement("button");
            const small = document.createElement("small");
            b.type = "button";
            b.textContent = issue.text || issue.selector;
            small.textContent = issue.problem;
            b.append(small);
            b.onclick = () => tell({ type: "reveal", selector: issue.selector });
            return b;
        });
        const fix = document.createElement("button");
        fix.type = "button";
        fix.className = "primary";
        fix.textContent = "Ask agent to fix";
        fix.onclick = () => {
            open(false);
            onFix(issues.map(({ selector, problem }) => ({ selector, problem })));
        };
        menu.replaceChildren(...rows, fix);
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
            chip.hidden = issues.length === 0;
            chip.textContent = issues.length === 1 ? "1 layout issue" : issues.length + " layout issues";
            if (issues.length === 0) open(false);
            draw();
        },
    };
}
