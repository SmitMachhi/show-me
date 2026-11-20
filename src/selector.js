// Added to the reviewed page by show-me. One job: the CSS path of one element, short
// enough to read and exact enough for the agent to find that element in its file.
// Stops at the nearest id. Exposes window.showmeSelector(el).
(function () {
    window.showmeSelector = function (el) {
        const parts = [];
        while (el && el.nodeType === 1 && el !== document.documentElement) {
            let part = el.tagName.toLowerCase();
            if (el.id) {
                parts.unshift(part + "#" + CSS.escape(el.id));
                break;
            }
            const twins = [...el.parentNode.children].filter((c) => c.tagName === el.tagName);
            if (twins.length > 1) part += ":nth-of-type(" + (twins.indexOf(el) + 1) + ")";
            parts.unshift(part);
            el = el.parentNode;
        }
        return parts.join(" > ");
    };
})();
