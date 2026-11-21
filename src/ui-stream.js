// The live link to the daemon: one event stream per review. It says when the page file
// changed, when the log grew, and what the agent is doing. When the daemon goes away,
// the panel says so. When it comes back it may be a newer build, so the panel reloads.
const el = (id) => document.getElementById(id);
const AGENT = { nobody: "Agent offline", listening: "Agent online", working: "Agent busy" };

// `on` has reload(), log() and banner(text).
export function connect(key, on) {
    const stream = new EventSource("/events/" + key);
    let lost = null;
    stream.onerror = () => {
        lost = lost || setTimeout(() => on.banner("show-me isn't running. Run show-me open again."), 3000);
    };
    stream.onopen = () => {
        if (lost) location.reload();
    };
    stream.onmessage = (e) => {
        if (e.data === "reload") on.reload();
        if (e.data === "log") on.log();
        if (!e.data.startsWith("presence ")) return;
        el("agent").dataset.state = e.data.slice(9);
        el("agent").lastElementChild.textContent = AGENT[e.data.slice(9)] || "";
    };
}
