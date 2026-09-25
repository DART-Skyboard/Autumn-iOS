import Foundation
import Compression

/// TF157: iOS has no built-in "create a .zip" API — Compression only does
/// raw stream (de)compression, not the container format. This builds a
/// real, standard ZIP file (local file header + central directory + end
/// record) with genuinely DEFLATE-compressed entries, so "zip it and
/// compress it" produces something any standard zip tool can open, not
/// just a renamed JSON file.
enum MiniZip {
    struct Entry { let name: String; let data: Data }

    static func write(entries: [Entry]) -> Data {
        var out = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let (compressed, method) = deflate(entry.data)
            let compSize = UInt32(compressed.count)
            let uncompSize = UInt32(entry.data.count)

            var local = Data()
            local.append(le32(0x04034b50))          // local file header signature
            local.append(le16(20))                   // version needed
            local.append(le16(0))                    // flags
            local.append(le16(method))               // compression method
            local.append(le16(0)); local.append(le16(0)) // mod time/date
            local.append(le32(crc))
            local.append(le32(compSize))
            local.append(le32(uncompSize))
            local.append(le16(UInt16(nameData.count)))
            local.append(le16(0))                    // extra field length
            local.append(nameData)
            local.append(compressed)
            out.append(local)

            var central = Data()
            central.append(le32(0x02014b50))         // central directory signature
            central.append(le16(20)); central.append(le16(20))
            central.append(le16(0))
            central.append(le16(method))
            central.append(le16(0)); central.append(le16(0))
            central.append(le32(crc))
            central.append(le32(compSize))
            central.append(le32(uncompSize))
            central.append(le16(UInt16(nameData.count)))
            central.append(le16(0)); central.append(le16(0)); central.append(le16(0)); central.append(le16(0))
            central.append(le32(0))
            central.append(le32(offset))
            central.append(nameData)
            centralDirectory.append(central)

            offset += UInt32(local.count)
        }

        let cdOffset = offset
        out.append(centralDirectory)

        var end = Data()
        end.append(le32(0x06054b50))
        end.append(le16(0)); end.append(le16(0))
        end.append(le16(UInt16(entries.count)))
        end.append(le16(UInt16(entries.count)))
        end.append(le32(UInt32(centralDirectory.count)))
        end.append(le32(cdOffset))
        end.append(le16(0))
        out.append(end)

        return out
    }

    /// Deflate via Compression framework; falls back to STORED (method 0)
    /// if compression somehow fails, so export never breaks over this —
    /// a slightly bigger valid zip beats no zip at all.
    private static func deflate(_ data: Data) -> (Data, UInt16) {
        guard !data.isEmpty else { return (data, 0) }
        let dstCapacity = data.count + (data.count / 2) + 64
        let compressed: Data? = data.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) -> Data? in
            guard let srcBase = srcPtr.bindMemory(to: UInt8.self).baseAddress else { return nil }
            var dst = [UInt8](repeating: 0, count: dstCapacity)
            let size = compression_encode_buffer(&dst, dstCapacity, srcBase, data.count, nil, COMPRESSION_ZLIB)
            guard size > 0 else { return nil }
            return Data(dst[0..<size])
        }
        if let compressed, compressed.count < data.count {
            return (compressed, 8)
        }
        return (data, 0)
    }

    private static func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    private static let crcTable: [UInt32] = {
        (0...255).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1 != 0) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
            return c
        }
    }()

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}
