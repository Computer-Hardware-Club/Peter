/* Drive the production libguac recording writer on the lab's real tmpfs. */
#include <assert.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <unistd.h>

typedef struct guac_socket guac_socket;

int main(void) {
    const size_t mib = 1024 * 1024;
    const size_t limit = 48 * mib;
    static char block[1024 * 1024];
    const char *path = "/recordings/size-cap-fixture";
    void *library = dlopen("/opt/guacamole/lib/libguac.so.25.0.0", RTLD_NOW);
    if (!library) {
        fprintf(stderr, "%s\n", dlerror());
        return 1;
    }
    guac_socket *(*open_recording)(int, size_t) = dlsym(library, "guac_socket_open_recording");
    ssize_t (*write_recording)(guac_socket *, const void *, size_t) = dlsym(library, "guac_socket_write");
    ssize_t (*flush_recording)(guac_socket *) = dlsym(library, "guac_socket_flush");
    void (*free_recording)(guac_socket *) = dlsym(library, "guac_socket_free");
    assert(open_recording && write_recording && flush_recording && free_recording);

    int fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0600);
    assert(fd >= 0);
    assert(unlink(path) == 0);
    guac_socket *socket = open_recording(fd, limit);
    struct stat contents;
    struct statvfs disk;
    for (size_t written = 0; written < limit + 4 * mib; written += sizeof block) {
        assert(write_recording(socket, block, sizeof block) == 0);
        assert(flush_recording(socket) == 0);
        assert(fstat(fd, &contents) == 0);
        size_t expected = written < limit ? written + sizeof block : limit;
        assert((size_t) contents.st_size == expected);
        assert(fstatvfs(fd, &disk) == 0);
        assert(disk.f_bavail * disk.f_frsize > 16 * mib);
    }
    printf("Recording capped at %zu bytes with %lu bytes still available\n", limit,
           (unsigned long)(disk.f_bavail * disk.f_frsize));
    free_recording(socket);
    close(fd);
    return 0;
}
