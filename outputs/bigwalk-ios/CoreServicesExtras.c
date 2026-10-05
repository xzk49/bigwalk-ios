#include <stdint.h>
int Gestalt(uint32_t selector, int32_t *response) {
    if (response) *response = 0;
    return -4; /* Legacy Mac OS queries are unsupported; let the engine fall back. */
}
int UpdateSystemActivity(uint8_t activity) { return -4; }
