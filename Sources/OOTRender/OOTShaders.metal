#include <metal_stdlib>

using namespace metal;

struct VertexIn {
    float3 position;
    float2 texCoord;
    float4 color;
    float3 normal;
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
    float fog;
};

struct FrameUniforms {
    float4x4 mvp;
    float4 fogParameters;
    float4 ambientColor;
    float4 directionalLightColor;
    float4 directionalLightDirection;
    float4 fogColor;
};

struct CombinerUniforms {
    uint4 cycle1ColorSelectors;
    uint4 cycle1AlphaSelectors;
    uint4 cycle2ColorSelectors;
    uint4 cycle2AlphaSelectors;
    float4 primitiveColor;
    float4 environmentColor;
    float4 fogColor;
    float2 textureScale;
    float2 textureOffset;
    float2 textureDimensions;
    float2 textureTileSpan;
    uint2 textureClamp;
    uint2 textureMirror;
    float alphaCompareThreshold;
    uint alphaCompareMode;
    uint geometryMode;
    uint renderMode;
};

struct N64VertexIn {
    short3 position [[attribute(0)]];
    short2 texCoord [[attribute(1)]];
    uchar4 shadeData [[attribute(2)]];
};

struct DrawBatchVertexIn {
    float4 clipPosition [[attribute(0)]];
    float4 shadeData [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
};

struct XRayDebugVertexIn {
    float3 position [[attribute(0)]];
    float4 color [[attribute(1)]];
};

constant uint kGeometryModeFog = 0x00010000;
constant uint kGeometryModeLighting = 0x00020000;

float computeFogFactor(float4 clipPosition, float4 fogParameters) {
    float fogStart = fogParameters.x;
    float fogEnd = max(fogParameters.y, fogStart + 0.0001);
    float viewDistance = length(clipPosition.xyz / max(clipPosition.w, 0.0001));
    return clamp((fogEnd - viewDistance) / (fogEnd - fogStart), 0.0, 1.0);
}

float3 decodeRawNormal(uchar4 shadeData) {
    int3 signedComponents = int3(shadeData.xyz);
    signedComponents -= select(int3(0), int3(256), signedComponents > 127);
    float3 normal = float3(signedComponents) / 127.0;
    if (length_squared(normal) < 0.0001) {
        return float3(0.0, 1.0, 0.0);
    }
    return normalize(normal);
}

float4 evaluateShadeColor(
    float4 shadeData,
    constant FrameUniforms& frameUniforms,
    uint geometryMode
) {
    if ((geometryMode & kGeometryModeLighting) == 0u) {
        return shadeData;
    }

    float3 normal = normalize(shadeData.xyz);
    float3 lightDirection = normalize(-frameUniforms.directionalLightDirection.xyz);
    float diffuse = max(dot(normal, lightDirection), 0.0);
    float3 litColor = clamp(
        frameUniforms.ambientColor.rgb + (frameUniforms.directionalLightColor.rgb * diffuse),
        0.0,
        1.0
    );
    return float4(litColor, shadeData.w);
}

vertex VertexOut oot_passthrough_vertex(
    N64VertexIn rawVertex [[stage_in]],
    constant FrameUniforms& frameUniforms [[buffer(1)]],
    constant CombinerUniforms& combinerUniforms [[buffer(2)]]
) {
    VertexIn vertexIn;
    vertexIn.position = float3(rawVertex.position);
    vertexIn.texCoord = float2(rawVertex.texCoord);
    vertexIn.color = float4(rawVertex.shadeData) / 255.0;
    vertexIn.normal = float3(0.0);

    float4 clipPosition = frameUniforms.mvp * float4(vertexIn.position, 1.0);
    float4 shadeData = vertexIn.color;
    if ((combinerUniforms.geometryMode & kGeometryModeLighting) != 0u) {
        shadeData = float4(
            decodeRawNormal(rawVertex.shadeData),
            float(rawVertex.shadeData.w) / 255.0
        );
    }

    VertexOut out;
    out.position = clipPosition;
    out.texCoord = ((float2(rawVertex.texCoord) / 32.0) * combinerUniforms.textureScale) + combinerUniforms.textureOffset;
    out.color = evaluateShadeColor(
        shadeData,
        frameUniforms,
        combinerUniforms.geometryMode
    );
    out.fog = computeFogFactor(clipPosition, frameUniforms.fogParameters);
    return out;
}

vertex VertexOut oot_draw_batch_vertex(
    DrawBatchVertexIn vertexIn [[stage_in]],
    constant FrameUniforms& frameUniforms [[buffer(1)]],
    constant CombinerUniforms& combinerUniforms [[buffer(2)]]
) {
    VertexOut out;
    out.position = vertexIn.clipPosition;
    out.texCoord = (vertexIn.texCoord * combinerUniforms.textureScale) + combinerUniforms.textureOffset;
    out.color = evaluateShadeColor(
        vertexIn.shadeData,
        frameUniforms,
        combinerUniforms.geometryMode
    );
    out.fog = computeFogFactor(vertexIn.clipPosition, frameUniforms.fogParameters);
    return out;
}

vertex VertexOut oot_xray_debug_vertex(
    XRayDebugVertexIn vertexIn [[stage_in]],
    constant FrameUniforms& frameUniforms [[buffer(1)]]
) {
    VertexOut out;
    out.position = frameUniforms.mvp * float4(vertexIn.position, 1.0);
    out.texCoord = float2(0.0);
    out.color = vertexIn.color;
    out.fog = 1.0;
    return out;
}

fragment float4 oot_flat_color_fragment(VertexOut in [[stage_in]]) {
    return in.color;
}

constant uint kCombinerCombined = 0;
constant uint kCombinerTexel0 = 1;
constant uint kCombinerTexel1 = 2;
constant uint kCombinerPrimitive = 3;
constant uint kCombinerShade = 4;
constant uint kCombinerEnvironment = 5;
constant uint kCombinerOne = 6;
constant uint kCombinerNoise = 7;
constant uint kCombinerZero = 31;
constant uint kAlphaCompareThreshold = 1;
float combinerNoise(float2 samplePoint) {
    return fract(sin(dot(samplePoint, float2(12.9898, 78.233))) * 43758.5453);
}

float4 combinerSource(
    uint selector,
    float4 texel0,
    float4 texel1,
    float4 primitiveColor,
    float4 environmentColor,
    float4 shadeColor,
    float4 combinedColor,
    float4 noiseColor
) {
    switch (selector) {
    case kCombinerCombined:
        return combinedColor;
    case kCombinerTexel0:
        return texel0;
    case kCombinerTexel1:
        return texel1;
    case kCombinerPrimitive:
        return primitiveColor;
    case kCombinerShade:
        return shadeColor;
    case kCombinerEnvironment:
        return environmentColor;
    case kCombinerOne:
        return 1.0;
    case kCombinerNoise:
        return noiseColor;
    case kCombinerZero:
        return 0.0;
    default:
        return 0.0;
    }
}

float combinerAlphaSource(
    uint selector,
    float texel0,
    float texel1,
    float primitiveColor,
    float environmentColor,
    float shadeColor,
    float combinedColor,
    float noiseValue
) {
    switch (selector) {
    case kCombinerCombined:
        return combinedColor;
    case kCombinerTexel0:
        return texel0;
    case kCombinerTexel1:
        return texel1;
    case kCombinerPrimitive:
        return primitiveColor;
    case kCombinerShade:
        return shadeColor;
    case kCombinerEnvironment:
        return environmentColor;
    case kCombinerOne:
        return 1.0;
    case kCombinerNoise:
        return noiseValue;
    case kCombinerZero:
        return 0.0;
    default:
        return 0.0;
    }
}

float4 evaluateColorCycle(
    uint4 selectors,
    float4 texel0,
    float4 texel1,
    float4 primitiveColor,
    float4 environmentColor,
    float4 shadeColor,
    float4 combinedColor,
    float4 noiseColor
) {
    float4 a = combinerSource(
        selectors.x,
        texel0,
        texel1,
        primitiveColor,
        environmentColor,
        shadeColor,
        combinedColor,
        noiseColor
    );
    float4 b = combinerSource(
        selectors.y,
        texel0,
        texel1,
        primitiveColor,
        environmentColor,
        shadeColor,
        combinedColor,
        noiseColor
    );
    float4 c = combinerSource(
        selectors.z,
        texel0,
        texel1,
        primitiveColor,
        environmentColor,
        shadeColor,
        combinedColor,
        noiseColor
    );
    float4 d = combinerSource(
        selectors.w,
        texel0,
        texel1,
        primitiveColor,
        environmentColor,
        shadeColor,
        combinedColor,
        noiseColor
    );
    return clamp((a - b) * c + d, 0.0, 1.0);
}

float evaluateAlphaCycle(
    uint4 selectors,
    float texel0,
    float texel1,
    float primitiveColor,
    float environmentColor,
    float shadeColor,
    float combinedColor,
    float noiseValue
) {
    float a = combinerAlphaSource(
        selectors.x,
        texel0,
        texel1,
        primitiveColor,
        environmentColor,
        shadeColor,
        combinedColor,
        noiseValue
    );
    float b = combinerAlphaSource(
        selectors.y,
        texel0,
        texel1,
        primitiveColor,
        environmentColor,
        shadeColor,
        combinedColor,
        noiseValue
    );
    float c = combinerAlphaSource(
        selectors.z,
        texel0,
        texel1,
        primitiveColor,
        environmentColor,
        shadeColor,
        combinedColor,
        noiseValue
    );
    float d = combinerAlphaSource(
        selectors.w,
        texel0,
        texel1,
        primitiveColor,
        environmentColor,
        shadeColor,
        combinedColor,
        noiseValue
    );
    return clamp((a - b) * c + d, 0.0, 1.0);
}

float wrappedTexelCoordinate(
    float coordinate,
    float tileSpan,
    uint clampMode,
    uint mirrorMode
) {
    float safeSpan = max(tileSpan, 1.0);
    float maxCoordinate = max(safeSpan - 1.0, 0.0);

    if (clampMode != 0u) {
        return clamp(coordinate, 0.0, maxCoordinate);
    }

    if (mirrorMode != 0u) {
        float period = safeSpan * 2.0;
        float mirrored = fmod(coordinate, period);
        if (mirrored < 0.0) {
            mirrored += period;
        }
        if (mirrored >= safeSpan) {
            mirrored = period - mirrored - 1.0;
        }
        return clamp(mirrored, 0.0, maxCoordinate);
    }

    float wrapped = fmod(coordinate, safeSpan);
    if (wrapped < 0.0) {
        wrapped += safeSpan;
    }
    return clamp(wrapped, 0.0, maxCoordinate);
}

float2 normalizedTextureCoordinate(
    float2 texelCoordinate,
    constant CombinerUniforms& combinerUniforms
) {
    float wrappedS = wrappedTexelCoordinate(
        texelCoordinate.x,
        combinerUniforms.textureTileSpan.x,
        combinerUniforms.textureClamp.x,
        combinerUniforms.textureMirror.x
    );
    float wrappedT = wrappedTexelCoordinate(
        texelCoordinate.y,
        combinerUniforms.textureTileSpan.y,
        combinerUniforms.textureClamp.y,
        combinerUniforms.textureMirror.y
    );
    float2 dimensions = max(combinerUniforms.textureDimensions, float2(1.0));
    return (float2(wrappedS, wrappedT) + 0.5) / dimensions;
}

fragment float4 oot_combiner_fragment(
    VertexOut in [[stage_in]],
    constant FrameUniforms& frameUniforms [[buffer(1)]],
    constant CombinerUniforms& combinerUniforms [[buffer(2)]],
    texture2d<half> texel0Texture [[texture(0)]],
    texture2d<half> texel1Texture [[texture(1)]]
) {
    constexpr sampler textureSampler(coord::normalized, address::clamp_to_edge, filter::nearest);

    float2 sampleCoordinate = normalizedTextureCoordinate(in.texCoord, combinerUniforms);
    float4 texel0 = float4(texel0Texture.sample(textureSampler, sampleCoordinate));
    float4 texel1 = float4(texel1Texture.sample(textureSampler, sampleCoordinate));
    float noiseValue = combinerNoise(in.position.xy + in.texCoord);
    float4 noiseColor = float4(noiseValue);

    float4 cycle1Color = evaluateColorCycle(
        combinerUniforms.cycle1ColorSelectors,
        texel0,
        texel1,
        combinerUniforms.primitiveColor,
        combinerUniforms.environmentColor,
        in.color,
        0.0,
        noiseColor
    );
    float cycle1Alpha = evaluateAlphaCycle(
        combinerUniforms.cycle1AlphaSelectors,
        texel0.a,
        texel1.a,
        combinerUniforms.primitiveColor.a,
        combinerUniforms.environmentColor.a,
        in.color.a,
        0.0,
        noiseValue
    );
    float4 cycle1Output = float4(cycle1Color.rgb, cycle1Alpha);

    float4 cycle2Color = evaluateColorCycle(
        combinerUniforms.cycle2ColorSelectors,
        texel0,
        texel1,
        combinerUniforms.primitiveColor,
        combinerUniforms.environmentColor,
        in.color,
        cycle1Output,
        noiseColor
    );
    float cycle2Alpha = evaluateAlphaCycle(
        combinerUniforms.cycle2AlphaSelectors,
        texel0.a,
        texel1.a,
        combinerUniforms.primitiveColor.a,
        combinerUniforms.environmentColor.a,
        in.color.a,
        cycle1Output.a,
        noiseValue
    );

    float4 finalColor = clamp(float4(cycle2Color.rgb, cycle2Alpha), 0.0, 1.0);

    if (
        combinerUniforms.alphaCompareMode == kAlphaCompareThreshold &&
        finalColor.a < combinerUniforms.alphaCompareThreshold
    ) {
        discard_fragment();
    }

    if ((combinerUniforms.geometryMode & kGeometryModeFog) != 0u) {
        float fogBlend = clamp(1.0 - in.fog, 0.0, 1.0);
        finalColor.rgb = mix(finalColor.rgb, combinerUniforms.fogColor.rgb, fogBlend);
    }

    return finalColor;
}
