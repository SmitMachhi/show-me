// Added to the reviewed page by show-me. The note card: one small box that opens at the
// element the reviewer clicked, so they type where they point. It lives in its own
// shadow root, so page styles cannot reach it and its styles cannot leak out.
// Exposes window.showmeCard = { open(target, onQueue, onImage), close(), busy(), addImage() }.
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
        "small{flex:1;color:#6f6f6b;font-size:12px}" +
        "button{font:inherit;border:0;border-radius:8px;padding:6px 10px;cursor:pointer;background:none;color:#6f6f6b;" +
        "transition:scale .08s cubic-bezier(.22,1,.36,1),background-color .08s}" +
        "button:hover{background:#0000000f}button:active{scale:.96}" +
        "button.go{background:#3657d6;color:#fff}button.go:hover{background:#2f4cc0}" +
        ".pics{display:flex;gap:6px;padding:0 6px}.pics:empty{display:none}.pics img{width:40px;height:40px;object-fit:cover;border-radius:8px}" +
        "@media(prefers-color-scheme:dark){.box{background:#1f1f1f;color:#ededeb;" +
        "box-shadow:0 0 0 1px #ffffff26,0 12px 32px #00000080}.where,small,button{color:#9b9b96}" +
        "button:hover{background:#ffffff14}button.go{background:#8ea2ff;color:#10142b}}" +
        "@media(prefers-reduced-motion:reduce){.box,.box.nudge{animation:none}}";

    let host = null;
    let area = null;
    let pics = [];
    let strip = null;

    function close() {
        if (host) host.remove();
        host = null;
        area = null;
        pics = [];
    }

    // Places the card under the target, or above it when there is no room below.
    // `scrolls` is false inside one full-window view, which does not move with the page.
    function place(rect, scrolls) {
        const top = rect.bottom + 8 + 150 > innerHeight && rect.top > 170 ? rect.top - 150 : rect.bottom + 8;
        host.style.top = (scrolls ? scrollY : 0) + top + "px";
        host.style.left = (scrolls ? scrollX : 0) + Math.max(8, Math.min(rect.left, innerWidth - 308)) + "px";
    }

    // `onQueue(words, sendNow, pictureIds)` runs when the reviewer queues the note.
    // `onImage(file)` runs for each pasted picture; the panel uploads it, then calls addImage.
    function open(target, onQueue, onImage) {
        close();
        host = document.createElement("div");
        host.setAttribute("data-showme-ui", "");
        const root = host.attachShadow({ mode: "closed" });
        root.innerHTML = "<style>" + CSS_TEXT + '</style><div class="box"><p class="where"></p>' +
            '<textarea rows="3" aria-label="Note" placeholder="Add a note"></textarea><div class="pics"></div>' +
            '<div class="bar"><small></small><button type="button">Cancel</button>' +
            '<button type="button" class="go">Add</button></div></div>';
        area = root.querySelector("textarea");
        strip = root.querySelector(".pics");
        root.querySelector(".where").textContent = target.label;
        const queue = (sendNow) => {
            const text = area.value.trim();
            const ids = pics;
            if (!text && !ids.length) return;
            close();
            onQueue(text, sendNow, ids);
        };
        root.querySelector("button").onclick = close;
        root.querySelector(".go").onclick = () => queue(false);
        area.onpaste = (e) => {
            const files = [...e.clipboardData.files].filter((f) => f.type.startsWith("image/"));
            if (!files.length) return;
            e.preventDefault();
            files.forEach(onImage);
        };
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
        if (!host || pics.length >= 4) return;
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

    window.showmeCard = { open, close, busy, addImage };
})();
