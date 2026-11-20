// Added to the reviewed page by show-me. Lets the reviewer draw on one SVG with the
// pointer, then turns the SVG and the strokes into one PNG. Strokes are SVG paths in
// viewBox units, so they follow zoom and pan.
// Exposes window.showmeDraw.attach(svg, active, onChange) -> { undo, count, summary, png }.
// The review panel loads this file too, for its sketch pad.
(function () {
    const NS = "http://www.w3.org/2000/svg";
    const MAX_EDGE = 1200; // longest PNG side in pixels: enough to read, cheap to send

    function nameOf(part) {
        const title = part && part.querySelector("title");
        return title ? title.textContent : "";
    }

    // Names of the nodes whose centre lies inside the box one stroke covers.
    function nodesInside(svg, box) {
        const names = [];
        for (const node of svg.querySelectorAll("g.node")) {
            const r = node.getBoundingClientRect();
            const [x, y] = [r.left + r.width / 2, r.top + r.height / 2];
            if (x > box.x0 && x < box.x1 && y > box.y0 && y < box.y1) names.push(nameOf(node));
        }
        return names;
    }

    // The layer that holds the strokes. The pointer passes through it to the nodes below.
    function inkLayer() {
        const ink = document.createElementNS(NS, "g");
        for (const [k, v] of [["pointer-events", "none"], ["fill", "none"], ["stroke", "#e5484d"], ["stroke-width", "3"],
            ["stroke-linecap", "round"], ["stroke-linejoin", "round"]]) ink.setAttribute(k, v);
        return ink;
    }

    // Where the pointer is, in the SVG's own units.
    function at(svg, e) {
        const p = new DOMPoint(e.clientX, e.clientY).matrixTransform(svg.getScreenCTM().inverse());
        return p.x.toFixed(1) + " " + p.y.toFixed(1);
    }

    // Adds the pointer position to one stroke and notes the node under it.
    function extend(svg, line, e) {
        const hit = document.elementFromPoint(e.clientX, e.clientY);
        const name = nameOf(hit && hit.closest("g.node"));
        if (name && line.touched[line.touched.length - 1] !== name) line.touched.push(name);
        line.box = {
            x0: Math.min(line.box.x0, e.clientX), x1: Math.max(line.box.x1, e.clientX),
            y0: Math.min(line.box.y0, e.clientY), y1: Math.max(line.box.y1, e.clientY),
        };
        line.d += "L" + at(svg, e);
        line.path.setAttribute("d", line.d);
    }

    // `active()` says if the pointer draws now. `onChange()` runs when the stroke count changes.
    function attach(svg, active, onChange) {
        const home = svg.getAttribute("viewBox");
        const ink = inkLayer();
        const strokes = []; // each: { path, touched: [names], inside: [names] }
        let line = null; // the stroke under the pointer, or null between strokes
        svg.append(ink);
        const finish = () => {
            if (!line) return;
            strokes.push({ path: line.path, touched: line.touched, inside: nodesInside(svg, line.box) });
            line = null;
            onChange();
        };
        svg.addEventListener("pointerdown", (e) => {
            if (!active()) return;
            window.showmeDragged = true; // so the click that follows does not pick one element
            svg.setPointerCapture(e.pointerId);
            const path = document.createElementNS(NS, "path");
            path.setAttribute("vector-effect", "non-scaling-stroke");
            ink.append(path);
            line = { path, d: "M" + at(svg, e), touched: [], box: { x0: e.clientX, x1: e.clientX, y0: e.clientY, y1: e.clientY } };
            extend(svg, line, e);
        });
        svg.addEventListener("pointermove", (e) => { if (line) extend(svg, line, e); });
        svg.addEventListener("pointerup", finish);
        svg.addEventListener("pointercancel", finish);

        return {
            count: () => strokes.length,
            undo() {
                const last = strokes.pop();
                if (last) last.path.remove();
                onChange();
            },
            summary: () => describe(strokes),
            // `onlyInk` cuts the picture down to the strokes: for one blank sheet.
            png: (onlyInk) => toPng(svg, onlyInk ? around(ink.getBBox()) : home),
        };
    }

    // The view box that holds one box with some room around it.
    function around(box) {
        return [box.x - 24, box.y - 24, box.width + 48, box.height + 48].join(" ");
    }

    // Says in words what the strokes point at, so the agent can often act without the picture.
    function describe(strokes) {
        const on = new Set();
        const lines = [];
        for (const s of strokes) {
            [...s.touched, ...s.inside].forEach((n) => on.add(n));
            const [from, to] = [s.touched[0], s.touched[s.touched.length - 1]];
            if (from && to && from !== to) lines.push(from + " -> " + to);
        }
        return "Drawing" + (on.size ? " on " + [...on].join(", ") : "") + (lines.length ? ". Lines: " + lines.join("; ") : "");
    }

    // Resolves to one PNG blob of the view box `view` on white, whatever the zoom is now.
    function toPng(svg, view) {
        const copy = svg.cloneNode(true);
        const [, , w, h] = view.split(/[ ,]+/).map(Number);
        const k = Math.min(2, MAX_EDGE / Math.max(w, h));
        copy.setAttribute("xmlns", NS);
        copy.setAttribute("viewBox", view);
        copy.setAttribute("width", Math.round(w * k));
        copy.setAttribute("height", Math.round(h * k));
        return new Promise((done, fail) => {
            const img = new Image();
            img.onload = () => {
                const canvas = document.createElement("canvas");
                [canvas.width, canvas.height] = [img.width, img.height];
                const g = canvas.getContext("2d");
                g.fillStyle = "#fff";
                g.fillRect(0, 0, canvas.width, canvas.height);
                g.drawImage(img, 0, 0);
                canvas.toBlob((blob) => (blob ? done(blob) : fail(new Error("no picture"))), "image/png");
            };
            img.onerror = () => fail(new Error("cannot draw the picture"));
            img.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(new XMLSerializer().serializeToString(copy));
        });
    }

    window.showmeDraw = { attach };
})();
