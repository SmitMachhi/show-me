// Added to the reviewed page by show-me. Finds layout problems the reviewer would
// otherwise have to describe: content wider than the page, and text that is cut off.
// It only reports to the panel. Nothing is fixed, and nothing reaches the agent unless
// the reviewer asks for it.
// Limits: it checks the width the page has now, and it does not look for elements that
// overlap. Text cut on purpose (ellipsis, line clamp) and scroll areas are left alone.
(function () {
    const MAX = 20;
    const doc = document.documentElement;

    function skip(el) {
        return el.closest("[data-showme-ui],svg,dialog,script,style,template") !== null;
    }

    // True when one ancestor scrolls or clips sideways, so the overflow is on purpose.
    function inScroller(el) {
        for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) {
            if (getComputedStyle(p).overflowX !== "visible") return true;
        }
        return false;
    }

    function hasOwnText(el) {
        return [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim());
    }

    function isCut(el) {
        if (el.scrollWidth <= el.clientWidth + 1 && el.scrollHeight <= el.clientHeight + 1) return false;
        const s = getComputedStyle(el);
        const wide = s.overflowX === "hidden" && el.scrollWidth > el.clientWidth + 1;
        const tall = s.overflowY === "hidden" && el.scrollHeight > el.clientHeight + 1;
        const onPurpose = s.textOverflow === "ellipsis" || (s.webkitLineClamp && s.webkitLineClamp !== "none");
        return (wide || tall) && !onPurpose && hasOwnText(el);
    }

    function check() {
        const found = [];
        const all = [...document.body.querySelectorAll("*")].filter((el) => !skip(el));
        if (doc.scrollWidth > doc.clientWidth + 1) {
            for (const el of all) {
                const r = el.getBoundingClientRect();
                const sticksOut = r.width > 0 && r.right > doc.clientWidth + 1;
                // Report the outermost culprit only. What is inside it follows from it.
                if (sticksOut && !found.some((f) => f.el.contains(el)) && !inScroller(el)) {
                    found.push({ el, problem: "wider than the page" });
                }
            }
        }
        for (const el of all) {
            if (isCut(el)) found.push({ el, problem: "text is cut off" });
        }
        parent.postMessage({
            source: "showme",
            type: "layout",
            issues: found.slice(0, MAX).map((f) => ({
                selector: window.showmeSelector(f.el),
                text: f.el.textContent.replace(/\s+/g, " ").trim().slice(0, 60),
                problem: f.problem,
            })),
        }, "*");
    }

    // Wait for fonts: text measured in the fallback font gives false alarms.
    const fonts = document.fonts ? document.fonts.ready : Promise.resolve();
    fonts.then(() => setTimeout(check, 200));
    let timer = 0;
    addEventListener("resize", () => {
        clearTimeout(timer);
        timer = setTimeout(check, 300);
    });
})();
