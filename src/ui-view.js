// Builds the chat bubbles and renders agent replies. No state lives here.
import { thumb, idOf } from "/ui-images.js";

const SVG = "http://www.w3.org/2000/svg";
// Chat convention: one check is sent, two is seen, two in color is done.
const RECEIPT = { Sent: "check", Seen: "checks", Done: "checks" };

export function icon(name) {
    const svg = document.createElementNS(SVG, "svg");
    const use = document.createElementNS(SVG, "use");
    svg.setAttribute("class", "icon");
    use.setAttribute("href", "#i-" + name);
    svg.append(use);
    return svg;
}

function make(tag, cls, text) {
    const el = document.createElement(tag);
    if (cls) el.className = cls;
    if (text) el.textContent = text;
    return el;
}

// What the note points at, shown like a quoted message. A plain message has none.
function quote(n) {
    let name = "pointer";
    let text = n.text ? n.text.slice(0, 80) : n.selector;
    if (n.node) [name, text] = ["graph", n.node];
    else if (n.cell) [name, text] = ["table", [n.cell.row, n.cell.column].filter(Boolean).join(" / ")];
    else if (n.kind === "text") name = "text";
    else if (n.kind === "page") [name, text] = ["page", "Form answer"];
    else if (n.kind === "layout") [name, text] = ["panel", n.issues.length === 1 ? "1 layout issue" : n.issues.length + " layout issues"];
    else if (!n.selector) return null;
    const q = make("div", "quote");
    q.append(icon(name), make("span", "", text));
    return q;
}

// Inline marks: `code`, **bold**, *italic* and http links. Everything else is plain text.
function inline(text, into) {
    const parts = text.split(/(`[^`]+`|\*\*[^*]+\*\*|\*[^*\s][^*]*\*|https?:\/\/[^\s)]+)/g);
    for (const part of parts) {
        if (/^`.+`$/.test(part)) into.append(make("code", "", part.slice(1, -1)));
        else if (/^\*\*.+\*\*$/.test(part)) into.append(make("b", "", part.slice(2, -2)));
        else if (/^\*.+\*$/.test(part)) into.append(make("i", "", part.slice(1, -1)));
        else if (/^https?:\/\//.test(part)) {
            const a = make("a", "", part);
            a.href = part;
            a.target = "_blank";
            a.rel = "noreferrer";
            into.append(a);
        } else into.append(part);
    }
}

// A small Markdown subset for agent replies: paragraphs, lists, headings as bold
// lines, fenced code. Built as DOM nodes, so reply text can never become markup.
export function markdown(text) {
    const out = document.createDocumentFragment();
    text.split("```").forEach((chunk, i) => {
        if (i % 2) return out.append(make("pre", "", chunk.replace(/^\w*\n/, "").trimEnd()));
        let list = null;
        for (const raw of chunk.split("\n")) {
            const line = raw.trim();
            const item = /^(-|\d+\.)\s+(.*)$/.exec(line);
            if (!line) { list = null; continue; }
            if (item) {
                if (!list) out.append(list = make(item[1] === "-" ? "ul" : "ol"));
                inline(item[2], list.appendChild(make("li")));
                continue;
            }
            list = null;
            const head = /^#+\s+(.*)$/.exec(line);
            inline(head ? head[1] : line, out.appendChild(make("p", head ? "lead" : "")));
        }
    });
    return out;
}

// The words and pictures of one of the reviewer's notes.
function body(n, urlOf) {
    const parts = [];
    const q = quote(n);
    if (q) parts.push(q);
    if (n.note) parts.push(make("p", "", n.note));
    if (n.images && n.images.length) {
        const box = make("div", "thumbs");
        for (const p of n.images) box.append(thumb(urlOf(idOf(p))));
        parts.push(box);
    }
    return parts;
}

// `changed` is true when the receipt differs from the last render, so it animates once.
export function sentRow(s, changed, onReveal, urlOf) {
    if (s.agent) {
        const li = make("li", "agent md");
        li.append(markdown(s.text));
        return li;
    }
    if (s.note.kind === "end") return make("li", "system", "Review ended");
    const li = make("li", "me");
    const receipt = make("em", (s.state === "Done" ? "done" : "") + (changed ? " changed" : ""));
    receipt.title = s.state;
    receipt.append(icon(RECEIPT[s.state]));
    li.append(...body(s.note, urlOf), receipt);
    if (s.note.selector) li.onclick = () => onReveal(s.note.selector);
    return li;
}

// A note that is not sent yet. Click it to edit: Enter saves, Escape cancels, empty removes.
export function queuedRow(n, on) {
    const li = make("li", "me queued");
    const remove = make("button", "plain");
    remove.type = "button";
    remove.title = "Remove";
    remove.setAttribute("aria-label", "Remove");
    remove.append(icon("x"));
    li.append(...body(n, on.url), remove);
    remove.onclick = (e) => {
        e.stopPropagation();
        li.classList.add("leave");
        setTimeout(on.remove, 80);
    };
    li.onclick = () => {
        const words = li.querySelector("p");
        if (li.querySelector("textarea") || !words) return;
        if (n.selector) on.reveal(n.selector);
        const area = make("textarea");
        area.value = n.note;
        area.rows = 2;
        area.onkeydown = (e) => {
            if (e.key === "Escape") on.save(n.note);
            if (e.key !== "Enter" || e.shiftKey || e.isComposing) return;
            e.preventDefault();
            on.save(area.value.trim());
        };
        area.onblur = () => on.save(area.value.trim());
        words.replaceWith(area);
        area.focus();
    };
    return li;
}
