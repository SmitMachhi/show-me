// The sketch pad: one blank full-window sheet to draw on. The drawing code is draw.js,
// the same code that draws on diagrams. The finished picture goes to `onPicture(blob)`.
const button = (label, icon) =>
    '<button type="button" class="tool" title="' + label + '" aria-label="' + label + '"><svg class="icon"><use href="#i-' + icon + '"/></svg></button>';

export function initSketch(opener, onPicture) {
    opener.onclick = () => open(onPicture);
}

function open(onPicture) {
    const pad = document.createElement("dialog");
    pad.id = "sketch";
    // The sheet has the size of the window, so no stroke lands outside the picture.
    pad.innerHTML = '<svg viewBox="0 0 ' + innerWidth + " " + innerHeight + '"></svg><nav>' +
        button("Undo", "undo") + button("Add to message", "check") + button("Close", "x") + "</nav>";
    const [undo, add, close] = pad.querySelectorAll("button");
    const ink = window.showmeDraw.attach(pad.firstChild, () => true, () => {
        undo.disabled = add.disabled = ink.count() === 0;
    });
    const shut = () => {
        if (ink.count() === 0 || confirm("Discard the drawing?")) pad.remove();
    };
    undo.onclick = ink.undo;
    undo.disabled = add.disabled = true;
    close.onclick = shut;
    pad.oncancel = (e) => { e.preventDefault(); shut(); }; // Esc
    add.onclick = () => ink.png(true).then((blob) => {
        pad.remove();
        onPicture(blob);
    }, () => alert("Couldn't add the drawing."));
    document.body.append(pad);
    pad.showModal();
}
