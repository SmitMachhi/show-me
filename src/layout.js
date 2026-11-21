// Added to the reviewed page by show-me. Finds layout problems the reviewer would
// otherwise have to describe, from what the browser drew:
// - wider than the page: one block makes the page scroll sideways
// - text is cut off: one box hides part of its own text
// - control is cut off: one box that clips hides part of one button or field
// - control or text is off the page: part of it sits left of or above the page edge,
//   where nobody can scroll
// - text is covered: one opaque box from elsewhere in the page sits on top of the words
// It only reports to the panel. Nothing reaches the agent unless the reviewer asks.
// Left alone on purpose: ellipsis and line clamp, scroll areas, one-pixel boxes for
// screen readers, hidden elements, and elements moved far off the page (skip links).
// Sticky and fixed bars that cover text while the page scrolls are left alone too.
// Limits: it checks the width the page has now, and only text that is on screen for
// "covered".
(function () {
    const MAX = 20;
    const CONTROL = "button,input,select,textarea,[role=button],[role=checkbox],[role=switch],[role=tab]";
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

    // One box that is hidden, or one pixel wide for screen readers.
    function invisible(el, r) {
        return r.width <= 2 || r.height <= 2 || getComputedStyle(el).visibility === "hidden";
    }

    function isCut(el) {
        if (el.scrollWidth <= el.clientWidth + 1 && el.scrollHeight <= el.clientHeight + 1) return false;
        const s = getComputedStyle(el);
        const wide = s.overflowX === "hidden" && el.scrollWidth > el.clientWidth + 1;
        const tall = s.overflowY === "hidden" && el.scrollHeight > el.clientHeight + 1;
        const onPurpose = s.textOverflow === "ellipsis" || (s.webkitLineClamp && s.webkitLineClamp !== "none");
        return (wide || tall) && !onPurpose && hasOwnText(el) && !invisible(el, el.getBoundingClientRect());
    }

    // The nearest ancestor that clips without scrolling, when it hides part of `r`.
    function clippedBy(el, r) {
        for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) {
            const s = getComputedStyle(p);
            if (s.overflowX === "visible" && s.overflowY === "visible") continue;
            if (/auto|scroll/.test(s.overflowX + s.overflowY)) return null;
            const b = p.getBoundingClientRect();
            const out = r.left < b.left - 2 || r.top < b.top - 2 || r.right > b.right + 2 || r.bottom > b.bottom + 2;
            return out ? p : null;
        }
        return null;
    }

    // Part of `r` is left of or above the page, and part is on it. Fully off the page
    // (more than 300 px away) is one way to hide on purpose.
    function partlyOff(r) {
        const left = r.left + scrollX;
        const top = r.top + scrollY;
        return (left < -2 && r.right + scrollX > 0 && left > -300) || (top < -2 && r.bottom + scrollY > 0 && top > -300);
    }

    // One opaque element that is not part of `el` and is not one sticky or fixed bar
    // sits on the middle of el's words. Clear layers do not count: the words show.
    function coveredBy(el, r) {
        if (r.bottom < 0 || r.top > innerHeight || r.right < 0 || r.left > innerWidth || !hasOwnText(el)) return null;
        const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
        if (!hit || el.contains(hit) || hit.contains(el) || skip(hit)) return null;
        for (let p = hit; p && p !== document.body; p = p.parentElement) {
            if (/sticky|fixed/.test(getComputedStyle(p).position)) return null;
        }
        const bg = getComputedStyle(hit).backgroundColor.match(/[\d.]+/g) || [];
        const opaque = bg.length === 3 || (bg.length === 4 && Number(bg[3]) > 0.9);
        return opaque || hasOwnText(hit) ? hit : null;
    }

    function findings() {
        const found = [];
        const add = (el, problem) => found.push({ el, problem });
        const all = [...document.body.querySelectorAll("*")].filter((el) => !skip(el));
        if (doc.scrollWidth > doc.clientWidth + 1) {
            for (const el of all) {
                const r = el.getBoundingClientRect();
                const sticksOut = r.width > 0 && r.right > doc.clientWidth + 1;
                // Report the outermost culprit only. What is inside it follows from it.
                if (sticksOut && !found.some((f) => f.el.contains(el)) && !inScroller(el)) add(el, "wider than the page");
            }
        }
        for (const el of all) {
            const r = el.getBoundingClientRect();
            const control = el.matches(CONTROL);
            if (invisible(el, r)) continue;
            if (isCut(el)) add(el, "text is cut off");
            else if (control && clippedBy(el, r)) add(el, "control is cut off");
            else if (partlyOff(r) && (control || hasOwnText(el))) add(el, control ? "control is off the page" : "text is off the page");
            else if (coveredBy(el, r)) add(el, "text is covered");
        }
        return found;
    }

    function check() {
        const t0 = performance.now();
        const issues = findings().slice(0, MAX).map((f) => ({
            selector: window.showmeSelector(f.el),
            text: f.el.textContent.replace(/\s+/g, " ").trim().slice(0, 60),
            problem: f.problem,
        }));
        window.showmeLayout.last = issues;
        window.showmeLayout.ms = performance.now() - t0;
        parent.postMessage({ source: "showme", type: "layout", issues }, "*");
    }

    window.showmeLayout = { last: [] };
    // Wait for fonts: text measured in the fallback font gives false alarms.
    const fonts = document.fonts ? document.fonts.ready : Promise.resolve();
    fonts.then(() => setTimeout(check, 200));
    let timer = 0;
    addEventListener("resize", () => {
        clearTimeout(timer);
        timer = setTimeout(check, 300);
    });
})();
