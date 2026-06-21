import Compression
import XCTest
import simd
@testable import XRShareCollaboration

final class CompressionTests: XCTestCase {
    func testEmptyDataRoundTrips() {
        XCTAssertEqual(XRCompression.compress(Data()), Data())
        XCTAssertEqual(XRCompression.decompress(Data()), Data())
    }

    func testRepetitiveDataRoundTripsWithSupportedAlgorithms() throws {
        let original = Data(repeating: 0x41, count: 32_768)
        let algorithms = [COMPRESSION_LZFSE, COMPRESSION_LZ4, COMPRESSION_ZLIB, COMPRESSION_LZMA]

        for algorithm in algorithms {
            let compressed = XRCompression.compress(original, algorithm: algorithm)
            XCTAssertLessThan(compressed.count, original.count)
            XCTAssertEqual(
                XRCompression.decompress(
                    compressed,
                    originalCapacityHint: original.count,
                    algorithm: algorithm
                ),
                original
            )
        }
    }

    func testCompressionReturnsOriginalWhenOutputWouldNotFit() {
        let original = Data((0..<255).map(UInt8.init))
        XCTAssertEqual(XRCompression.compress(original), original)
    }

    func testInvalidCompressedDataFailsToDecode() {
        XCTAssertNil(XRCompression.decompress(Data([0x01, 0x02, 0x03]), algorithm: COMPRESSION_LZFSE))
    }
}

final class MatrixUtilitiesTests: XCTestCase {
    func testMatrixArrayRoundTripUsesColumnMajorOrder() {
        let values = (1...16).map(Float.init)
        let matrix = simd_float4x4.fromArray(values)
        XCTAssertEqual(matrix.toArray(), values)
    }

    func testPositionReadsTranslationColumn() {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4<Float>(2, -3, 4.5, 1)
        XCTAssertEqual(matrix.position, SIMD3<Float>(2, -3, 4.5))
    }

    func testShortArrayFallsBackToIdentity() {
        XCTAssertEqual(simd_float4x4.fromArray([1, 2, 3]).toArray(), matrix_identity_float4x4.toArray())
    }

    func testApproximateEqualityHonorsEpsilon() {
        var nearby = matrix_identity_float4x4
        nearby.columns.3.x = 0.0009
        XCTAssertTrue(XRShareCollaboration.simd_almost_equal_elements(matrix_identity_float4x4, nearby, 0.001))
        XCTAssertFalse(XRShareCollaboration.simd_almost_equal_elements(matrix_identity_float4x4, nearby, 0.0001))
    }

    func testAlertItemsHaveStableDistinctIdentity() {
        let first = AlertItem(title: "A", message: "One")
        let second = AlertItem(title: "A", message: "One")
        XCTAssertEqual(first.title, "A")
        XCTAssertEqual(first.message, "One")
        XCTAssertNotEqual(first.id, second.id)
    }
}
