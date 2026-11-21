// Reads one review's log into what the chat shows. The log is the record: notes, acks
// from the agent's command, working marks, replies, and the end and start of the review.
// Receipt per note: Sent, then Seen once one ack covers it, then Working once the agent
// changes the page after that, then Done once one reply follows.
// Each step keeps the time from the {"t":"at"} line before it. Logs from before
// version 0.1.5 have no time lines; their steps have no time.
export function parseLog(text) {
    const rows = [];
    let file = "";
    let ended = false;
    let at = null;
    const step = (r, from, to) => {
        if (r.state !== from) return;
        r.state = to;
        r.times[to] = at;
    };
    for (const line of text.split("\n")) {
        let e;
        try { e = JSON.parse(line); } catch (err) { continue; }
        if (e.t === "at") { at = e.ms; continue; }
        const notes = rows.filter((r) => !r.agent);
        if (e.t === "open") file = e.file;
        if (e.t === "note") rows.push({ note: e.data, state: "Sent", times: { Sent: at } });
        if (e.t === "ack") notes.slice(0, e.n).forEach((r) => step(r, "Sent", "Seen"));
        if (e.t === "working") notes.forEach((r) => step(r, "Seen", "Working"));
        if (e.t === "reply") {
            notes.forEach((r) => { step(r, "Seen", "Done"); step(r, "Working", "Done"); });
            rows.push({ agent: true, text: e.text });
        }
        if (e.t === "end") ended = true;
        if (e.t === "start") ended = false;
        if (e.t !== "id") at = null;
    }
    return { rows, file, ended, replies: rows.filter((r) => r.agent).length };
}
