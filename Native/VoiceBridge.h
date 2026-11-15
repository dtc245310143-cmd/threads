#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
void *studio_voice_open(const char *directory, char *error, size_t capacity);
int studio_voice_write(void *handle, const char *text, const char *destination, char *error, size_t capacity);
void studio_voice_close(void *handle);
#ifdef __cplusplus
}
#endif
