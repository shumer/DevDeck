#pragma once
#include <sys/types.h>

int devdeck_spawn_session(const char *shell, const char *command, const char *directory,
                         const char *path, int interactive, int output, int error, pid_t *pid);
int devdeck_wait_child(pid_t pid, int *exit_code);
int devdeck_signal_group(pid_t pid, int signal_number);
