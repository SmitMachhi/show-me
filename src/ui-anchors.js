// Queued notes and the page. The page learns where each queued note points (its id,
// selector and diagram node), never its words: the page is the untrusted side. The page
// marks those elements, and one click on a marked element asks the panel to edit that note.
const el = (id) => document.getElementById(id);

export function createAnchors(tell, queue) {
    return {
        // Sends the current anchors. Call it after each queue change and when the page loads.
        sync() {
            const items = queue().filter((n) => n.id && n.selector && n.kind === "element")
                .map((n) => ({ id: n.id, selector: n.selector, node: n.node || "" }));
            tell({ type: "anchors", items });
        },
        // Opens the inline editor of the queued note with this id.
        edit(id) {
            if (document.body.classList.contains("collapsed")) el("toggle").click();
            const i = queue().findIndex((n) => n.id === id);
            const row = el("list").querySelectorAll(":scope > li.queued")[i];
            if (!row) return;
            row.scrollIntoView({ block: "nearest" });
            row.click();
        },
    };
}
