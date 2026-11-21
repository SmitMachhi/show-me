// Added to the reviewed page by show-me. Keeps unsent work across one reload of the page:
// the agent edits the file, the page reloads, and the reviewer loses nothing.
// The page has no storage of its own (one sandboxed frame), so it reports each change
// to the panel, and the panel sends it back after the next load.
// - Form values: only fields with one id or one name, because a position can point at
//   another field after the agent's edit. Password and file fields are never kept.
//   Restored values fire no events, so page code does not see them as new answers.
// - The open note card: it opens again at its element. When the element is gone, its
//   words become one queued note, so they are not lost.
(function () {
    function post(msg) {
        parent.postMessage(Object.assign({ source: "showme" }, msg), "*");
    }

    function fieldKey(el) {
        if (!el.matches || !el.matches("input,select,textarea") || el.closest("[data-showme-ui]")) return null;
        if (["password", "file", "hidden", "submit", "button", "reset", "image"].includes(el.type)) return null;
        const choice = el.type === "checkbox" || el.type === "radio" ? ":" + el.value : "";
        if (el.id) return "#" + el.id;
        return el.name ? "name:" + el.name + choice : null;
    }

    function values() {
        const out = {};
        for (const el of document.querySelectorAll("input,select,textarea")) {
            const k = fieldKey(el);
            if (k) out[k] = el.type === "checkbox" || el.type === "radio" ? el.checked : el.value;
        }
        return out;
    }

    function restoreForm(saved) {
        for (const el of document.querySelectorAll("input,select,textarea")) {
            const k = fieldKey(el);
            if (!k || !(k in saved)) continue;
            if (el.type === "checkbox" || el.type === "radio") el.checked = saved[k];
            else el.value = saved[k];
        }
    }

    // The element that one saved card pointed at: the diagram node by name, else the selector.
    function find(card) {
        if (card.node) return [...document.querySelectorAll("g.node,g.edge,g.cluster")].find((g) => g.querySelector("title")?.textContent === card.node);
        try { return document.querySelector(card.selector); } catch (e) { return null; }
    }

    function restoreCard(card) {
        const el = find(card);
        if (!el) {
            // The words are queued once, and the saved card goes, so no later load queues them again.
            const { words, ...note } = card;
            post(Object.assign(note, { type: "note", note: words }));
            return post({ type: "draft", card: null });
        }
        window.showmePick(el, card.kind === "text" ? "element" : card.kind, card.text || "");
        window.showmeCard.setWords(card.words);
        post({ type: "draft", card });
    }

    const report = (e) => { if (fieldKey(e.target)) post({ type: "draftForm", values: values() }); };
    addEventListener("input", report, true);
    addEventListener("change", report, true);
    addEventListener("message", (e) => {
        const m = e.data;
        if (e.source !== parent || !m || m.source !== "showme-panel" || m.type !== "restoreDraft") return;
        if (m.form) restoreForm(m.form);
        if (m.card) restoreCard(m.card);
    });
    post({ type: "draftsWanted" });
})();
