// socket.c
// Implementation of Unix Domain Socket wrapper for Lean 4 FFI

#include "socket.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

// Socket handle structure
struct klei_socket_t {
    int fd;
    char last_error[256];
};

// Connect to Unix Domain Socket
klei_socket_t* klei_socket_connect(const char* path) {
    if (!path) {
        return NULL;
    }

    // Allocate handle
    klei_socket_t* sock = malloc(sizeof(klei_socket_t));
    if (!sock) {
        return NULL;
    }

    // Initialize error message
    sock->last_error[0] = '\0';

    // Create socket
    sock->fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock->fd < 0) {
        snprintf(sock->last_error, sizeof(sock->last_error),
                 "socket() failed: %s", strerror(errno));
        free(sock);
        return NULL;
    }

    // Set up address
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);

    // Connect
    if (connect(sock->fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        snprintf(sock->last_error, sizeof(sock->last_error),
                 "connect() failed: %s", strerror(errno));
        close(sock->fd);
        free(sock);
        return NULL;
    }

    return sock;
}

// Send data to socket
int64_t klei_socket_send(klei_socket_t* sock, const uint8_t* data, size_t len) {
    if (!sock || sock->fd < 0) {
        return KLEI_ERR_INVALID;
    }

    if (!data || len == 0) {
        return KLEI_ERR_INVALID;
    }

    ssize_t sent = send(sock->fd, data, len, MSG_NOSIGNAL);
    if (sent < 0) {
        snprintf(sock->last_error, sizeof(sock->last_error),
                 "send() failed: %s", strerror(errno));
        return KLEI_ERR_SEND;
    }

    return sent;
}

// Receive data from socket
int64_t klei_socket_recv(
    klei_socket_t* sock,
    uint8_t* buffer,
    size_t bufsize,
    uint32_t timeout_ms
) {
    if (!sock || sock->fd < 0) {
        return KLEI_ERR_INVALID;
    }

    if (!buffer || bufsize == 0) {
        return KLEI_ERR_INVALID;
    }

    // Set timeout if requested
    if (timeout_ms > 0) {
        struct timeval tv;
        tv.tv_sec = timeout_ms / 1000;
        tv.tv_usec = (timeout_ms % 1000) * 1000;
        if (setsockopt(sock->fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv)) < 0) {
            snprintf(sock->last_error, sizeof(sock->last_error),
                     "setsockopt() failed: %s", strerror(errno));
            return KLEI_ERR_INVALID;
        }
    }

    ssize_t received = recv(sock->fd, buffer, bufsize, 0);
    if (received < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            snprintf(sock->last_error, sizeof(sock->last_error),
                     "recv() timeout after %u ms", timeout_ms);
            return KLEI_ERR_TIMEOUT;
        }
        snprintf(sock->last_error, sizeof(sock->last_error),
                 "recv() failed: %s", strerror(errno));
        return KLEI_ERR_RECV;
    } else if (received == 0) {
        snprintf(sock->last_error, sizeof(sock->last_error),
                 "Connection closed by peer");
        return KLEI_ERR_CLOSED;
    }

    return received;
}

// Close socket and free resources
void klei_socket_close(klei_socket_t* sock) {
    if (!sock) {
        return;
    }
    if (sock->fd >= 0) {
        close(sock->fd);
        sock->fd = -1;
    }
    free(sock);
}

// Get last error message
const char* klei_socket_error(klei_socket_t* sock) {
    if (!sock) {
        return "Invalid socket handle";
    }
    return sock->last_error;
}
