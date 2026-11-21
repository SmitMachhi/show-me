// Added to the reviewed page by show-me. Turns clicks and text selections into notes,
// and follows orders from the review panel: annotate mode, reveal, restore scroll.
// The page cannot read the panel: it runs in one sandboxed frame with no origin.
// What one click points at (controls, table cells, queued notes) is in target.js.
(function () {
    const T = window.showmeTarget;
    const ACCENT = "#3657d6";
    const CSS_TEXT =
        "html{scrollbar-width:thin;scrollbar-color:#8886 transparent}" +
        "html[data-showme-annotate] [data-showme-hover]{outline:2px solid " + ACCENT + "66;outline-offset:2px;cursor:crosshair}" +
        "[data-showme-queued]:not(g){outline:2px dashed " + ACCENT + "99;outline-offset:2px}" +
        "g[data-showme-queued]>polygon,g[data-showme-queued]>path,g[data-showme-queued]>ellipse{stroke:" + ACCENT + ";stroke-dasharray:4 3}" +
        "[data-showme-picked]{outline:2px solid " + ACCENT + ";outline-offset:2px;box-shadow:0 0 0 6px " + ACCENT + "22}" +
        "::highlight(showme){background-color:" + ACCENT + "33}" +
        "[data-showme-flash]{animation:showme-flash .6s steps(2,jump-none)}" +
        "@keyframes showme-flash{0%,50%{outline:3px solid " + ACCENT + ";outline-offset:3px;box-shadow:0 0 0 8px " + ACCENT + "33}}" +
        "@media(prefers-reduced-motion:reduce){[data-showme-flash]{animation-duration:.01s}}";
    const root = document.documentElement;
    let annotate = root.getAttribute("data-showme-annotate") !== "off";

    function post(msg) {
        parent.postMessage(Object.assign({ source: "showme" }, msg), "*");
    }

    function unmark(attr) {
        for (const el of document.querySelectorAll("[" + attr + "]")) el.removeAttribute(attr);
    }

    // Removes the mark of the note being written: the outline or the word highlight.
    function unpick() {
        unmark("data-showme-picked");
        T.clearWords();
    }

    function setMode(on) {
        annotate = on;
        root.toggleAttribute("data-showme-annotate", on);
        if (!on) {
            unmark("data-showme-hover");
            window.showmeCard.close();
        }
    }

    // Opens the note card at one element. `text` is its words, or the selected words.
    // `range` is the selection for text notes. `picture` is one image blob to attach.
    // A card that already holds words keeps them and gets the picture.
    function pick(el, kind, text, picture, range) {
        if (picture) setTimeout(() => post({ type: "image", blob: picture }));
        if (window.showmeCard.busy()) return;
        const part = el.closest("g.node,g.edge,g.cluster");
        const title = part && part.querySelector("title");
        // One full-window view shows a copy, which names the diagram in the page that it copies.
        const within = el.closest("dialog[data-of]");
        const note = { kind, selector: within ? within.dataset.of : window.showmeSelector(el), text: text.trim().slice(0, 500) };
        if (title) note.node = title.textContent;
        const cell = T.cellOf(el);
        if (cell) note.cell = cell;
        // One click on one element that holds one queued note edits that note in the panel.
        const held = kind === "element" && T.heldBy(note);
        if (held) return post({ type: "edit", id: held.id });
        window.showmeCard.close(); // clears the mark of one earlier card
        unpick();
        if (!(range && T.markWords(range))) (part || el).setAttribute("data-showme-picked", "");
        const label = note.node || (kind === "text" ? "“" + note.text.slice(0, 60) + "”" : note.text.slice(0, 60) || note.selector);
        const target = { label, rect: (part || el).getBoundingClientRect(), within };
        window.showmeCard.open(target, (words, sendNow, images) => {
            post(Object.assign({ type: "note", note: words, sendNow }, images.length ? { images } : {}, note));
        }, (file) => post({ type: "image", blob: file }), unpick);
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
        if (annotate && !e.target.closest(T.CONTROLS)) e.target.setAttribute("data-showme-hover", "");
    }, true);

    addEventListener("click", (e) => {
        const link = T.linkOf(e.target);
        const control = e.target.closest(T.CONTROLS);
        // A link never takes the review frame away. In annotate mode one plain click makes
        // one note on it; Ctrl or Cmd click, and any click in explore mode, open one new tab.
        if (link && link.leaves && (!annotate || e.ctrlKey || e.metaKey || control)) {
            e.preventDefault();
            window.open(link.url, "_blank", "noopener");
            return;
        }
        if (link && annotate) e.preventDefault();
        // The diagram view sets showmeDragged when one drag ends, so that drag is not one pick.
        // textPicked: this click ends one drag-select that already opened one text card.
        const skip = !annotate || window.showmeDragged || textPicked || control || String(getSelection()).trim();
        window.showmeDragged = false;
        textPicked = false;
        if (skip) return;
        e.preventDefault();
        e.stopPropagation();
        pick(e.target, "element", e.target.textContent || "");
    }, true);

    // One file dropped outside the note card must not replace the reviewed page.
    const files = (e) => e.dataTransfer && e.dataTransfer.types.includes("Files");
    addEventListener("dragover", (e) => { if (files(e)) e.preventDefault(); });
    addEventListener("drop", (e) => { if (files(e)) e.preventDefault(); });

    // True from one mouseup that opened one text card until the next press. The browser
    // sends one click after that mouseup, and the click must not open one element card.
    let textPicked = false;
    addEventListener("mousedown", () => { textPicked = false; }, true);

    addEventListener("mouseup", (e) => {
        const sel = getSelection();
        const text = String(sel).trim();
        if (!annotate || !text || e.target.closest("[data-showme-ui]")) return;
        textPicked = true;
        // Copy the range now: the card takes focus next, and the selection may go.
        const range = sel.getRangeAt(0).cloneRange();
        const node = range.commonAncestorContainer;
        pick(node.nodeType === 1 ? node : node.parentElement, "text", text, null, range);
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
        if (m.type === "imageDone") window.showmeCard.addImage(m.id, m.url);
        if (m.type === "imageFailed") window.showmeCard.fail("Couldn't add the image. " + m.error);
        if (m.type === "anchors") T.setAnchors(m.items);
    });

    window.showmePick = pick; // graph.js calls this with one drawing

    // For pages that are forms: window.showme.send("Use plan B", { plan: "B" }, options)
    // options.question: one name; one later answer with the same name replaces this one
    // while both are unsent. options.now: send at once. options.end: send, then end.
    window.showme = {
        send(note, data, options) {
            const o = options || {};
            post(Object.assign({ type: "note", kind: "page", note: String(note), data: data === undefined ? null : data },
                o.question ? { question: String(o.question) } : {}, { sendNow: !!o.now, end: !!o.end }));
        },
    };
    post({ type: "ready", title: document.title, annotate });
})();
