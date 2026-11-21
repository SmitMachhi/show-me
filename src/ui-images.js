// Pictures on notes: upload, small previews, and the composer's attach, sketch, paste and drop.
// A picture is sent to the daemon at once and the note then carries only its id.
import { initSketch } from "/ui-sketch.js";

const el = (id) => document.getElementById(id);
const MAX_PER_NOTE = 4;

export function createImages(key, onChange) {
    let pending = [];

    // Returns the picture id, or null with the reason shown to the reviewer.
    async function upload(blob) {
        const r = await fetch("/image/" + key, { method: "POST", body: blob }).catch(() => null);
        if (r && r.ok) return r.text();
        const why = !r ? "show-me isn't running." : r.status === 413 ? "It's over 10 MB." : "Use PNG, JPEG or WebP.";
        el("banner").textContent = "Couldn't add the image. " + why;
        el("banner").hidden = false;
        return null;
    }

    function url(id) {
        return "/image/" + key + "/" + id;
    }

    async function add(files) {
        for (const file of files) {
            if (!file.type.startsWith("image/") || pending.length >= MAX_PER_NOTE) continue;
            const id = await upload(file);
            if (id) pending.push(id);
        }
        draw();
        onChange();
    }

    function draw() {
        el("thumbs").replaceChildren(...pending.map((id, i) => thumb(url(id), () => {
            pending.splice(i, 1);
            draw();
            onChange();
        })));
    }

    el("attach").onclick = () => el("file").click();
    initSketch(el("sketch"), (blob) => add([blob]));
    el("file").onchange = () => { add([...el("file").files]); el("file").value = ""; };
    el("note").addEventListener("paste", (e) => {
        const files = [...e.clipboardData.files];
        if (files.length) { e.preventDefault(); add(files); }
    });
    el("form").addEventListener("dragover", (e) => e.preventDefault());
    el("form").addEventListener("drop", (e) => { e.preventDefault(); add([...e.dataTransfer.files]); });
    // One file dropped outside the composer must not replace the review page.
    const files = (e) => e.dataTransfer && e.dataTransfer.types.includes("Files");
    addEventListener("dragover", (e) => { if (files(e)) e.preventDefault(); });
    addEventListener("drop", (e) => { if (files(e)) e.preventDefault(); });

    return {
        upload,
        url,
        count: () => pending.length,
        // Hands over the composer's pictures and clears them.
        take() {
            const ids = pending;
            pending = [];
            draw();
            return ids;
        },
    };
}

// One small preview. With `onRemove` it gets a remove button.
export function thumb(src, onRemove) {
    const box = document.createElement("span");
    const img = document.createElement("img");
    box.className = "thumb";
    img.src = src;
    img.alt = "Attached picture";
    box.append(img);
    if (onRemove) {
        const b = document.createElement("button");
        b.type = "button";
        b.className = "plain";
        b.setAttribute("aria-label", "Remove");
        b.textContent = "×";
        b.onclick = (e) => { e.stopPropagation(); onRemove(); };
        box.append(b);
    }
    return box;
}

// Sent notes carry file paths. The file name at the end of each is the picture id.
export function idOf(pathOrId) {
    return pathOrId.split(/[\\/]/).pop();
}
