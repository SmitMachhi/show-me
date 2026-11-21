// Added to the reviewed page by show-me. Tells the panel the page's title and icon, at
// load and each time the page changes them, so the browser tab shows them. A page that
// sets document.title works the same with and without show-me.
// It also tells the page's canvas color: white, or dark for one page that asks for dark
// with color-scheme. The panel paints the frame with it, so the page looks the same in
// the review as in one browser tab of its own.
(function () {
    let last = "";

    function canvas() {
        const probe = document.createElement("div");
        probe.setAttribute("data-showme-ui", "");
        probe.style.cssText = "position:absolute;width:0;height:0;background:Canvas";
        document.documentElement.append(probe);
        const color = getComputedStyle(probe).backgroundColor;
        probe.remove();
        return color;
    }

    function report() {
        const link = document.querySelector("link[rel~='icon']");
        const meta = { type: "meta", title: document.title, icon: link ? link.href : "", canvas: canvas() };
        const text = JSON.stringify(meta);
        if (text === last) return;
        last = text;
        parent.postMessage(Object.assign({ source: "showme" }, meta), "*");
    }

    new MutationObserver(report).observe(document.head || document.documentElement,
        { childList: true, subtree: true, characterData: true, attributes: true });
    report();
})();
