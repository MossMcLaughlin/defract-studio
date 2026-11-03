#include <CoreImage/CoreImage.h>
using namespace metal;

static float signedCubeRoot(float value) {
    return copysign(pow(abs(value), 1.0f / 3.0f), value);
}

static float3 toOklab(float3 rgb) {
    float l = signedCubeRoot(dot(rgb, float3(0.4122214708f, 0.5363325363f, 0.0514459929f)));
    float m = signedCubeRoot(dot(rgb, float3(0.2119034982f, 0.6806995451f, 0.1073969566f)));
    float s = signedCubeRoot(dot(rgb, float3(0.0883024619f, 0.2817188376f, 0.6299787005f)));
    return float3(0.2104542553f*l + 0.7936177850f*m - 0.0040720468f*s,
                  1.9779984951f*l - 2.4285922050f*m + 0.4505937099f*s,
                  0.0259040371f*l + 0.7827717662f*m - 0.8086757660f*s);
}

static float3 fromOklab(float3 lab) {
    float l = lab.x + 0.3963377774f*lab.y + 0.2158037573f*lab.z;
    float m = lab.x - 0.1055613458f*lab.y - 0.0638541728f*lab.z;
    float s = lab.x - 0.0894841775f*lab.y - 1.2914855480f*lab.z;
    l *= l*l; m *= m*m; s *= s*s;
    return float3(4.0767416621f*l - 3.3077115913f*m + 0.2309699292f*s,
                 -1.2684380046f*l + 2.6097574011f*m - 0.3413193965f*s,
                 -0.0041960863f*l - 0.7034186147f*m + 1.7076147010f*s);
}

static bool inGamut(float3 rgb) {
    return all(rgb >= float3(0.0f)) && all(rgb <= float3(1.0f));
}

static float3 sdrGamut(float3 rgb) {
    if (inGamut(rgb)) return rgb;
    float3 lab = toOklab(rgb);
    float light = clamp(lab.x, 0.0f, 1.0f);
    float chroma = length(lab.yz);
    if (chroma < 0.00001f) return float3(light*light*light);
    float2 direction = lab.yz / chroma;
    float low = 0.0f, high = chroma;
    for (int iteration = 0; iteration < 12; ++iteration) {
        float middle = 0.5f * (low + high);
        float3 candidate = fromOklab(float3(light, direction * middle));
        if (inGamut(candidate)) low = middle;
        else high = middle;
    }
    return clamp(fromOklab(float3(light, direction * low)), 0.0f, 1.0f);
}

static float encodeSRGB(float value) {
    value = clamp(value, 0.0f, 1.0f);
    return value <= 0.0031308f ? 12.92f*value : 1.055f*pow(value, 1.0f/2.4f)-0.055f;
}

static float selectionHue(float3 rgb) {
    float3 encoded = float3(encodeSRGB(rgb.r), encodeSRGB(rgb.g), encodeSRGB(rgb.b));
    float upper = max(encoded.r, max(encoded.g, encoded.b));
    float lower = min(encoded.r, min(encoded.g, encoded.b));
    float span = upper - lower;
    if (span < 0.000001f) return 0.0f;
    float hue;
    if (upper == encoded.r) hue = 60.0f * (encoded.g - encoded.b) / span;
    else if (upper == encoded.g) hue = 60.0f * ((encoded.b - encoded.r) / span + 2.0f);
    else hue = 60.0f * ((encoded.r - encoded.g) / span + 4.0f);
    return hue < 0.0f ? hue + 360.0f : hue;
}

static float3 mixColor(float3 rgb, float3 weighted, float saturation, float vibrance) {
    float3 lab = toOklab(rgb);
    float chroma = length(lab.yz);
    float originalChroma = chroma;
    float angle = atan2(lab.z, lab.y);
    float gate = smoothstep(0.01f, 0.04f, chroma);
    angle += (45.0f * 3.14159265359f / 180.0f) * weighted.x * gate;
    chroma *= max(0.0f, 1.0f + weighted.y);
    float light = lab.x;
    light += 0.15f * weighted.z * gate * max(0.0f, 4.0f*light*(1.0f-light));
    chroma *= max(0.0f, 1.0f + saturation);
    float vibranceScale = vibrance >= 0.0f
        ? 1.0f + 0.8f*vibrance*(1.0f-smoothstep(0.05f, 0.25f, originalChroma))
        : max(0.0f, 1.0f+vibrance);
    chroma *= vibranceScale;
    return fromOklab(float3(light, chroma*cos(angle), chroma*sin(angle)));
}

extern "C" float4 colorGradeV3(coreimage::sampler source, coreimage::sampler curve,
                        coreimage::sampler bandTable, float exposure, float toneEnabled,
                        float saturation, float vibrance, float shoulder, float mixerActive) {
        float4 pixel = source.sample(source.coord());
        float alpha = pixel.a;
        if (alpha <= 0.000001f) return float4(0.0f);
        float3 rgb = pixel.rgb / alpha;
        rgb *= exp2(exposure);
        if (toneEnabled > 0.5f) {
            float luminance = dot(rgb, float3(0.2126f, 0.7152f, 0.0722f));
            if (luminance > 0.000001f) {
                float x = log2(max(luminance, exp2(-14.0f)) / 0.18f);
                float boundedX = clamp(x, -14.0f, 10.0f);
                float position = (boundedX + 14.0f) * (4095.0f / 24.0f) + 0.5f;
                float mapped = curve.sample(float2(position, 0.5f)).r;
                if (x < -14.0f) {
                    float next = curve.sample(float2(1.5f, 0.5f)).r;
                    mapped += (x + 14.0f) * (next - curve.sample(float2(0.5f, 0.5f)).r) * (4095.0f / 24.0f);
                } else if (x > 10.0f) {
                    float previous = curve.sample(float2(4094.5f, 0.5f)).r;
                    mapped += (x - 10.0f) * (curve.sample(float2(4095.5f, 0.5f)).r - previous) * (4095.0f / 24.0f);
                }
                float target = 0.18f * exp2(mapped);
                float gain = target / luminance;
                if (gain > 7.0f) gain = 7.0f + 1.0f - exp(-(gain - 7.0f));
                else if (gain < 0.25f) gain = 0.125f + 0.125f * exp((gain - 0.25f) / 0.125f);
                rgb *= gain;
            }
        }
        if (mixerActive > 0.5f) {
            float hue = selectionHue(rgb);
            float3 weighted = bandTable.sample(float2(hue * (1024.0f / 360.0f) + 0.5f, 0.5f)).rgb;
            rgb = mixColor(rgb, weighted, saturation, vibrance);
        }
        if (shoulder > 0.0f) {
            float luminance = dot(rgb, float3(0.2126f, 0.7152f, 0.0722f));
            if (luminance > 0.8f) {
                float target = 0.8f + 0.2f * (1.0f - exp(-(luminance - 0.8f)/0.2f));
                rgb *= mix(1.0f, target / luminance, shoulder);
            }
        }
        return float4(sdrGamut(rgb) * alpha, alpha);
    }
