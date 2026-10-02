#define _GNU_SOURCE
#include "WSLProcessSupport.h"
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

int devdeck_spawn_session(const char *shell, const char *command, const char *directory,
                         const char *path, int interactive, int output, int error, pid_t *pid) {
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    int result = posix_spawn_file_actions_init(&actions);
    if (result) return result;
    result = posix_spawnattr_init(&attributes);
    if (result) { posix_spawn_file_actions_destroy(&actions); return result; }
    if (!(result = posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)) &&
        !(result = posix_spawn_file_actions_adddup2(&actions, output, 1)) &&
        !(result = posix_spawn_file_actions_adddup2(&actions, error, 2)) &&
        !(result = posix_spawn_file_actions_addclose(&actions, output)) &&
        !(result = (error == output ? 0 : posix_spawn_file_actions_addclose(&actions, error))) &&
        !(result = posix_spawn_file_actions_addchdir_np(&actions, directory))) {
        result = posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETSID);
    }
    char *arguments[] = { (char *)shell, interactive ? "-ilc" : "-lc", (char *)command, NULL };
    size_t count = 0;
    while (environ[count]) count++;
    char **environment = calloc(count + 2, sizeof(char *));
    char *path_entry = NULL;
    if (!environment) result = ENOMEM;
    if (path && !result && asprintf(&path_entry, "PATH=%s", path) < 0) result = ENOMEM;
    if (!result) {
        size_t index = 0;
        for (size_t i = 0; i < count; i++) {
            if (path && strncmp(environ[i], "PATH=", 5) == 0) continue;
            environment[index++] = environ[i];
        }
        if (path_entry) environment[index] = path_entry;
        result = posix_spawn(pid, shell, &actions, &attributes, arguments, environment);
    }
    free(path_entry);
    free(environment);
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attributes);
    return result;
}

int devdeck_wait_child(pid_t pid, int *exit_code) {
    int status;
    pid_t result;
    do { result = waitpid(pid, &status, 0); } while (result < 0 && errno == EINTR);
    if (result < 0) return errno;
    *exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
    return 0;
}

int devdeck_signal_group(pid_t pid, int signal_number) {
    if (pid <= 1) return EINVAL;
    return kill(-pid, signal_number) == 0 ? 0 : errno;
}
