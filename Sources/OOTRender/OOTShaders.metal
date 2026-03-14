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
};

struct CombinerUniforms {
    float2 textureScale;
    float2 reserved;
};

struct N64VertexIn {
    short3 position [[attribute(0)]];
    short2 texCoord [[attribute(1)]];
    float4 color [[attribute(2)]];
};

vertex VertexOut oot_passthrough_vertex(
    N64VertexIn rawVertex [[stage_in]],
    constant FrameUniforms& frameUniforms [[buffer(1)]],
    constant CombinerUniforms& combinerUniforms [[buffer(2)]]
) {
    VertexIn vertexIn;
    vertexIn.position = float3(rawVertex.position);
    vertexIn.texCoord = float2(rawVertex.texCoord);
    vertexIn.color = rawVertex.color;
    vertexIn.normal = float3(0.0);

    float4 clipPosition = frameUniforms.mvp * float4(vertexIn.position, 1.0);
    float fogStart = frameUniforms.fogParameters.x;
    float fogEnd = max(frameUniforms.fogParameters.y, fogStart + 0.0001);
    float viewDistance = length(clipPosition.xyz / max(clipPosition.w, 0.0001));

    VertexOut out;
    out.position = clipPosition;
    out.texCoord = vertexIn.texCoord * combinerUniforms.textureScale;
    out.color = vertexIn.color;
    out.fog = clamp((fogEnd - viewDistance) / (fogEnd - fogStart), 0.0, 1.0);
    return out;
}

fragment float4 oot_flat_color_fragment(VertexOut in [[stage_in]]) {
    return in.color;
}
