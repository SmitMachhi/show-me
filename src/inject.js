// Added to the reviewed page by show-me. Turns clicks and text selections into
// messages for the review panel. The page cannot read the panel or send notes itself:
// it runs in one sandboxed frame with no origin, and only posts to its parent.
(function () {
    const CONTROLS = "a[href],button,input,select,textarea,label,summary,[contenteditable],[data-showme-action]";

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

    function pick(el, kind, text) {
        const msg = { type: "pick", kind, selector: selectorOf(el), text: text.trim().slice(0, 500) };
        const part = el.closest("g.node,g.edge");
        const title = part && part.querySelector("title");
        if (title) msg.node = title.textContent;
        post(msg);
    }

    const style = document.createElement("style");
    style.textContent = "[data-showme-hover]{outline:2px solid #2563eb;outline-offset:2px;cursor:crosshair}";
    document.head.appendChild(style);

    let hovered = null;
    addEventListener("mouseover", (e) => {
        if (hovered) hovered.removeAttribute("data-showme-hover");
        hovered = e.target.closest(CONTROLS) ? null : e.target;
        if (hovered) hovered.setAttribute("data-showme-hover", "");
    }, true);

    addEventListener("click", (e) => {
        if (e.target.closest(CONTROLS) || String(getSelection()).trim()) return;
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

    // For pages that are forms: window.showme.send("Use plan B", { plan: "B" })
    window.showme = {
        send(note, data) {
            post({ type: "note", kind: "page", note: String(note), data: data === undefined ? null : data });
        },
    };
})();
