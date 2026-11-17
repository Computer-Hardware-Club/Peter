/* Drive a production recording and its participant socket on the lab tmpfs. */
#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <unistd.h>

#include <guacamole/client.h>
#include <guacamole/recording.h>
#include <guacamole/socket.h>

int main(void) {
    const size_t mib = 1024 * 1024;
    const size_t limit = 48 * mib;
    static char block[1024 * 1024];
    const char *name = "size-cap-fixture";
    const char *path = "/recordings/size-cap-fixture";
    guac_client *client = guac_client_alloc();
    assert(client != NULL);
    guac_socket_free(client->socket);
    int sink = open("/tmp/participant-fixture", O_RDWR | O_CREAT | O_TRUNC, 0600);
    assert(sink >= 0);
    assert(unlink("/tmp/participant-fixture") == 0);
    client->socket = guac_socket_open(sink);
    guac_recording *recording = guac_recording_create(client, "/recordings", name, 0, 1, 0, 0, 0, 0);
    assert(recording != NULL);
    int fd = open(path, O_RDONLY);
    assert(fd >= 0);
    assert(unlink(path) == 0);
    struct stat contents;
    struct stat participant;
    struct statvfs disk;
    for (size_t written = 0; written < limit + 4 * mib; written += sizeof block) {
        assert(guac_socket_write(client->socket, block, sizeof block) == 0);
        assert(guac_socket_flush(client->socket) == 0);
        assert(fstat(fd, &contents) == 0);
        assert(fstat(sink, &participant) == 0);
        size_t expected = written < limit ? written + sizeof block : limit;
        assert((size_t) contents.st_size == expected);
        assert((size_t) participant.st_size == written + sizeof block);
        assert(fstatvfs(fd, &disk) == 0);
        assert(disk.f_bavail * disk.f_frsize > 16 * mib);
    }
    printf("Recording capped at %zu bytes with %lu bytes still available, participant received %zu bytes\n",
           limit, (unsigned long)(disk.f_bavail * disk.f_frsize), (size_t) participant.st_size);
    close(fd);
    guac_recording_free(recording);
    guac_client_free(client);
    return 0;
}
