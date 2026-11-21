// Pictures on notes: upload, small previews, and the composer's attach, sketch, paste and drop.
// A picture is sent to the daemon at once and the note then carries only its id.
// Each composer picture is one chip in exactly one state:
//   "uploading": sent to the daemon, no answer yet. Send waits.
//   "failed":    refused or lost. Retry or remove it; Send waits.
//   "ready":     the daemon has it, under `id`.
import { initSketch } from "/ui-sketch.js";

const el = (id) => document.getElementById(id);
const MAX_PER_NOTE = 4;

// The composer's chips. createImages fills in the key and the change callback.
const box = { key: "", onChange: () => {}, chips: [] };

// Resolves to { id } or to { error } with the reason in words.
async function upload(blob) {
    const r = await fetch("/image/" + box.key, { method: "POST", body: blob }).catch(() => null);
    if (r && r.ok) return { id: await r.text() };
    return { error: !r ? "show-me isn't running." : r.status === 413 ? "It's over 10 MB." : "Use PNG, JPEG or WebP." };
}

const url = (id) => "/image/" + box.key + "/" + id;

async function send(chip) {
    chip.state = "uploading";
    draw();
    const r = await upload(chip.file);
    Object.assign(chip, r.id ? { state: "ready", id: r.id } : { state: "failed", error: r.error });
    draw();
}

function add(files) {
    for (const file of files) {
        if (!file.type.startsWith("image/") || box.chips.length >= MAX_PER_NOTE) continue;
        const chip = { state: "uploading", file, src: URL.createObjectURL(file) };
        box.chips.push(chip);
        send(chip);
    }
    draw();
}

function remove(chip) {
    box.chips = box.chips.filter((c) => c !== chip);
    URL.revokeObjectURL(chip.src);
    draw();
}

function draw() {
    el("thumbs").replaceChildren(...box.chips.map((c) => thumb(c.src, () => remove(c), c, () => send(c))));
    box.onChange();
}

// Hands over the ids of the composer's pictures and clears them.
function take() {
    const ids = box.chips.map((c) => c.id);
    box.chips.forEach((c) => URL.revokeObjectURL(c.src));
    box.chips = [];
    draw();
    return ids;
}

function listen() {
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
}

export function createImages(key, onChange) {
    Object.assign(box, { key, onChange });
    listen();
    return {
        upload,
        url,
        take,
        count: () => box.chips.length,
        // True when every chip is ready, so the message can go.
        ready: () => box.chips.every((c) => c.state === "ready"),
    };
}

function button(cls, label, text, onclick) {
    const b = document.createElement("button");
    b.type = "button";
    b.className = cls;
    b.title = label;
    b.setAttribute("aria-label", label);
    b.textContent = text;
    b.onclick = (e) => { e.stopPropagation(); onclick(); };
    return b;
}

// One small preview. With `onRemove` it gets a remove button. `chip` gives its upload
// state and, when that failed, one button that calls `onRetry`. A picture the daemon no longer has
// (pictures expire after 7 days) shows "Expired".
export function thumb(src, onRemove, chip, onRetry) {
    const box = document.createElement("span");
    const img = document.createElement("img");
    box.className = "thumb" + (chip ? " " + chip.state : "");
    img.src = src;
    img.alt = "Attached picture";
    img.onerror = () => {
        box.classList.add("gone");
        box.title = "Image expired";
        img.replaceWith(Object.assign(document.createElement("span"), { textContent: "Expired" }));
    };
    box.append(img);
    if (chip && chip.state === "failed") {
        box.title = "Couldn't add the image. " + chip.error;
        box.append(button("retry", "Retry", "↻", onRetry));
    }
    if (onRemove) box.append(button("plain", "Remove", "×", onRemove));
    return box;
}

// Sent notes carry file paths. The file name at the end of each is the picture id.
export function idOf(pathOrId) {
    return pathOrId.split(/[\\/]/).pop();
}
