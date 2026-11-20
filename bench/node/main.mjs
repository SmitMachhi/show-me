// Benchmark mini-daemon, Node and Bun reference (the stack lavish uses). Standard library only.
import http from "node:http";

const [mode, port] = process.argv.slice(2);
if (mode === "ping") {
    http.get({ host: "127.0.0.1", port, path: "/health", agent: false }, (r) => {
        r.resume();
        r.on("end", () => {
            console.log(r.statusCode === 200 ? "ok" : "bad");
            process.exit(r.statusCode === 200 ? 0 : 1);
        });
    });
} else {
    let waiters = [];
    const server = http.createServer((q, r) => {
        r.setHeader("Connection", "close");
        if (q.url === "/health") {
            r.end("ok");
        } else if (q.url === "/wait") {
            waiters.push(r);
        } else if (q.url === "/send") {
            const parts = [];
            q.on("data", (d) => parts.push(d));
            q.on("end", () => {
                const body = Buffer.concat(parts);
                for (const w of waiters) {
                    w.end(body);
                }
                waiters = [];
                r.end("ok");
            });
        } else if (q.url === "/quit") {
            r.end("bye", () => process.exit(0));
        } else {
            r.statusCode = 404;
            r.end("no");
        }
    });
    server.listen(+port, "127.0.0.1", () => console.log("ready"));
}
