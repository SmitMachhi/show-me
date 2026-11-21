// Added to the reviewed page by show-me. The note card: one small box that opens at the
// element the reviewer clicked, so they type where they point. It lives in its own
// shadow root, so page styles cannot reach it and its styles cannot leak out.
// Exposes window.showmeCard = { open(target, onQueue, onImage, onClose), close(), busy(), addImage() }.
// `onClose` runs once when the card goes, for any reason: Add, Cancel, Esc or one new card.
// `target` is { label, rect, within }: `within` is the open full-window view, or null.
(function () {
    const CSS_TEXT =
        ":host{all:initial;position:absolute;z-index:2147483647;width:300px;font:14px/1.4 system-ui,sans-serif}" +
        ".box{padding:8px;border-radius:14px;background:#fff;color:#1b1b1a;transform-origin:0 0;" +
        "box-shadow:0 0 0 1px #0000001a,0 2px 6px #0000001a,0 12px 32px #00000026;" +
        "animation:in .09s cubic-bezier(.22,1,.36,1)}" +
        "@keyframes in{from{opacity:0;scale:.96}}" +
        ".box.nudge{animation:nudge .1s cubic-bezier(.22,1,.36,1)}" +
        "@keyframes nudge{50%{scale:1.03}}" +
        ".where{margin:0 0 4px;padding:2px 6px;color:#6f6f6b;font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}" +
        "textarea{display:block;width:100%;box-sizing:border-box;padding:6px;border:0;outline:0;resize:none;" +
        "background:none;color:inherit;font:inherit}" +
        ".bar{display:flex;align-items:center;gap:6px;padding:4px 0 0 6px}" +
        "small{flex:1;color:#6f6f6b;font-size:12px}small.err{color:#d64545}" +
        "button{font:inherit;border:0;border-radius:8px;padding:6px 10px;cursor:pointer;background:none;color:#6f6f6b;" +
        "transition:scale .08s cubic-bezier(.22,1,.36,1),background-color .08s}" +
        "button:hover{background:#0000000f}button:active{scale:.96}" +
        "button.go{background:#3657d6;color:#fff}button.go:hover{background:#2f4cc0}" +
        ".pics{display:flex;gap:6px;padding:0 6px}.pics:empty{display:none}.pics img{width:40px;height:40px;object-fit:cover;border-radius:8px}" +
        "button.pic{display:grid;place-items:center;padding:6px}button.pic svg{width:16px;height:16px;fill:none;stroke:currentColor;" +
        "stroke-width:2;stroke-linecap:round;stroke-linejoin:round}.box.drop{box-shadow:0 0 0 2px #3657d6,0 12px 32px #00000026}" +
        "@media(prefers-color-scheme:dark){.box{background:#1f1f1f;color:#ededeb;" +
        "box-shadow:0 0 0 1px #ffffff26,0 12px 32px #00000080}.where,small,button{color:#9b9b96}" +
        "button:hover{background:#ffffff14}button.go{background:#8ea2ff;color:#10142b}}" +
        "@media(prefers-reduced-motion:reduce){.box,.box.nudge{animation:none}}";

    let host = null;
    let area = null;
    let pics = [];
    let strip = null;
    let closing = null;
    let small = null; // the line between the attach button and Cancel

    function close() {
        const done = closing;
        closing = null;
        if (host) host.remove();
        host = null;
        area = null;
        pics = [];
        if (done) done();
    }

    // Places the card under the target, or above it when there is no room below.
    // `scrolls` is false inside one full-window view, which does not move with the page.
    function place(rect, scrolls) {
        const top = rect.bottom + 8 + 150 > innerHeight && rect.top > 170 ? rect.top - 150 : rect.bottom + 8;
        host.style.top = (scrolls ? scrollY : 0) + top + "px";
        host.style.left = (scrolls ? scrollX : 0) + Math.max(8, Math.min(rect.left, innerWidth - 308)) + "px";
    }

    const PIC_ICON = '<svg viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="16" rx="2"/>' +
        '<circle cx="9" cy="10" r="1.5"/><path d="m4 18 5-5 4 4 3-3 4 4"/></svg>';

    // Pictures reach the card three ways: the attach button, paste, and drop.
    function takeImages(root, onImage) {
        const box = root.querySelector(".box");
        const input = root.querySelector("input[type=file]");
        const take = (files) => [...files].filter((f) => f.type.startsWith("image/")).forEach(onImage);
        root.querySelector(".pic").onclick = () => input.click();
        input.onchange = () => { take(input.files); input.value = ""; };
        area.onpaste = (e) => {
            if (![...e.clipboardData.files].some((f) => f.type.startsWith("image/"))) return;
            e.preventDefault();
            take(e.clipboardData.files);
        };
        box.ondragover = (e) => { e.preventDefault(); box.classList.add("drop"); };
        box.ondragleave = () => box.classList.remove("drop");
        box.ondrop = (e) => { e.preventDefault(); box.classList.remove("drop"); take(e.dataTransfer.files); };
    }

    // `onQueue(words, sendNow, pictureIds)` runs when the reviewer queues the note.
    // `onImage(file)` runs for each pasted picture; the panel uploads it, then calls addImage.
    function open(target, onQueue, onImage, onClose) {
        close();
        closing = onClose || null;
        host = document.createElement("div");
        host.setAttribute("data-showme-ui", "");
        const root = host.attachShadow({ mode: "closed" });
        root.innerHTML = "<style>" + CSS_TEXT + '</style><div class="box"><p class="where"></p>' +
            '<textarea rows="3" aria-label="Note" placeholder="Add a note"></textarea><div class="pics"></div>' +
            '<div class="bar"><button type="button" class="pic" title="Attach image" aria-label="Attach image">' + PIC_ICON +
            '</button><input type="file" accept="image/png,image/jpeg,image/webp" multiple hidden><small></small>' +
            '<button type="button" class="no" title="Cancel (Esc)">Cancel</button>' +
            '<button type="button" class="go" title="Add (Enter). Add and send: Ctrl+Enter">Add</button></div></div>';
        area = root.querySelector("textarea");
        strip = root.querySelector(".pics");
        small = root.querySelector("small");
        root.querySelector(".where").textContent = target.label;
        const queue = (sendNow) => {
            const text = area.value.trim();
            const ids = pics;
            if (!text && !ids.length) return;
            close();
            onQueue(text, sendNow, ids);
        };
        root.querySelector(".no").onclick = close;
        root.querySelector(".go").onclick = () => queue(false);
        takeImages(root, onImage);
        area.onkeydown = (e) => {
            e.stopPropagation();
            if (e.key === "Escape") e.preventDefault(); // Esc must not also close the full-window view
            if (e.key === "Escape" && !area.value.trim() && !pics.length) return close();
            if (e.key !== "Enter" || e.shiftKey || e.isComposing) return;
            e.preventDefault();
            queue(e.ctrlKey || e.metaKey);
        };
        // One open full-window view covers the page, so the card must sit inside it.
        (target.within || document.documentElement).append(host);
        place(target.rect, !target.within);
        area.focus({ preventScroll: true });
    }

    function addImage(id, url) {
        if (!host || pics.length >= 4 || pics.includes(id)) return;
        pics.push(id);
        const img = document.createElement("img");
        img.src = url;
        img.alt = "Attached picture";
        strip.append(img);
    }

    // True while the card holds words or pictures. The caller must not replace it then.
    function busy() {
        if (host && !host.isConnected) close(); // its full-window view went away
        if (!area || (!area.value.trim() && !pics.length)) return false;
        const box = area.parentNode;
        box.classList.remove("nudge");
        void box.offsetWidth;
        box.classList.add("nudge");
        area.focus({ preventScroll: true });
        return true;
    }

    // Shows why one picture could not be added, inside the card where it was added.
    function fail(text) {
        if (!small) return;
        small.textContent = text;
        small.className = "err";
    }

    window.showmeCard = { open, close, busy, addImage, fail };
})();
