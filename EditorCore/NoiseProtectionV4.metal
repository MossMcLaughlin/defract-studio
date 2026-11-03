#include <CoreImage/CoreImage.h>
using namespace metal;

static float encodedV4(float linear) {
    float magnitude = abs(linear);
    float result = magnitude <= 0.0031308f ? 12.92f * magnitude
        : 1.055f * pow(magnitude, 1.0f / 2.4f) - 0.055f;
    return copysign(result, linear);
}

static float linearV4(float encoded) {
    float magnitude = abs(encoded);
    float result = magnitude <= 0.04045f ? magnitude / 12.92f
        : pow((magnitude + 0.055f) / 1.055f, 2.4f);
    return copysign(result, encoded);
}

static float3 opponentV4(float4 pixel) {
    float3 rgb = pixel.rgb / max(pixel.a, 0.000001f);
    float3 encoded = float3(encodedV4(rgb.r), encodedV4(rgb.g), encodedV4(rgb.b));
    float y = dot(encoded, float3(0.2126f, 0.7152f, 0.0722f));
    return float3(y, encoded.b - y, encoded.r - y);
}

static float3 rgbV4(float3 opponent) {
    float red = opponent.x + opponent.z;
    float blue = opponent.x + opponent.y;
    float green = (opponent.x - 0.2126f * red - 0.0722f * blue) / 0.7152f;
    return float3(linearV4(red), linearV4(green), linearV4(blue));
}

extern "C" float4 sourceProtectV4(coreimage::sampler source, coreimage::sampler field,
                                  float rangeY, float rangeC, float radius) {
    float2 coordinate = source.coord();
    float4 center = source.sample(coordinate);
    float2 strength = clamp(field.sample(field.coord()).rg, 0.0f, 1.0f);
    if (center.a <= 0.000001f || all(strength <= float2(0.0f))) return center;
    float3 original = opponentV4(center);
    float3 weighted = float3(0.0f);
    float total = 0.0f;
    const float spatial[5] = {0.13533528f, 0.60653066f, 1.0f, 0.60653066f, 0.13533528f};
    for (int y = -2; y <= 2; ++y) {
        for (int x = -2; x <= 2; ++x) {
            float4 neighbor = source.sample(coordinate + radius * float2(x, y));
            if (neighbor.a <= 0.000001f) continue;
            float3 candidate = opponentV4(neighbor);
            float dy = (candidate.x - original.x) / rangeY;
            float2 dc = (candidate.yz - original.yz) / rangeC;
            float guide = exp(-0.5f * (dy*dy + dot(dc, dc)));
            float weight = spatial[x + 2] * spatial[y + 2] * guide * neighbor.a;
            weighted += weight * candidate;
            total += weight;
        }
    }
    float3 filtered = weighted / max(total, 0.000001f);
    float3 result = float3(mix(original.x, filtered.x, strength.y),
                           mix(original.y, filtered.y, strength.x),
                           mix(original.z, filtered.z, strength.x));
    return float4(rgbV4(result) * center.a, center.a);
}
