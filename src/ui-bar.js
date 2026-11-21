// The top bar: annotate switch, panel toggle, and the menu. It reports what the
// reviewer chose through the `on` callbacks and keeps no review state itself.
const el = (id) => document.getElementById(id);

export function initBar(on) {
    const menu = el("menu");
    const more = el("more");
    let annotate = true;

    function openMenu(open) {
        menu.hidden = !open;
        more.setAttribute("aria-expanded", String(open));
    }

    function setMode(next) {
        annotate = next;
        el("mode").setAttribute("aria-checked", String(next));
    }

    // On one narrow screen the chat is a sheet over the page, closed until asked for.
    const narrow = matchMedia("(max-width: 760px)");

    function setPanel(open) {
        document.body.classList.toggle("collapsed", !open);
        el("toggle").setAttribute("aria-label", open ? "Hide chat" : "Show chat");
        el("toggle").title = open ? "Hide chat" : "Show chat";
        if (narrow.matches) return;
        try { localStorage.setItem("showme:panel", open ? "open" : "closed"); } catch (e) {}
    }

    el("mode").onclick = () => on.mode(!annotate);
    el("toggle").onclick = () => setPanel(document.body.classList.contains("collapsed"));
    more.onclick = () => openMenu(menu.hidden);
    el("copy").onclick = async () => {
        try { await navigator.clipboard.writeText(on.file()); } catch (e) { return; }
        const text = el("copy").lastChild;
        text.textContent = "Copied";
        setTimeout(() => { text.textContent = "Copy file path"; openMenu(false); }, 700);
    };
    el("reload").onclick = () => { openMenu(false); on.reload(); };
    el("export").onclick = () => { openMenu(false); on.download(); };
    el("end").onclick = () => { openMenu(false); on.end(); };

    addEventListener("mousedown", (e) => {
        if (!menu.hidden && !e.target.closest(".menu")) openMenu(false);
    });
    addEventListener("keydown", (e) => {
        if (e.key === "Escape") openMenu(false);
        if ((e.ctrlKey || e.metaKey) && !e.shiftKey && !e.altKey && e.key.toLowerCase() === "i") {
            e.preventDefault();
            on.mode(!annotate);
        }
    });

    let stored = "open";
    try { stored = localStorage.getItem("showme:panel") || "open"; } catch (e) {}
    setPanel(stored === "open" && !narrow.matches);
    // A tap on the dimmed page closes the sheet.
    el("page").parentNode.onclick = (e) => {
        if (narrow.matches && e.target === e.currentTarget) setPanel(false);
    };

    return {
        setMode,
        isAnnotate: () => annotate,
        // The badge shows on the toggle while the panel is hidden.
        setBadge(count, unseenReply) {
            el("badge").textContent = count ? String(count) : unseenReply ? "•" : "";
        },
        setTitle(title) {
            el("title").textContent = title;
            document.title = (title ? title + " · " : "") + "show-me";
        },
        // The page's title and icon for the browser tab. The icon comes from the page,
        // which is not trusted: only data:image/ and files of this review are used.
        setMeta(m) {
            this.setTitle(m.title || "");
            const ok = /^data:image\//.test(m.icon) || (m.icon || "").startsWith(location.origin + "/a/" + location.pathname.split("/").pop() + "/");
            let link = document.querySelector("link[rel=icon]");
            if (!ok) return link && link.remove();
            if (!link) document.head.append(link = Object.assign(document.createElement("link"), { rel: "icon" }));
            link.href = m.icon;
        },
        setEnded(ended) {
            document.body.classList.toggle("ended", ended);
            el("end").disabled = ended;
        },
    };
}
