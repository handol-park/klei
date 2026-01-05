// lean_glue.c
// Glue code between Lean FFI and klei_socket C library
// Handles Lean's object representation and calling conventions

#include <lean/lean.h>
#include "socket.h"
#include <string.h>
#include <stdint.h>
#include <stdio.h>

// External class for SocketHandle
static lean_external_class* g_socket_class = NULL;

// Finalize function for socket handle
static void socket_finalize(void* ptr) {
    if (ptr != NULL) {
        klei_socket_t* sock = (klei_socket_t*)ptr;
        // Note: We don't close here because close is called explicitly
        // This is just a safety net for leaked handles
        klei_socket_close_impl(sock);
    }
}

// Foreach function for GC
static void socket_foreach(void* ptr, b_lean_obj_arg f) {
    // No nested objects to traverse
    (void)ptr;
    (void)f;
}

// Initialize the external class (called once)
static void init_socket_class() {
    if (g_socket_class == NULL) {
        g_socket_class = lean_register_external_class(socket_finalize, socket_foreach);
    }
}

// Create a Lean external object wrapping a socket handle
static lean_obj_res wrap_socket(klei_socket_t* sock) {
    init_socket_class();
    return lean_alloc_external(g_socket_class, sock);
}

// Extract socket handle from Lean external object
static klei_socket_t* unwrap_socket(b_lean_obj_arg obj) {
    return (klei_socket_t*)lean_get_external_data(obj);
}

// Lean FFI wrapper for klei_socket_connect
LEAN_EXPORT lean_obj_res klei_socket_connect(b_lean_obj_arg path_obj, lean_obj_arg /* IO world */) {
    const char* path = lean_string_cstr(path_obj);
    klei_socket_t* sock = klei_socket_connect_impl(path);

    // Return IO result (always returns a socket object, even if NULL)
    lean_obj_res socket_obj = wrap_socket(sock);
    return lean_io_result_mk_ok(socket_obj);
}

// Lean FFI wrapper for klei_socket_is_null
LEAN_EXPORT lean_obj_res klei_socket_is_null(b_lean_obj_arg sock_obj, lean_obj_arg /* IO world */) {
    klei_socket_t* sock = unwrap_socket(sock_obj);
    uint8_t is_null = klei_socket_is_null_impl(sock);
    return lean_io_result_mk_ok(lean_box(is_null));
}

// Lean FFI wrapper for klei_socket_send
LEAN_EXPORT lean_obj_res klei_socket_send(b_lean_obj_arg sock_obj, b_lean_obj_arg data_obj,
                              size_t len, lean_obj_arg /* IO world */) {
    klei_socket_t* sock = unwrap_socket(sock_obj);

    // Extract byte array data
    const uint8_t* data = lean_sarray_cptr(data_obj);

    // Call C function
    int64_t result = klei_socket_send_impl(sock, data, len);

    // Return IO result with Int64
    lean_obj_res result_obj = lean_int64_to_int(result);
    return lean_io_result_mk_ok(result_obj);
}

// Lean FFI wrapper for klei_socket_recv
LEAN_EXPORT lean_obj_res klei_socket_recv(b_lean_obj_arg sock_obj, b_lean_obj_arg buffer_obj,
                              size_t bufsize, uint32_t timeout_ms, lean_obj_arg /* IO world */) {
    klei_socket_t* sock = unwrap_socket(sock_obj);
    uint8_t* buffer = lean_sarray_cptr(buffer_obj);

    // Call C function
    int64_t result = klei_socket_recv_impl(sock, buffer, bufsize, timeout_ms);

    // Update the byte array size if we received data
    if (result > 0) {
        lean_sarray_object* sarray = (lean_sarray_object*)lean_to_sarray(buffer_obj);
        sarray->m_size = result;
    }

    // Return IO result with Int64
    lean_obj_res result_obj = lean_int64_to_int(result);
    return lean_io_result_mk_ok(result_obj);
}

// Lean FFI wrapper for klei_socket_close
LEAN_EXPORT lean_obj_res klei_socket_close(b_lean_obj_arg sock_obj, lean_obj_arg /* IO world */) {
    klei_socket_t* sock = unwrap_socket(sock_obj);
    klei_socket_close_impl(sock);
    return lean_io_result_mk_ok(lean_box(0));
}

// Lean FFI wrapper for klei_socket_error
LEAN_EXPORT lean_obj_res klei_socket_error(b_lean_obj_arg sock_obj, lean_obj_arg /* IO world */) {
    klei_socket_t* sock = unwrap_socket(sock_obj);
    const char* err_msg = klei_socket_error_impl(sock);
    lean_obj_res err_str = lean_mk_string(err_msg);
    return lean_io_result_mk_ok(err_str);
}
