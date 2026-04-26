#include <unistd.h>
#include <string.h>
#include <time.h>

int cstr_write(int fd, const char *s) {
    return (int)write(fd, s, strlen(s));
}

const char *cstr_timestamp() {
    static char buf[64];
    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);
    strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", tm_info);
    return buf;
}
