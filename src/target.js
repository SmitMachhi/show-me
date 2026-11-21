// Added to the reviewed page by show-me. What one click or one selection points at:
// which elements are controls, the row and column of one table cell, which elements
// hold queued notes, links that leave the page, and the mark on selected words.
// Exposes window.showmeTarget. inject.js uses it.
(function () {
    // Elements that work as controls: clicks reach them and make no note. The same list
    // as lavish, with the ARIA widget roles for controls built from plain elements.
    const CONTROLS = "button,input,select,textarea,option,optgroup,label,summary," +
        "[contenteditable]:not([contenteditable='false']),[data-showme-action],[data-showme-ui]," +
        "[role=button],[role=checkbox],[role=combobox],[role=menuitem],[role=menuitemcheckbox]," +
        "[role=menuitemradio],[role=option],[role=radio],[role=switch],[role=tab],[role=treeitem]";

    // Names the row and column of one table cell, so the note still makes sense after the
    // table is sorted or filtered. Returns null when merged cells make the names unsure.
    function cellOf(el) {
        const cell = el.closest("td,th");
        const table = cell && cell.closest("table");
        if (!table || table.querySelector("[colspan],[rowspan]")) return null;
        const head = table.querySelector("tr");
        const column = head.children[cell.cellIndex];
        const row = cell.parentNode.children[0];
        const clean = (c) => (c && c !== cell ? c.textContent.trim().slice(0, 60) : "");
        const names = { row: clean(row), column: clean(head === cell.parentNode ? null : column) };
        return names.row || names.column ? names : null;
    }

    // Where queued notes point: [{ id, selector, node }] from the panel, without their words.
    let anchors = [];

    // The element one anchor points at: the diagram node by name, else the selector.
    function anchored(a) {
        if (a.node) return [...document.querySelectorAll("g.node,g.edge,g.cluster")].find((g) => g.querySelector("title")?.textContent === a.node);
        try { return document.querySelector(a.selector); } catch (e) { return null; }
    }

    function setAnchors(items) {
        anchors = items;
        for (const el of document.querySelectorAll("[data-showme-queued]")) el.removeAttribute("data-showme-queued");
        for (const a of anchors) anchored(a)?.setAttribute("data-showme-queued", "");
    }

    // The queued note that one new note would point at again, or undefined.
    function heldBy(note) {
        return anchors.find((a) => (note.node ? a.node === note.node : a.selector === note.selector));
    }

    // True for one link to another document. Same-page "#part" links stay in the frame.
    function leaves(link) {
        return !(link.getAttribute("href") || "").startsWith("#") && link.href.split("#")[0] !== location.href.split("#")[0];
    }

    // Marks exactly the selected words with the CSS Custom Highlight API, which adds no
    // element and follows reflow. Returns false where the browser has no such API.
    function markWords(range) {
        if (!window.CSS || !CSS.highlights || !window.Highlight) return false;
        CSS.highlights.set("showme", new Highlight(range));
        return true;
    }

    function clearWords() {
        if (window.CSS && CSS.highlights) CSS.highlights.delete("showme");
    }

    window.showmeTarget = { CONTROLS, cellOf, setAnchors, heldBy, leaves, markWords, clearWords };
})();
