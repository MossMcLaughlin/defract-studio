#include <CoreImage/CoreImage.h>
using namespace metal;

static float outputLuma(float3 rgb) {
    return dot(rgb, float3(0.2126f, 0.7152f, 0.0722f));
}

static float outputSmooth(float low, float high, float value) {
    float x = clamp((value - low) / (high - low), 0.0f, 1.0f);
    return x * x * (3.0f - 2.0f * x);
}

extern "C" float4 sharpenV6(coreimage::sampler source, coreimage::sampler blurred,
                             float amount, float noiseSigma) {
    float4 pixel = source.sample(source.coord());
    if (pixel.a < 0.999f) return pixel;
    float3 rgb = pixel.rgb / pixel.a;
    float luminance = outputLuma(rgb);
    if (luminance < 0.0001f) return pixel;
    float4 softPixel = blurred.sample(blurred.coord());
    float softLuma = outputLuma(softPixel.rgb / max(softPixel.a, 0.000001f));
    float detail = luminance - softLuma;
    float threshold = 0.0015f + 2.5f * clamp(noiseSigma, 0.0f, 0.02f);
    float significant = max(0.0f, abs(detail) - threshold);
    float tone = outputSmooth(0.01f, 0.05f, luminance)
        * (1.0f - outputSmooth(0.82f, 1.1f, luminance));
    float edge = 1.0f - outputSmooth(0.18f, 0.40f, abs(detail));
    float change = clamp(copysign(significant, detail) * 0.5f * amount * tone * edge,
                         -0.018f, 0.018f);
    float ratio = clamp((luminance + change) / luminance, 0.9f, 1.1f);
    return float4(rgb * ratio * pixel.a, pixel.a);
}

static uint outputHash(uint seed) {
    seed ^= seed >> 16;
    seed *= 0x7feb352du;
    seed ^= seed >> 15;
    seed *= 0x846ca68bu;
    return seed ^ (seed >> 16);
}

static float outputUniform(uint seed) {
    return float(outputHash(seed) & 0x00ffffffu) / 16777216.0f;
}

static float outputEncode(float linear, bool video) {
    if (video) return linear < 0.018f ? 4.5f * linear : 1.099f * pow(linear, 0.45f) - 0.099f;
    return linear < 0.0031308f ? 12.92f * linear : 1.055f * pow(linear, 1.0f / 2.4f) - 0.055f;
}

static float outputDecode(float encoded, bool video) {
    if (video) return encoded < 0.081f ? encoded / 4.5f : pow((encoded + 0.099f) / 1.099f, 1.0f / 0.45f);
    return encoded < 0.04045f ? encoded / 12.92f : pow((encoded + 0.055f) / 1.055f, 2.4f);
}

extern "C" float4 ditherV6(coreimage::sampler source, float bits, float isVideo, float frameIndex) {
    float4 pixel = source.sample(source.coord());
    if (pixel.a < 0.999f) return pixel;
    float3 rgb = pixel.rgb / pixel.a;
    if (any(rgb < 0.0f) || any(rgb > 1.0f)) return pixel;
    bool video = isVideo > 0.5f;
    float lsb = video ? 1.0f / (219.0f * exp2(bits - 8.0f)) : 1.0f / (exp2(bits) - 1.0f);
    uint2 position = uint2(floor(source.coord()));
    uint seed = position.x * 0x9e3779b9u ^ position.y * 0x85ebca6bu ^ uint(frameIndex) * 0xc2b2ae35u;
    float3 encoded = float3(outputEncode(rgb.r, video), outputEncode(rgb.g, video), outputEncode(rgb.b, video));
    for (uint channel = 0; channel < 3; channel++) {
        uint offset = video ? 0u : 2u * channel;
        float noise = (outputUniform(seed + offset) - outputUniform(seed + offset + 1u)) * lsb;
        float interior = outputSmooth(0.0f, 2.0f * lsb, encoded[channel])
            * (1.0f - outputSmooth(1.0f - 2.0f * lsb, 1.0f, encoded[channel]));
        encoded[channel] = clamp(encoded[channel] + noise * interior, 0.0f, 1.0f);
    }
    return float4(float3(outputDecode(encoded.r, video), outputDecode(encoded.g, video),
                         outputDecode(encoded.b, video)) * pixel.a, pixel.a);
}
