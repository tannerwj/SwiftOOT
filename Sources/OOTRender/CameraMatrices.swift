import simd

struct CameraMatrices: Sendable, Equatable {
    let viewMatrix: simd_float4x4
    let projectionMatrix: simd_float4x4

    var viewProjectionMatrix: simd_float4x4 {
        projectionMatrix * viewMatrix
    }
}
