// Added to the reviewed page by show-me. Gives each diagram one full-window view with
// zoom and pan. Zoom and pan only change the SVG viewBox, so the picture stays sharp.
(function () {
    const ICONS = {
        expand: "M8 3H5a2 2 0 0 0-2 2v3M16 3h3a2 2 0 0 1 2 2v3M8 21H5a2 2 0 0 1-2-2v-3M16 21h3a2 2 0 0 0 2-2v-3",
        close: "M18 6 6 18M6 6l12 12",
        plus: "M12 5v14M5 12h14",
        minus: "M5 12h14",
        fit: "M4 9V5h4M20 9V5h-4M4 15v4h4M20 15v4h-4",
    };
    const CSS_TEXT =
        ".showme-graph{position:relative;margin:0}.showme-graph svg{max-width:100%;height:auto;display:block}" +
        ".showme-btn{display:grid;place-items:center;width:32px;height:32px;padding:0;border:0;border-radius:8px;" +
        "background:#fff;color:#333;cursor:pointer;box-shadow:0 0 0 1px #0000001a,0 2px 6px #0000001a;" +
        "transition:scale .08s cubic-bezier(.22,1,.36,1),opacity .08s cubic-bezier(.22,1,.36,1),background-color .08s}" +
        ".showme-btn:hover{background:#f3f4f6}.showme-btn:active{scale:.96}" +
        ".showme-btn svg{width:16px;height:16px;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}" +
        ".showme-graph>.showme-btn{position:absolute;top:8px;right:8px;opacity:0}" +
        ".showme-graph:hover>.showme-btn,.showme-btn:focus-visible{opacity:1}" +
        "@media(hover:none){.showme-graph>.showme-btn{opacity:1}}" +
        "dialog.showme-full{width:100vw;height:100vh;max-width:none;max-height:none;margin:0;border:0;padding:0;background:#fff}" +
        "dialog.showme-full[open]{animation:showme-in .09s cubic-bezier(.22,1,.36,1)}" +
        "@keyframes showme-in{from{opacity:0;scale:.985}}" +
        "dialog.showme-full.leaving{opacity:0;scale:.985;transition:opacity .07s cubic-bezier(.22,1,.36,1),scale .07s cubic-bezier(.22,1,.36,1)}" +
        "dialog.showme-full svg{width:100%;height:100%;cursor:grab;touch-action:none}" +
        "dialog.showme-full nav{position:absolute;top:12px;right:12px;display:flex;gap:6px}" +
        "@media(prefers-reduced-motion:reduce){dialog.showme-full[open]{animation:none}.showme-btn{transition:none}}";

    function button(name, label, onclick) {
        const b = document.createElement("button");
        b.className = "showme-btn";
        b.setAttribute("aria-label", label);
        b.title = label;
        b.innerHTML = '<svg viewBox="0 0 24 24"><path d="' + ICONS[name] + '"/></svg>';
        b.onclick = onclick;
        return b;
    }

    // Returns { zoom(k), fit() } for one SVG. k below 1 zooms in.
    function panZoom(svg) {
        const home = svg.getAttribute("viewBox").split(/[ ,]+/).map(Number);
        let [x, y, w, h] = home;
        let from = null;
        const set = () => svg.setAttribute("viewBox", [x, y, w, h].join(" "));
        const zoom = (k, fx, fy) => {
            x += fx * w * (1 - k);
            y += fy * h * (1 - k);
            w *= k;
            h *= k;
            set();
        };
        svg.addEventListener("wheel", (e) => {
            e.preventDefault();
            const r = svg.getBoundingClientRect();
            zoom(e.deltaY < 0 ? 0.85 : 1.18, (e.clientX - r.left) / r.width, (e.clientY - r.top) / r.height);
        }, { passive: false });
        svg.addEventListener("pointerdown", (e) => { from = { cx: e.clientX, cy: e.clientY, x, y }; });
        svg.addEventListener("pointermove", (e) => {
            if (!from) return;
            const r = svg.getBoundingClientRect();
            if (Math.abs(e.clientX - from.cx) + Math.abs(e.clientY - from.cy) > 4) window.showmeDragged = true;
            x = from.x - ((e.clientX - from.cx) / r.width) * w;
            y = from.y - ((e.clientY - from.cy) / r.height) * h;
            set();
        });
        addEventListener("pointerup", () => { from = null; });
        // Button presses glide to the new view in 90 ms so you keep your place.
        // Wheel and drag stay instant: they must follow the hand.
        const glide = (to) => {
            const start = [x, y, w, h];
            const t0 = performance.now();
            const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
            const step = (now) => {
                const p = still ? 1 : Math.min(1, (now - t0) / 90);
                const k = 1 - Math.pow(1 - p, 3);
                [x, y, w, h] = start.map((v, i) => v + (to[i] - v) * k);
                set();
                if (p < 1) requestAnimationFrame(step);
            };
            requestAnimationFrame(step);
        };
        return {
            zoom: (k) => glide([x + 0.5 * w * (1 - k), y + 0.5 * h * (1 - k), w * k, h * k]),
            fit: () => glide(home),
        };
    }

    function expand(svg) {
        const full = document.createElement("dialog");
        const nav = document.createElement("nav");
        const copy = svg.cloneNode(true);
        full.className = "showme-full";
        copy.removeAttribute("width");
        copy.removeAttribute("height");
        full.append(copy, nav);
        // Leaves the way it came, a little faster.
        const shut = () => {
            full.classList.add("leaving");
            setTimeout(() => full.remove(), 70);
        };
        full.oncancel = (e) => { e.preventDefault(); shut(); }; // Esc
        document.body.append(full);
        full.showModal();
        const view = panZoom(copy);
        nav.append(
            button("plus", "Zoom in", () => view.zoom(0.8)),
            button("minus", "Zoom out", () => view.zoom(1.25)),
            button("fit", "Fit", view.fit),
            button("close", "Close", shut),
        );
    }

    const style = document.createElement("style");
    style.textContent = CSS_TEXT;
    document.head.appendChild(style);
    for (const svg of document.querySelectorAll("figure.showme-graph > svg")) {
        svg.after(button("expand", "Expand", () => expand(svg)));
    }
})();
