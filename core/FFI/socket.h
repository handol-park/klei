// socket.h
// C FFI wrapper for Unix Domain Socket operations
// Used by Lean 4 via FFI for high-performance IPC with vLLM

#ifndef KLEI_SOCKET_H
#define KLEI_SOCKET_H

#include <stddef.h>
#include <stdint.h>

// Opaque socket handle
typedef struct klei_socket_t klei_socket_t;

// Error codes
typedef enum {
    KLEI_OK = 0,
    KLEI_ERR_CONNECT = -1,
    KLEI_ERR_SEND = -2,
    KLEI_ERR_RECV = -3,
    KLEI_ERR_TIMEOUT = -4,
    KLEI_ERR_CLOSED = -5,
    KLEI_ERR_INVALID = -6
} klei_error_t;

// Connect to Unix Domain Socket (implementation)
// Returns: socket handle on success, NULL on failure
klei_socket_t* klei_socket_connect_impl(const char* path);

// Send data to socket (implementation)
// Returns: number of bytes sent, or error code < 0
int64_t klei_socket_send_impl(
    klei_socket_t* sock,
    const uint8_t* data,
    size_t len
);

// Receive data from socket (implementation)
// Returns: number of bytes received, or error code < 0
// Blocks until data available or timeout
int64_t klei_socket_recv_impl(
    klei_socket_t* sock,
    uint8_t* buffer,
    size_t bufsize,
    uint32_t timeout_ms  // 0 = no timeout
);

// Close socket and free resources (implementation)
void klei_socket_close_impl(klei_socket_t* sock);

// Get last error message (implementation)
const char* klei_socket_error_impl(klei_socket_t* sock);

// Check if socket handle is null (implementation)
int klei_socket_is_null_impl(klei_socket_t* sock);

#endif // KLEI_SOCKET_H
