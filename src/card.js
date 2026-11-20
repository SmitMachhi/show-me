// Added to the reviewed page by show-me. The note card: one small box that opens at the
// element the reviewer clicked, so they type where they point. It lives in its own
// shadow root, so page styles cannot reach it and its styles cannot leak out.
// Exposes window.showmeCard = { open(target, onQueue), close(), busy() }.
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
        "@media(prefers-color-scheme:dark){.box{background:#1f1f1f;color:#ededeb;" +
        "box-shadow:0 0 0 1px #ffffff26,0 12px 32px #00000080}.where,small,button{color:#9b9b96}" +
        "button:hover{background:#ffffff14}button.go{background:#8ea2ff;color:#10142b}}" +
        "@media(prefers-reduced-motion:reduce){.box,.box.nudge{animation:none}}";

    let host = null;
    let area = null;

    function close() {
        if (host) host.remove();
        host = null;
        area = null;
    }

    // Places the card under the target, or above it when there is no room below.
    function place(rect) {
        const top = rect.bottom + 8 + 150 > innerHeight && rect.top > 170 ? rect.top - 150 : rect.bottom + 8;
        host.style.top = scrollY + top + "px";
        host.style.left = scrollX + Math.max(8, Math.min(rect.left, innerWidth - 308)) + "px";
    }

    function open(target, onQueue) {
        close();
        host = document.createElement("div");
        host.setAttribute("data-showme-ui", "");
        const root = host.attachShadow({ mode: "closed" });
        root.innerHTML = "<style>" + CSS_TEXT + '</style><div class="box"><p class="where"></p>' +
            '<textarea rows="3" aria-label="Note" placeholder="Write one note"></textarea>' +
            '<div class="bar"><small>Enter queues</small><button type="button">Cancel</button>' +
            '<button type="button" class="go">Queue</button></div></div>';
        area = root.querySelector("textarea");
        root.querySelector(".where").textContent = target.label;
        const queue = (sendNow) => {
            const text = area.value.trim();
            if (!text) return;
            close();
            onQueue(text, sendNow);
        };
        root.querySelector("button").onclick = close;
        root.querySelector(".go").onclick = () => queue(false);
        area.onkeydown = (e) => {
            e.stopPropagation();
            if (e.key === "Escape" && !area.value.trim()) close();
            if (e.key !== "Enter" || e.shiftKey || e.isComposing) return;
            e.preventDefault();
            queue(e.ctrlKey || e.metaKey);
        };
        document.documentElement.append(host);
        place(target.rect);
        area.focus({ preventScroll: true });
    }

    // True while the card holds words. The caller must not replace it then.
    function busy() {
        if (!area || !area.value.trim()) return false;
        const box = area.parentNode;
        box.classList.remove("nudge");
        void box.offsetWidth;
        box.classList.add("nudge");
        area.focus({ preventScroll: true });
        return true;
    }

    window.showmeCard = { open, close, busy };
})();
