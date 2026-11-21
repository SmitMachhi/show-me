// The unsent notes of this tab, in order. They live in sessionStorage, so one reload
// keeps them. Each note gets one id when it is queued: a send retried after one lost
// answer then stores nothing twice, because the daemon skips ids it already has.
export const newId = () => crypto.randomUUID?.() ??
    [...crypto.getRandomValues(new Uint8Array(16))].map((b) => b.toString(16).padStart(2, "0")).join("");

export function createQueue(key) {
    const store = "showme:queue:" + key;
    let items = [];
    try { items = JSON.parse(sessionStorage.getItem(store)) || []; } catch (e) {}
    const keep = () => {
        try { sessionStorage.setItem(store, JSON.stringify(items)); } catch (e) {}
    };
    return {
        get items() { return items; },
        // Adds one note. One note with `question` replaces the unsent note with the same
        // question, so one form page keeps one answer for each question.
        add(n) {
            if (n.question) items = items.filter((o) => o.question !== n.question);
            items.push(Object.assign({ id: newId() }, n));
            keep();
        },
        remove(i) {
            items.splice(i, 1);
            keep();
        },
        // Saves the words of note i. The note gets one new id only when its words change,
        // so the daemon stores one changed note again but never one unchanged note twice.
        // One note with pictures keeps them when its words are cleared; one empty note goes.
        edit(i, text) {
            const n = items[i];
            if (text === n.note) return;
            if (text || (n.images && n.images.length)) Object.assign(n, { note: text, id: newId() });
            else items.splice(i, 1);
            keep();
        },
        clear() {
            items = [];
            keep();
        },
    };
}
