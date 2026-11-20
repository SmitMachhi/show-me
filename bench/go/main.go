// Benchmark mini-daemon. Routes /health /wait /send /quit. Standard library only.
package main

import (
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
)

func ping(addr string) {
	r, err := http.Get("http://" + addr + "/health")
	if err != nil || r.StatusCode != 200 {
		os.Exit(1)
	}
	io.Copy(io.Discard, r.Body)
	fmt.Println("ok")
}

func main() {
	addr := "127.0.0.1:" + os.Args[2]
	if os.Args[1] == "ping" {
		ping(addr)
		return
	}
	var mu sync.Mutex
	cv := sync.NewCond(&mu)
	gen, last := 0, []byte{}
	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("ok"))
	})
	mux.HandleFunc("/wait", func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		seen := gen
		for gen == seen {
			cv.Wait()
		}
		body := last
		mu.Unlock()
		w.Write(body)
	})
	mux.HandleFunc("/send", func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(io.LimitReader(r.Body, 65536))
		mu.Lock()
		gen++
		last = body
		cv.Broadcast()
		mu.Unlock()
		w.Write([]byte("ok"))
	})
	mux.HandleFunc("/quit", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Connection", "close")
		w.Write([]byte("bye"))
		if f, ok := w.(http.Flusher); ok {
			f.Flush()
		}
		go os.Exit(0)
	})
	l, err := net.Listen("tcp", addr)
	if err != nil {
		fmt.Fprintln(os.Stderr, strings.TrimSpace(err.Error()))
		os.Exit(1)
	}
	fmt.Println("ready")
	http.Serve(l, mux)
}
