// Tells the reviewer when the same review is open in more than one tab of this browser.
// Unsent notes live in the tab where they were written, so two tabs can hold two
// different queues. The panels talk over one BroadcastChannel: instant, no daemon.
// Limit: two different browsers do not see each other.
export function watchTabs(key) {
    if (!window.BroadcastChannel) return;
    const notice = document.getElementById("tabs");
    const me = Math.random().toString(36).slice(2);
    const others = new Set();
    const channel = new BroadcastChannel("showme:tabs:" + key);

    function show() {
        notice.hidden = others.size === 0;
        const more = others.size === 1 ? "one more tab" : others.size + " more tabs";
        notice.textContent = "This review is open in " + more + ". Unsent notes stay in the tab where you wrote them.";
    }

    channel.onmessage = (e) => {
        const { say, tab } = e.data || {};
        if (!tab || tab === me) return;
        if (say === "hello") channel.postMessage({ say: "here", tab: me });
        if (say === "hello" || say === "here") others.add(tab);
        if (say === "bye") others.delete(tab);
        show();
    };
    addEventListener("pagehide", () => channel.postMessage({ say: "bye", tab: me }));
    channel.postMessage({ say: "hello", tab: me });
}
