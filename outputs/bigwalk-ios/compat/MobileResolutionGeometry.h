#pragma once
#include <stdint.h>
#include <math.h>

typedef struct { int32_t width, height; } BWRenderSize;
// The short edge is the quality tier. Round only the other edge to an even
// pixel; retain the actual viewport aspect for phones, tablets and rotation.
static inline BWRenderSize BWRenderSizeForViewport(double width, double height, int32_t shortEdge) {
    if(!isfinite(width)||!isfinite(height)||width<=0||height<=0||shortEdge<=0)return (BWRenderSize){0,0};
    double longer=fmax(width,height)/fmin(width,height)*shortEdge;
    if(longer>16384)return (BWRenderSize){0,0};
    int32_t longEdge=(int32_t)llround(longer/2.0)*2;
    return width>=height?(BWRenderSize){longEdge,shortEdge}:(BWRenderSize){shortEdge,longEdge};
}
