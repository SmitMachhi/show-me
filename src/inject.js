// Added to the reviewed page by show-me. Turns clicks and text selections into notes,
// and follows orders from the review panel: annotate mode, reveal, restore scroll.
// The page cannot read the panel: it runs in one sandboxed frame with no origin.
(function () {
    const CONTROLS = "a[href],button,input,select,textarea,label,summary,[contenteditable],[data-showme-action],[data-showme-ui]";
    const ACCENT = "#3657d6";
    const CSS_TEXT =
        "html[data-showme-annotate] [data-showme-hover]{outline:2px solid " + ACCENT + "66;outline-offset:2px;cursor:crosshair}" +
        "[data-showme-picked]{outline:2px solid " + ACCENT + ";outline-offset:2px;box-shadow:0 0 0 6px " + ACCENT + "22}" +
        "[data-showme-flash]{animation:showme-flash .6s steps(2,jump-none)}" +
        "@keyframes showme-flash{0%,50%{outline:3px solid " + ACCENT + ";outline-offset:3px;box-shadow:0 0 0 8px " + ACCENT + "33}}" +
        "@media(prefers-reduced-motion:reduce){[data-showme-flash]{animation-duration:.01s}}";
    const root = document.documentElement;
    let annotate = root.getAttribute("data-showme-annotate") !== "off";

    function selectorOf(el) {
        const parts = [];
        while (el && el.nodeType === 1 && el !== root) {
            let part = el.tagName.toLowerCase();
            if (el.id) {
                parts.unshift(part + "#" + CSS.escape(el.id));
                break;
            }
            const twins = [...el.parentNode.children].filter((c) => c.tagName === el.tagName);
            if (twins.length > 1) part += ":nth-of-type(" + (twins.indexOf(el) + 1) + ")";
            parts.unshift(part);
            el = el.parentNode;
        }
        return parts.join(" > ");
    }

    function post(msg) {
        parent.postMessage(Object.assign({ source: "showme" }, msg), "*");
    }

    function unmark(attr) {
        for (const el of document.querySelectorAll("[" + attr + "]")) el.removeAttribute(attr);
    }

    function setMode(on) {
        annotate = on;
        root.toggleAttribute("data-showme-annotate", on);
        if (!on) {
            unmark("data-showme-hover");
            unmark("data-showme-picked");
            window.showmeCard.close();
        }
    }

    // Opens the note card at one element. `text` is its words, or the selected words.
    function pick(el, kind, text) {
        if (window.showmeCard.busy()) return;
        const part = el.closest("g.node,g.edge,g.cluster");
        const title = part && part.querySelector("title");
        const note = { kind, selector: selectorOf(el), text: text.trim().slice(0, 500) };
        if (title) note.node = title.textContent;
        unmark("data-showme-picked");
        (part || el).setAttribute("data-showme-picked", "");
        const label = note.node || (kind === "text" ? "“" + note.text.slice(0, 60) + "”" : note.text.slice(0, 60) || note.selector);
        window.showmeCard.open({ label, rect: (part || el).getBoundingClientRect() }, (words, sendNow) => {
            unmark("data-showme-picked");
            post(Object.assign({ type: "note", note: words, sendNow }, note));
        });
    }

    function reveal(selector) {
        let el = null;
        try { el = document.querySelector(selector); } catch (e) { return; }
        if (!el) return;
        el.scrollIntoView({ block: "center" });
        unmark("data-showme-flash");
        el.setAttribute("data-showme-flash", "");
        setTimeout(() => el.removeAttribute("data-showme-flash"), 700);
    }

    const style = document.createElement("style");
    style.textContent = CSS_TEXT;
    document.head.appendChild(style);
    setMode(annotate);

    addEventListener("mouseover", (e) => {
        unmark("data-showme-hover");
        if (annotate && !e.target.closest(CONTROLS)) e.target.setAttribute("data-showme-hover", "");
    }, true);

    addEventListener("click", (e) => {
        // The diagram view sets this flag when one drag ends, so that drag is not one pick.
        const skip = !annotate || window.showmeDragged || e.target.closest(CONTROLS) || String(getSelection()).trim();
        window.showmeDragged = false;
        if (skip) return;
        e.preventDefault();
        e.stopPropagation();
        pick(e.target, "element", e.target.textContent || "");
    }, true);

    addEventListener("mouseup", (e) => {
        const sel = getSelection();
        const text = String(sel).trim();
        if (!annotate || !text || e.target.closest("[data-showme-ui]")) return;
        const node = sel.getRangeAt(0).commonAncestorContainer;
        pick(node.nodeType === 1 ? node : node.parentElement, "text", text);
    });

    // Ctrl+I or Cmd+I switches between annotate and explore, from inside the page too.
    addEventListener("keydown", (e) => {
        if ((e.ctrlKey || e.metaKey) && !e.shiftKey && !e.altKey && e.key.toLowerCase() === "i") {
            e.preventDefault();
            post({ type: "toggleMode" });
        }
    }, true);

    let ticking = false;
    addEventListener("scroll", () => {
        if (ticking) return;
        ticking = true;
        requestAnimationFrame(() => { ticking = false; post({ type: "scroll", y: scrollY }); });
    }, { passive: true });

    addEventListener("message", (e) => {
        const m = e.data;
        if (e.source !== parent || !m || m.source !== "showme-panel") return;
        if (m.type === "mode") setMode(m.on);
        if (m.type === "reveal") reveal(m.selector);
        if (m.type === "restore") scrollTo(0, m.y);
    });

    // For pages that are forms: window.showme.send("Use plan B", { plan: "B" })
    window.showme = {
        send(note, data) {
            post({ type: "note", kind: "page", note: String(note), data: data === undefined ? null : data });
        },
    };
    post({ type: "ready", title: document.title, annotate });
})();
