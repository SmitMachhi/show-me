// Benchmark harness (Windows). Usage: harness <label> <exe> [pre-args...]
// The target must support `serve <port>` (prints "ready") and `ping <port>`.
// Reports median and min over runs after warm-up. Times are wall clock from spawn.
use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpStream;
use std::os::windows::io::AsRawHandle;
use std::process::{Child, Command, Stdio};
use std::time::Instant;

#[repr(C)]
#[derive(Default)]
struct Pmc {
    cb: u32,
    faults: u32,
    peak_ws: usize,
    ws: usize,
    q1: usize,
    q2: usize,
    q3: usize,
    q4: usize,
    pagefile: usize,
    peak_pagefile: usize,
    private: usize,
}

extern "system" {
    fn K32GetProcessMemoryInfo(h: *mut std::ffi::c_void, p: *mut Pmc, cb: u32) -> i32;
}

fn mem(c: &Child) -> (f64, f64) {
    let mut p = Pmc::default();
    p.cb = std::mem::size_of::<Pmc>() as u32;
    let ok = unsafe { K32GetProcessMemoryInfo(c.as_raw_handle() as _, &mut p, p.cb) };
    assert!(ok != 0);
    (p.private as f64 / 1048576.0, p.ws as f64 / 1048576.0)
}

fn req(port: u16, text: &str) -> String {
    let mut s = TcpStream::connect(("127.0.0.1", port)).unwrap();
    s.write_all(text.as_bytes()).unwrap();
    let mut out = String::new();
    let _ = s.read_to_string(&mut out);
    out
}

fn serve(exe: &str, pre: &[String], port: u16) -> (Child, f64) {
    let t = Instant::now();
    let mut c = Command::new(exe)
        .args(pre)
        .arg("serve")
        .arg(port.to_string())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    let mut line = String::new();
    BufReader::new(c.stdout.take().unwrap()).read_line(&mut line).unwrap();
    assert!(line.trim() == "ready", "no ready line: {}", line);
    (c, t.elapsed().as_secs_f64() * 1000.0)
}

fn quit(mut c: Child, port: u16) {
    let _ = req(port, "GET /quit HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n");
    std::thread::sleep(std::time::Duration::from_millis(30));
    let _ = c.kill();
    let _ = c.wait();
}

fn stats(mut v: Vec<f64>, warm: usize) -> (f64, f64) {
    v.drain(..warm);
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    (v[v.len() / 2], v[0])
}

fn bench_start(exe: &str, pre: &[String], base: u16) -> (f64, f64) {
    let mut starts = vec![];
    for i in 0..25 {
        let (c, ms) = serve(exe, pre, base + i);
        starts.push(ms);
        quit(c, base + i);
    }
    stats(starts, 5)
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let (label, exe, pre) = (&a[1], &a[2], &a[3..]);
    let base: u16 = 48000 + (std::process::id() % 500) as u16 * 2;
    let (start_med, start_min) = bench_start(exe, pre, base);

    let port = base + 40;
    let (c, _) = serve(exe, pre, port);
    let mut pings = vec![];
    for _ in 0..45 {
        let t = Instant::now();
        let out = Command::new(exe).args(pre).arg("ping").arg(port.to_string()).output().unwrap();
        pings.push(t.elapsed().as_secs_f64() * 1000.0);
        assert!(String::from_utf8_lossy(&out.stdout).trim() == "ok", "ping failed");
    }
    let (ping_med, ping_min) = stats(pings, 5);
    std::thread::sleep(std::time::Duration::from_millis(500));
    let (idle_priv, idle_ws) = mem(&c);

    let mut wakes = vec![];
    let mut held = (0.0, 0.0);
    for i in 0..25 {
        let waiter = std::thread::spawn(move || {
            req(port, "GET /wait HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
        });
        std::thread::sleep(std::time::Duration::from_millis(60));
        if i == 24 {
            held = mem(&c);
        }
        let t = Instant::now();
        req(port, "POST /send HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello");
        let got = waiter.join().unwrap();
        wakes.push(t.elapsed().as_secs_f64() * 1000.0);
        assert!(got.ends_with("hello"), "wait got {}", got);
    }
    let (wake_med, wake_min) = stats(wakes, 5);
    quit(c, port);

    println!(
        "{label:<10} start {start_med:7.1} / {start_min:7.1} ms | ping {ping_med:7.1} / {ping_min:7.1} ms | wake {wake_med:5.2} / {wake_min:5.2} ms | idle {idle_priv:6.2} MB priv {idle_ws:6.2} MB ws | 1 waiter {:6.2} MB priv {:6.2} MB ws",
        held.0, held.1
    );
}
