import Foundation
import OOTDataModel
import XCTest
import simd
@testable import OOTRender

final class RSPStateTests: XCTestCase {
    func testMatrixStackPushPopLoadAndMultiplyProduceExpectedMatrices() throws {
        var state = RSPState()
        let translation = makeTranslationMatrix(x: 2, y: 3, z: 4)
        let scale = makeScaleMatrix(x: 5, y: 6, z: 7)

        state.loadMatrix(translation)
        try state.pushMatrix()
        state.multiplyMatrix(by: scale)

        XCTAssertEqual(state.matrixStack.depth, 2)
        assertMatrixEqual(state.currentMatrix, simd_mul(translation, scale))

        let poppedMatrix = try state.popMatrix()

        assertMatrixEqual(poppedMatrix, simd_mul(translation, scale))
        assertMatrixEqual(state.currentMatrix, translation)
        XCTAssertEqual(state.matrixStack.depth, 1)
    }

    func testVertexBufferLoadAndReadUsesRequestedSlots() throws {
        var state = RSPState()
        let vertex = TransformedVertex(
            clipPosition: SIMD4<Float>(1, 2, 3, 1),
            textureCoordinates: SIMD2<Float>(0.25, 0.75),
            color: SIMD4<Float>(1, 0.5, 0.25, 1)
        )
        let secondVertex = TransformedVertex(
            clipPosition: SIMD4<Float>(4, 5, 6, 1),
            textureCoordinates: SIMD2<Float>(0.5, 0.125),
            color: SIMD4<Float>(0.25, 0.75, 1, 1)
        )

        try state.loadVertex(vertex, at: 7)
        try state.loadVertices([secondVertex], startingAt: 12)

        XCTAssertEqual(try state.vertex(at: 7), vertex)
        XCTAssertEqual(try state.vertex(at: 12), secondVertex)
        XCTAssertNil(try state.vertex(at: 6))
    }

    func testGeometryModeSetAndClearManipulateBits() {
        var state = RSPState()

        state.setGeometryMode([.lighting, .fog, .cull])
        XCTAssertTrue(state.geometryMode.contains(.lighting))
        XCTAssertTrue(state.geometryMode.contains(.fog))
        XCTAssertTrue(state.geometryMode.contains(.cullFront))
        XCTAssertTrue(state.geometryMode.contains(.cullBack))

        state.clearGeometryMode([.fog, .cullFront])
        XCTAssertFalse(state.geometryMode.contains(.fog))
        XCTAssertFalse(state.geometryMode.contains(.cullFront))
        XCTAssertTrue(state.geometryMode.contains(.cullBack))

        state.applyGeometryMode(
            clearBits: GeometryMode.cullBack.rawValue,
            setBits: GeometryMode.zBuffer.rawValue | GeometryMode.smoothShading.rawValue
        )

        XCTAssertFalse(state.geometryMode.contains(.cullBack))
        XCTAssertTrue(state.geometryMode.contains(.lighting))
        XCTAssertTrue(state.geometryMode.contains(.zBuffer))
        XCTAssertTrue(state.geometryMode.contains(.smoothShading))
    }
}

final class RDPStateTests: XCTestCase {
    func testCombineModeStoresCycleSelectors() {
        var state = RDPState()
        let combineMode = RDPCombineState(
            firstCycle: RDPCombineCycle(
                color: RDPCombineSelectorGroup(a: 1, b: 2, c: 3, d: 4),
                alpha: RDPCombineSelectorGroup(a: 5, b: 6, c: 7, d: 8)
            ),
            secondCycle: RDPCombineCycle(
                color: RDPCombineSelectorGroup(a: 9, b: 10, c: 11, d: 12),
                alpha: RDPCombineSelectorGroup(a: 13, b: 14, c: 15, d: 16)
            )
        )

        state.setCombineMode(combineMode)

        XCTAssertEqual(state.combineMode, combineMode)
        XCTAssertEqual(state.combineMode.firstCycle.color.c, 3)
        XCTAssertEqual(state.combineMode.firstCycle.alpha.d, 8)
        XCTAssertEqual(state.combineMode.secondCycle.color.a, 9)
        XCTAssertEqual(state.combineMode.secondCycle.alpha.b, 14)
    }

    func testTileDescriptorConfigurationRoundTrips() throws {
        var state = RDPState()
        let descriptor = TileDescriptor(
            format: .ci8,
            texelSize: .bits8,
            line: 42,
            tmem: 128,
            tile: 3,
            palette: 7,
            clampS: true,
            mirrorS: false,
            maskS: 5,
            shiftS: 2,
            clampT: false,
            mirrorT: true,
            maskT: 4,
            shiftT: 1
        )

        try state.setTileDescriptor(descriptor)

        XCTAssertEqual(try state.tileDescriptor(at: 3), descriptor)
    }
}

final class SegmentTableTests: XCTestCase {
    func testSegmentTableStoresDataForSegmentIDs() throws {
        var table = SegmentTable()
        let textureData = Data([0x12, 0x34, 0x56, 0x78])

        try table.setSegment(0x0C, data: textureData)

        XCTAssertEqual(try table.data(for: 0x0C), textureData)
    }
}

private func assertMatrixEqual(
    _ lhs: simd_float4x4,
    _ rhs: simd_float4x4,
    accuracy: Float = 0.000_1,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    for column in 0..<4 {
        for row in 0..<4 {
            XCTAssertEqual(lhs[column, row], rhs[column, row], accuracy: accuracy, file: file, line: line)
        }
    }
}

private func makeTranslationMatrix(x: Float, y: Float, z: Float) -> simd_float4x4 {
    simd_float4x4(
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(x, y, z, 1)
    )
}

private func makeScaleMatrix(x: Float, y: Float, z: Float) -> simd_float4x4 {
    simd_float4x4(
        SIMD4<Float>(x, 0, 0, 0),
        SIMD4<Float>(0, y, 0, 0),
        SIMD4<Float>(0, 0, z, 0),
        SIMD4<Float>(0, 0, 0, 1)
    )
}
