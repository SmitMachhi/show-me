// "What changed": compares the page now with the page as it was when the reviewer last
// sent notes, and shows the count in the top bar. Click the count to step through.
// The comparison itself runs in the page (changes.js); this side only keeps the "before".
export function createChanges(key, tell) {
    const chip = document.getElementById("changes");
    const store = "showme:before:" + key;
    let before = null;
    // True from one send until the page answers with its blocks as they are then.
    let rebase = false;
    try { before = JSON.parse(sessionStorage.getItem(store)); } catch (e) {}

    function compare() {
        try { sessionStorage.setItem(store, JSON.stringify(before)); } catch (e) {}
        tell({ type: "diff", before });
    }

    chip.onclick = () => tell({ type: "step" });

    return {
        // Handles the two messages the page sends about changes.
        onMessage(m) {
            if (m.type === "blocks") {
                if (!before || rebase) before = m.texts;
                rebase = false;
                compare();
            } else if (m.type === "changes") {
                chip.hidden = !m.count;
                chip.textContent = m.count === 1 ? "1 change" : m.count + " changes";
            }
        },
        // Call when notes are sent: from then on, changes are measured from the page as it
        // is now. The page is asked again, because it may have drawn more since it loaded.
        reset() {
            rebase = true;
            tell({ type: "snapshot" });
        },
    };
}
