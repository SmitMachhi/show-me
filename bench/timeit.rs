// Times one command the way an agent pays for it: full wall time from spawn to exit.
// Usage: timeit <label> <runs> <program> [args...]
// Prints the median and the fastest run in milliseconds, after 3 warm-up runs.
// Build: rustc -C opt-level=2 timeit.rs
use std::process::{Command, Stdio};
use std::time::Instant;

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let (label, runs) = (&a[1], a[2].parse::<usize>().unwrap());
    let mut times = vec![];
    for i in 0..runs + 3 {
        let t = Instant::now();
        let status = Command::new(&a[3])
            .args(&a[4..])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .unwrap_or_else(|e| panic!("cannot run {}: {e}", a[3]));
        let ms = t.elapsed().as_secs_f64() * 1000.0;
        assert!(status.success(), "{label}: command failed with {status}");
        if i >= 3 {
            times.push(ms);
        }
    }
    times.sort_by(|x, y| x.partial_cmp(y).unwrap());
    println!("{label:<34} median {:8.1} ms   fastest {:8.1} ms", times[times.len() / 2], times[0]);
}
