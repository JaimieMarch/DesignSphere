import Foundation
import Compression

enum XRCompression {
    static func compress(_ data: Data, algorithm: compression_algorithm = COMPRESSION_LZFSE) -> Data {
        guard !data.isEmpty else { return data }
        return data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Data in
            let dstBufferSize = max(64, data.count / 2)
            var dstData = Data(count: dstBufferSize)
            let compressedCount: Int = dstData.withUnsafeMutableBytes { dst in
                let srcPtr = src.bindMemory(to: UInt8.self).baseAddress!
                let dstPtr = dst.bindMemory(to: UInt8.self).baseAddress!
                return compression_encode_buffer(
                    dstPtr,
                    dstBufferSize,
                    srcPtr,
                    data.count,
                    nil,
                    algorithm
                )
            }
            if compressedCount == 0 { return data } // compression failed or expanded
            dstData.removeSubrange(compressedCount..<dstData.count)
            return dstData
        }
    }

    static func decompress(_ data: Data, originalCapacityHint: Int = 128 * 1024, algorithm: compression_algorithm = COMPRESSION_LZFSE) -> Data? {
        guard !data.isEmpty else { return data }
        let dstCapacity = max(64, originalCapacityHint)
        var result = Data(count: dstCapacity)
        var decompressedSize = 0
        let status: Bool = result.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                let srcPtr = src.bindMemory(to: UInt8.self).baseAddress!
                let dstPtr = dst.bindMemory(to: UInt8.self).baseAddress!
                decompressedSize = compression_decode_buffer(
                    dstPtr,
                    dstCapacity,
                    srcPtr,
                    data.count,
                    nil,
                    algorithm
                )
                return decompressedSize > 0
            }
        }
        if !status { return nil }
        result.removeSubrange(decompressedSize..<result.count)
        return result
    }
}
