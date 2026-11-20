// Reads one review's log into what the chat shows. The log is the record: notes, acks
// from the agent's command, replies, and the end and start of the review.
// Receipt per note: Sent, then Seen once one ack covers it, then Done once one reply follows.
export function parseLog(text) {
    const rows = [];
    let file = "";
    let ended = false;
    for (const line of text.split("\n")) {
        let e;
        try { e = JSON.parse(line); } catch (err) { continue; }
        const notes = rows.filter((r) => !r.agent);
        if (e.t === "open") file = e.file;
        if (e.t === "note") rows.push({ note: e.data, state: "Sent" });
        if (e.t === "ack") notes.slice(0, e.n).forEach((r) => { if (r.state === "Sent") r.state = "Seen"; });
        if (e.t === "reply") {
            notes.forEach((r) => { if (r.state === "Seen") r.state = "Done"; });
            rows.push({ agent: true, text: e.text });
        }
        if (e.t === "end") ended = true;
        if (e.t === "start") ended = false;
    }
    return { rows, file, ended, replies: rows.filter((r) => r.agent).length };
}
