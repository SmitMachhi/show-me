// "What changed": compares the page now with the page as it was when the reviewer last
// sent notes, and shows the count in the top bar. Click the count to step through.
// The comparison itself runs in the page (changes.js); this side only keeps the "before".
export function createChanges(key, tell) {
    const chip = document.getElementById("changes");
    const store = "showme:before:" + key;
    let before = null;
    let now = [];
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
                now = m.texts;
                if (!before) before = now;
                compare();
            } else if (m.type === "changes") {
                chip.hidden = !m.count;
                chip.textContent = m.count === 1 ? "1 change" : m.count + " changes";
            }
        },
        // Call when notes are sent: from then on, changes are measured from this page.
        reset() {
            before = now;
            compare();
        },
    };
}
