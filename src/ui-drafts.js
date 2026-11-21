// Unsent work in the page (the open note card, form values), kept for one reload. The
// page reports it (drafts.js) and gets it back after its next load. It lives in this
// tab's sessionStorage, like the queue. One saved state larger than 20 KB is dropped.
const MAX = 20000;

export function createDrafts(key, tell) {
    const store = "showme:drafts:" + key;
    let saved = { card: null, form: null };
    try { saved = JSON.parse(sessionStorage.getItem(store)) || saved; } catch (e) {}
    const keep = () => {
        const text = JSON.stringify(saved);
        try { sessionStorage.setItem(store, text.length > MAX ? JSON.stringify({ card: null, form: null }) : text); } catch (e) {}
    };
    return {
        // Handles the page messages about drafts, and sends them back once the page loads.
        onMessage(m) {
            if (m.type === "draft") saved.card = m.card;
            if (m.type === "draftForm") saved.form = m.values;
            if (m.type === "draft" || m.type === "draftForm") keep();
            // drafts.js asks once it has loaded. "ready" can come first, before it listens.
            if (m.type === "draftsWanted" && (saved.card || saved.form)) tell({ type: "restoreDraft", card: saved.card, form: saved.form });
        },
    };
}
