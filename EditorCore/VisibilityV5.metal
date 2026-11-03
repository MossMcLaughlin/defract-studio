#include <CoreImage/CoreImage.h>
using namespace metal;

static float v5Luma(float3 rgb) {
    return dot(rgb, float3(0.2126f, 0.7152f, 0.0722f));
}

static float v5Smooth(float low, float high, float value) {
    float x = clamp((value - low) / (high - low), 0.0f, 1.0f);
    return x * x * (3.0f - 2.0f * x);
}

extern "C" float4 logLuminanceV5(coreimage::sampler source) {
    float4 pixel = source.sample(source.coord());
    float3 rgb = pixel.rgb / max(pixel.a, 0.000001f);
    float value = log2(max(v5Luma(rgb), 0.00006103515625f));
    return float4(value, value, value, pixel.a);
}

extern "C" float4 clarityV5(coreimage::sampler source, coreimage::sampler logImage,
                             coreimage::sampler baseImage, float strength, float sigma) {
    float4 pixel = source.sample(source.coord());
    if (pixel.a < 0.999f) return pixel;
    float3 rgb = pixel.rgb / pixel.a;
    float luminance = v5Luma(rgb);
    if (luminance <= 0.0001f) return pixel;
    float detail = logImage.sample(logImage.coord()).r - baseImage.sample(baseImage.coord()).r;
    float limited = 0.35f * tanh(detail / 0.35f);
    float noiseFloor = 0.02f + 4.0f * clamp(sigma, 0.0f, 0.02f);
    float texture = v5Smooth(noiseFloor, noiseFloor + 0.06f, abs(detail));
    float tone = v5Smooth(0.008f, 0.06f, luminance) * (1.0f - v5Smooth(0.75f, 1.2f, luminance));
    float ratio = clamp(exp2(0.6f * strength * limited * texture * tone), 0.67f, 1.5f);
    return float4(rgb * ratio * pixel.a, pixel.a);
}

extern "C" float4 dehazeV5(coreimage::sampler source, coreimage::sampler smoothImage,
                            float ar, float ag, float ab, float strength, float confidence) {
    float4 pixel = source.sample(source.coord());
    if (pixel.a < 0.999f) return pixel;
    float3 rgb = pixel.rgb / pixel.a;
    float3 smoothed = smoothImage.sample(smoothImage.coord()).rgb;
    float3 air = float3(ar, ag, ab);
    float proxy = clamp(min(smoothed.g / max(ag, 0.02f), smoothed.b / max(ab, 0.02f)), 0.0f, 1.0f);
    float transmission = clamp(1.0f - 0.65f * strength * proxy, 0.60f, 1.0f);
    float luminance = v5Luma(rgb);
    float smoothLuma = v5Luma(smoothed);
    float separation = abs(log2(max(luminance, 0.000061f)) - log2(max(smoothLuma, 0.000061f)));
    float structure = v5Smooth(0.025f, 0.10f, separation) * (1.0f - v5Smooth(0.28f, 0.55f, separation));
    float tonal = v5Smooth(0.008f, 0.045f, luminance) * (1.0f - v5Smooth(0.65f, 0.9f, luminance));
    float reliability = confidence * mix(0.25f, 1.0f, structure) * tonal;
    float3 recovered = air + (rgb - air) / transmission;
    // A scalar transmission keeps hue stable; the blend remains deliberately weak in smooth water.
    return float4(mix(rgb, recovered, reliability) * pixel.a, pixel.a);
}
