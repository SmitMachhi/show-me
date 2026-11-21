// Added to the reviewed page by show-me. Tells the panel the page's title and icon, at
// load and each time the page changes them, so the browser tab shows them. A page that
// sets document.title works the same with and without show-me.
(function () {
    let last = "";

    function report() {
        const link = document.querySelector("link[rel~='icon']");
        const meta = { type: "meta", title: document.title, icon: link ? link.href : "" };
        const text = JSON.stringify(meta);
        if (text === last) return;
        last = text;
        parent.postMessage(Object.assign({ source: "showme" }, meta), "*");
    }

    new MutationObserver(report).observe(document.head || document.documentElement,
        { childList: true, subtree: true, characterData: true, attributes: true });
    report();
})();
