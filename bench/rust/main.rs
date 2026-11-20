// Benchmark mini-daemon. Spec: bench/README is the harness; routes /health /wait /send /quit.
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Condvar, Mutex};

type Shared = Arc<(Mutex<(u64, Vec<u8>)>, Condvar)>;

fn respond(s: &mut TcpStream, code: &str, body: &[u8]) {
    let head = format!(
        "HTTP/1.1 {code}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        body.len()
    );
    let _ = s.write_all(head.as_bytes());
    let _ = s.write_all(body);
}

fn read_head(s: &mut TcpStream, buf: &mut [u8]) -> Option<(usize, usize)> {
    let mut n = 0;
    loop {
        let r = s.read(&mut buf[n..]).unwrap_or(0);
        if r == 0 {
            return None;
        }
        n += r;
        if let Some(i) = buf[..n].windows(4).position(|w| w == b"\r\n\r\n") {
            return Some((n, i + 4));
        }
    }
}

fn handle(mut s: TcpStream, shared: Shared) {
    let mut buf = vec![0u8; 70000];
    let Some((mut n, head_end)) = read_head(&mut s, &mut buf) else {
        return;
    };
    let head = String::from_utf8_lossy(&buf[..head_end]).to_string();
    let line = head.lines().next().unwrap_or("");
    if line.starts_with("GET /health") {
        respond(&mut s, "200 OK", b"ok");
    } else if line.starts_with("GET /wait") {
        let (lock, cv) = &*shared;
        let mut g = lock.lock().unwrap();
        let seen = g.0;
        while g.0 == seen {
            g = cv.wait(g).unwrap();
        }
        let body = g.1.clone();
        drop(g);
        respond(&mut s, "200 OK", &body);
    } else if line.starts_with("POST /send") {
        let len: usize = head
            .lines()
            .find_map(|l| l.to_ascii_lowercase().strip_prefix("content-length:").map(|v| v.trim().parse().unwrap_or(0)))
            .unwrap_or(0);
        while n < head_end + len {
            let r = s.read(&mut buf[n..]).unwrap_or(0);
            if r == 0 {
                break;
            }
            n += r;
        }
        let (lock, cv) = &*shared;
        let mut g = lock.lock().unwrap();
        g.0 += 1;
        g.1 = buf[head_end..n].to_vec();
        cv.notify_all();
        drop(g);
        respond(&mut s, "200 OK", b"ok");
    } else if line.starts_with("GET /quit") {
        respond(&mut s, "200 OK", b"bye");
        std::process::exit(0);
    } else {
        respond(&mut s, "404 Not Found", b"no");
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let port: u16 = args[2].parse().unwrap();
    if args[1] == "ping" {
        let mut s = TcpStream::connect(("127.0.0.1", port)).unwrap();
        s.write_all(b"GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n").unwrap();
        let mut out = String::new();
        let _ = s.read_to_string(&mut out);
        if !out.contains("200") {
            std::process::exit(1);
        }
        println!("ok");
        return;
    }
    let l = TcpListener::bind(("127.0.0.1", port)).unwrap();
    println!("ready");
    let shared: Shared = Arc::new((Mutex::new((0, Vec::new())), Condvar::new()));
    for s in l.incoming().flatten() {
        let sh = shared.clone();
        std::thread::spawn(move || handle(s, sh));
    }
}
