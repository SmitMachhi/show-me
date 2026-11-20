// Added to the reviewed page by show-me. Turns clicks and text selections into
// messages for the review panel. The page cannot read the panel or send notes itself:
// it runs in one sandboxed frame with no origin, and only posts to its parent.
(function () {
    const CONTROLS = "a[href],button,input,select,textarea,label,summary,[contenteditable],[data-showme-action]";
    const ACCENT = "#3657d6";
    const CSS_TEXT =
        "[data-showme-hover]{outline:2px solid " + ACCENT + "66;outline-offset:2px;cursor:crosshair}" +
        "[data-showme-picked]{outline:2px solid " + ACCENT + ";outline-offset:2px;" +
        "box-shadow:0 0 0 6px " + ACCENT + "22;transition:box-shadow .14s cubic-bezier(.2,0,0,1)}";

    function selectorOf(el) {
        const parts = [];
        while (el && el.nodeType === 1 && el !== document.documentElement) {
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

    function pick(el, kind, text) {
        const msg = { type: "pick", kind, selector: selectorOf(el), text: text.trim().slice(0, 500) };
        const part = el.closest("g.node,g.edge,g.cluster");
        const title = part && part.querySelector("title");
        if (title) msg.node = title.textContent;
        unmark("data-showme-picked");
        (part || el).setAttribute("data-showme-picked", "");
        post(msg);
    }

    const style = document.createElement("style");
    style.textContent = CSS_TEXT;
    document.head.appendChild(style);

    addEventListener("mouseover", (e) => {
        unmark("data-showme-hover");
        if (!e.target.closest(CONTROLS)) e.target.setAttribute("data-showme-hover", "");
    }, true);

    addEventListener("click", (e) => {
        // The diagram view sets this flag when one drag ends, so that drag is not one pick.
        const skip = window.showmeDragged || e.target.closest(CONTROLS) || String(getSelection()).trim();
        window.showmeDragged = false;
        if (skip) return;
        e.preventDefault();
        e.stopPropagation();
        pick(e.target, "element", e.target.textContent || "");
    }, true);

    addEventListener("mouseup", () => {
        const sel = getSelection();
        const text = String(sel).trim();
        if (!text) return;
        const node = sel.getRangeAt(0).commonAncestorContainer;
        pick(node.nodeType === 1 ? node : node.parentElement, "text", text);
    });

    // The panel says when the picked element is no longer the target.
    addEventListener("message", (e) => {
        if (e.source === parent && e.data && e.data.source === "showme-panel" && e.data.type === "clear") {
            unmark("data-showme-picked");
        }
    });

    // For pages that are forms: window.showme.send("Use plan B", { plan: "B" })
    window.showme = {
        send(note, data) {
            post({ type: "note", kind: "page", note: String(note), data: data === undefined ? null : data });
        },
    };
})();
