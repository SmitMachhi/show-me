// Added to the reviewed page by show-me. Marks what changed since the reviewer last
// sent notes, so they can see what the agent did without rereading the page.
// The page author does nothing for this: blocks of text are compared as they are.
// Limits: a block that was removed leaves nothing to mark, and a block that only moved
// counts as unchanged. Content drawn by the page's own script after load is not seen.
(function () {
    const BLOCKS = "h1,h2,h3,h4,h5,h6,p,li,td,th,dt,dd,pre,blockquote,figcaption,summary,g.node,g.edge";
    const GREEN = "#2b9348";
    const CSS_TEXT =
        "[data-showme-changed]{box-shadow:-3px 0 0 " + GREEN + "}" +
        "g[data-showme-changed]>polygon,g[data-showme-changed]>path,g[data-showme-changed]>ellipse{stroke:" + GREEN + ";stroke-width:2.5}" +
        "[data-showme-now]{animation:showme-now .6s steps(2,jump-none)}" +
        "@keyframes showme-now{0%,50%{outline:3px solid " + GREEN + ";outline-offset:3px}}";
    let changed = [];
    let at = -1;

    function post(msg) {
        parent.postMessage(Object.assign({ source: "showme" }, msg), "*");
    }

    function textOf(el) {
        return el.textContent.replace(/\s+/g, " ").trim();
    }

    // The innermost blocks that hold words. A list item that holds one paragraph counts once.
    function blocks() {
        return [...document.querySelectorAll(BLOCKS)].filter((el) =>
            !el.closest("[data-showme-ui]") && !el.querySelector(BLOCKS) && textOf(el));
    }

    // `before` is the text of every block at the last send. Each block whose text was not
    // there then is new or edited.
    function mark(before) {
        const left = new Map();
        for (const text of before) left.set(text, (left.get(text) || 0) + 1);
        for (const el of document.querySelectorAll("[data-showme-changed]")) el.removeAttribute("data-showme-changed");
        changed = blocks().filter((el) => {
            const n = left.get(textOf(el)) || 0;
            if (n) left.set(textOf(el), n - 1);
            return !n;
        });
        for (const el of changed) el.setAttribute("data-showme-changed", "");
        at = -1;
        post({ type: "changes", count: changed.length });
    }

    function step() {
        if (!changed.length) return;
        at = (at + 1) % changed.length;
        const el = changed[at];
        el.scrollIntoView({ block: "center" });
        el.removeAttribute("data-showme-now");
        void el.getBoundingClientRect();
        el.setAttribute("data-showme-now", "");
    }

    const style = document.createElement("style");
    style.textContent = CSS_TEXT;
    document.head.appendChild(style);
    addEventListener("message", (e) => {
        const m = e.data;
        if (e.source !== parent || !m || m.source !== "showme-panel") return;
        if (m.type === "diff") mark(m.before);
        if (m.type === "step") step();
    });
    post({ type: "blocks", texts: blocks().map(textOf) });
})();
