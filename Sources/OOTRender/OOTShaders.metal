#include <metal_stdlib>

using namespace metal;

struct RasterizerData {
    float4 position [[position]];
};

vertex RasterizerData oot_passthrough_vertex(uint vertexID [[vertex_id]]) {
    constexpr float2 positions[3] = {
        float2(-1.0, -1.0),
        float2(3.0, -1.0),
        float2(-1.0, 3.0),
    };

    RasterizerData out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    return out;
}

fragment float4 oot_solid_color_fragment() {
    return float4(45.0 / 255.0, 155.0 / 255.0, 52.0 / 255.0, 1.0);
}
