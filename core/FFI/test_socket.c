// test_socket.c
// Test program for klei_socket library
// Creates a simple echo server and tests client operations

#include "socket.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <signal.h>

#define TEST_SOCKET_PATH "/tmp/klei_test.sock"
#define TEST_MESSAGE "Hello, Klei!"
#define BUFFER_SIZE 1024

// Simple echo server for testing
void run_test_server() {
    int server_fd, client_fd;
    struct sockaddr_un addr;
    uint8_t buffer[BUFFER_SIZE];

    // Remove old socket if exists
    unlink(TEST_SOCKET_PATH);

    // Create server socket
    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd < 0) {
        perror("Server socket creation failed");
        exit(1);
    }

    // Bind to path
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, TEST_SOCKET_PATH, sizeof(addr.sun_path) - 1);

    if (bind(server_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        perror("Server bind failed");
        close(server_fd);
        exit(1);
    }

    // Listen
    if (listen(server_fd, 1) < 0) {
        perror("Server listen failed");
        close(server_fd);
        exit(1);
    }

    // Accept one connection
    client_fd = accept(server_fd, NULL, NULL);
    if (client_fd < 0) {
        perror("Server accept failed");
        close(server_fd);
        exit(1);
    }

    // Echo loop - read and send back
    ssize_t n = recv(client_fd, buffer, BUFFER_SIZE, 0);
    if (n > 0) {
        send(client_fd, buffer, n, 0);
    }

    // Cleanup
    close(client_fd);
    close(server_fd);
    unlink(TEST_SOCKET_PATH);
}

// Test the client library
int run_client_test() {
    klei_socket_t* sock;
    uint8_t send_buf[BUFFER_SIZE];
    uint8_t recv_buf[BUFFER_SIZE];
    int64_t result;
    int errors = 0;

    printf("Testing klei_socket library...\n");

    // Test 1: Connect
    printf("Test 1: Connecting to %s... ", TEST_SOCKET_PATH);
    fflush(stdout);

    sock = klei_socket_connect(TEST_SOCKET_PATH);
    if (!sock) {
        printf("FAILED\n");
        printf("  Error: Unable to connect\n");
        return 1;
    }
    printf("PASSED\n");

    // Test 2: Send data
    printf("Test 2: Sending message... ");
    fflush(stdout);

    strcpy((char*)send_buf, TEST_MESSAGE);
    result = klei_socket_send(sock, send_buf, strlen(TEST_MESSAGE));
    if (result < 0) {
        printf("FAILED\n");
        printf("  Error code: %ld\n", result);
        printf("  Error message: %s\n", klei_socket_error(sock));
        errors++;
    } else if ((size_t)result != strlen(TEST_MESSAGE)) {
        printf("FAILED\n");
        printf("  Expected %zu bytes, sent %ld bytes\n", strlen(TEST_MESSAGE), result);
        errors++;
    } else {
        printf("PASSED (%ld bytes)\n", result);
    }

    // Test 3: Receive data
    printf("Test 3: Receiving echo... ");
    fflush(stdout);

    result = klei_socket_recv(sock, recv_buf, BUFFER_SIZE, 5000);  // 5 second timeout
    if (result < 0) {
        printf("FAILED\n");
        printf("  Error code: %ld\n", result);
        printf("  Error message: %s\n", klei_socket_error(sock));
        errors++;
    } else {
        recv_buf[result] = '\0';  // Null-terminate
        if (strcmp((char*)recv_buf, TEST_MESSAGE) == 0) {
            printf("PASSED (%ld bytes)\n", result);
        } else {
            printf("FAILED\n");
            printf("  Expected: '%s'\n", TEST_MESSAGE);
            printf("  Received: '%s'\n", recv_buf);
            errors++;
        }
    }

    // Test 4: Close
    printf("Test 4: Closing connection... ");
    fflush(stdout);

    klei_socket_close(sock);
    printf("PASSED\n");

    // Summary
    printf("\n");
    if (errors == 0) {
        printf("All tests passed!\n");
        return 0;
    } else {
        printf("%d test(s) failed.\n", errors);
        return 1;
    }
}

int main() {
    pid_t server_pid;

    printf("=== Klei Socket Library Test ===\n\n");

    // Fork server process
    server_pid = fork();
    if (server_pid < 0) {
        perror("Fork failed");
        return 1;
    }

    if (server_pid == 0) {
        // Child: run server
        run_test_server();
        exit(0);
    } else {
        // Parent: wait a bit for server to start, then run client
        usleep(100000);  // 100ms

        int result = run_client_test();

        // Wait for server to finish
        waitpid(server_pid, NULL, 0);

        return result;
    }
}
