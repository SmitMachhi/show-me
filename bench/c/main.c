// Benchmark mini-daemon. Routes /health /wait /send /quit. C standard library + OS sockets and threads.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
typedef SOCKET sock_t;
typedef CRITICAL_SECTION mutex_t;
typedef CONDITION_VARIABLE cond_t;
#define lock(m) EnterCriticalSection(m)
#define unlock(m) LeaveCriticalSection(m)
#define cond_wait(c, m) SleepConditionVariableCS(c, m, INFINITE)
#define cond_all(c) WakeAllConditionVariable(c)
#define THREAD_RET DWORD WINAPI
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <pthread.h>
#include <sys/socket.h>
#include <unistd.h>
typedef int sock_t;
typedef pthread_mutex_t mutex_t;
typedef pthread_cond_t cond_t;
#define lock(m) pthread_mutex_lock(m)
#define unlock(m) pthread_mutex_unlock(m)
#define cond_wait(c, m) pthread_cond_wait(c, m)
#define cond_all(c) pthread_cond_broadcast(c)
#define closesocket close
#define THREAD_RET void *
#endif

#define MAX 70000

mutex_t mu;
cond_t cv;
long gen;
char last[MAX];
int last_len;

void respond(sock_t s, const char *code, const char *body, int len) {
    char head[128];
    int n = snprintf(head, sizeof head,
        "HTTP/1.1 %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n", code, len);
    send(s, head, n, 0);
    send(s, body, len, 0);
}

int read_head(sock_t s, char *buf, int *n) {
    for (;;) {
        int r = recv(s, buf + *n, MAX - 1 - *n, 0);
        if (r <= 0) {
            return 0;
        }
        *n += r;
        buf[*n] = 0;
        char *p = strstr(buf, "\r\n\r\n");
        if (p) {
            return (int)(p - buf) + 4;
        }
    }
}

void do_send(sock_t s, char *buf, int n, int head_end) {
    char *cl = strstr(buf, "Content-Length:");
    if (!cl) {
        cl = strstr(buf, "content-length:");
    }
    int len = cl ? atoi(cl + 15) : 0;
    while (n < head_end + len && n < MAX - 1) {
        int r = recv(s, buf + n, MAX - 1 - n, 0);
        if (r <= 0) {
            break;
        }
        n += r;
    }
    lock(&mu);
    gen++;
    last_len = n - head_end;
    memcpy(last, buf + head_end, last_len);
    cond_all(&cv);
    unlock(&mu);
    respond(s, "200 OK", "ok", 2);
}

THREAD_RET handle(void *arg) {
    sock_t s = (sock_t)(size_t)arg;
    char *buf = malloc(MAX);
    int n = 0;
    int head_end = read_head(s, buf, &n);
    if (!head_end) {
        closesocket(s);
        free(buf);
        return 0;
    }
    if (!strncmp(buf, "GET /health", 11)) {
        respond(s, "200 OK", "ok", 2);
    } else if (!strncmp(buf, "GET /wait", 9)) {
        lock(&mu);
        long seen = gen;
        while (gen == seen) {
            cond_wait(&cv, &mu);
        }
        int len = last_len;
        memcpy(buf, last, len);
        unlock(&mu);
        respond(s, "200 OK", buf, len);
    } else if (!strncmp(buf, "POST /send", 10)) {
        do_send(s, buf, n, head_end);
    } else if (!strncmp(buf, "GET /quit", 9)) {
        respond(s, "200 OK", "bye", 3);
        closesocket(s);
        exit(0);
    } else {
        respond(s, "404 Not Found", "no", 2);
    }
    closesocket(s);
    free(buf);
    return 0;
}

int main(int argc, char **argv) {
#ifdef _WIN32
    WSADATA w;
    WSAStartup(MAKEWORD(2, 2), &w);
    InitializeCriticalSection(&mu);
    InitializeConditionVariable(&cv);
#else
    pthread_mutex_init(&mu, 0);
    pthread_cond_init(&cv, 0);
#endif
    struct sockaddr_in a = {.sin_family = AF_INET, .sin_port = htons((unsigned short)atoi(argv[2]))};
    inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
    sock_t l = socket(AF_INET, SOCK_STREAM, 0);
    if (!strcmp(argv[1], "ping")) {
        char out[512] = {0};
        const char *req = "GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n";
        if (connect(l, (struct sockaddr *)&a, sizeof a)) {
            return 1;
        }
        send(l, req, (int)strlen(req), 0);
        int n = 0, r;
        while (n < 511 && (r = recv(l, out + n, 511 - n, 0)) > 0) {
            n += r;
        }
        if (!strstr(out, "200")) {
            return 1;
        }
        puts("ok");
        return 0;
    }
    if (bind(l, (struct sockaddr *)&a, sizeof a) || listen(l, 64)) {
        return 1;
    }
    puts("ready");
    fflush(stdout);
    for (;;) {
        sock_t s = accept(l, 0, 0);
#ifdef _WIN32
        CloseHandle(CreateThread(0, 0, handle, (void *)(size_t)s, 0, 0));
#else
        pthread_t t;
        pthread_create(&t, 0, handle, (void *)(size_t)s);
        pthread_detach(t);
#endif
    }
}
