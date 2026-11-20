// Added to the reviewed page by show-me. Turns clicks and text selections into
// messages for the review panel, and gives each diagram one full-window view.
// The page cannot read the panel or send notes itself: it runs in one sandboxed frame
// with no origin, and only posts to its parent.
(function () {
    const CONTROLS = "a[href],button,input,select,textarea,label,summary,[contenteditable],[data-showme-action]";
    const CSS_TEXT = "[data-showme-hover]{outline:2px solid #2563eb;outline-offset:2px;cursor:crosshair}" +
        ".showme-graph{margin:1em 0}.showme-graph svg{max-width:100%;height:auto;display:block}" +
        ".showme-graph>button,.showme-full>button{float:right}" +
        "dialog.showme-full[open]{display:flex;flex-direction:column;width:100vw;height:100vh;" +
        "max-width:none;max-height:none;margin:0;border:0;padding:8px;box-sizing:border-box}" +
        "dialog.showme-full svg{flex:1;min-height:0;width:100%;cursor:grab;touch-action:none}" +
        "dialog.showme-full>button{align-self:flex-end}";
    let dragged = false;

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
        const part = el.closest("g.node,g.edge,g.cluster");
        const title = part && part.querySelector("title");
        if (title) msg.node = title.textContent;
        post(msg);
    }

    function button(text, onclick) {
        const b = document.createElement("button");
        b.textContent = text;
        b.onclick = onclick;
        return b;
    }

    // Wheel zooms about the pointer. Drag pans. Both only change the viewBox.
    function panZoom(svg) {
        let [x, y, w, h] = svg.getAttribute("viewBox").split(/[ ,]+/).map(Number);
        let from = null;
        const set = () => svg.setAttribute("viewBox", [x, y, w, h].join(" "));
        svg.addEventListener("wheel", (e) => {
            e.preventDefault();
            const k = e.deltaY < 0 ? 0.85 : 1.18;
            const r = svg.getBoundingClientRect();
            x += ((e.clientX - r.left) / r.width) * w * (1 - k);
            y += ((e.clientY - r.top) / r.height) * h * (1 - k);
            w *= k;
            h *= k;
            set();
        }, { passive: false });
        svg.addEventListener("pointerdown", (e) => { from = { cx: e.clientX, cy: e.clientY, x, y }; dragged = false; });
        svg.addEventListener("pointermove", (e) => {
            if (!from) return;
            const r = svg.getBoundingClientRect();
            if (Math.abs(e.clientX - from.cx) + Math.abs(e.clientY - from.cy) > 4) dragged = true;
            x = from.x - ((e.clientX - from.cx) / r.width) * w;
            y = from.y - ((e.clientY - from.cy) / r.height) * h;
            set();
        });
        addEventListener("pointerup", () => { from = null; });
    }

    function expand(svg) {
        const full = document.createElement("dialog");
        full.className = "showme-full";
        const copy = svg.cloneNode(true);
        copy.removeAttribute("width");
        copy.removeAttribute("height");
        full.append(button("Close", () => full.remove()), copy);
        full.onclose = () => full.remove(); // Esc
        document.body.append(full);
        full.showModal();
        panZoom(copy);
    }

    const style = document.createElement("style");
    style.textContent = CSS_TEXT;
    document.head.appendChild(style);
    for (const svg of document.querySelectorAll("figure.showme-graph > svg")) {
        svg.before(button("Expand", () => expand(svg)));
    }

    let hovered = null;
    addEventListener("mouseover", (e) => {
        if (hovered) hovered.removeAttribute("data-showme-hover");
        hovered = e.target.closest(CONTROLS) ? null : e.target;
        if (hovered) hovered.setAttribute("data-showme-hover", "");
    }, true);

    addEventListener("click", (e) => {
        const skip = dragged || e.target.closest(CONTROLS) || String(getSelection()).trim();
        dragged = false;
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

    // For pages that are forms: window.showme.send("Use plan B", { plan: "B" })
    window.showme = {
        send(note, data) {
            post({ type: "note", kind: "page", note: String(note), data: data === undefined ? null : data });
        },
    };
})();
