import Foundation

/// ITU-T G.711 µ-law / A-law codecs (Sun Microsystems reference implementation port).
enum G711 {

    // MARK: µ-law

    static func ulawEncode(_ samples: [Float]) -> Data {
        var out = Data(capacity: samples.count)
        for s in samples {
            out.append(ulawEncode(linear: Int32(clamping: Int(s * 32768.0))))
        }
        return out
    }

    static func ulawDecode(_ data: Data) -> [Float] {
        data.map { Float(ulawDecode($0)) / 32768.0 }
    }

    static func ulawEncode(linear: Int32) -> UInt8 {
        var v = linear >> 2
        let mask: UInt8 = v < 0 ? 0x7F : 0xFF
        if v < 0 { v = -v }
        if v > 8159 { v = 8159 }

        let segEnds: [Int32] = [0x3F, 0x7F, 0xFF, 0x1FF, 0x3FF, 0x7FF, 0xFFF, 0x1FFF]
        var seg = 0
        while seg < 7 && v > segEnds[seg] { seg += 1 }

        let uval = UInt8(truncatingIfNeeded: (seg << 4) | Int((v >> Int32(seg + 1)) & 0x0F))
        return uval ^ mask
    }

    static func ulawDecode(_ u: UInt8) -> Int16 {
        let uval: UInt8 = ~u
        let seg = Int32((uval & 0x70) >> 4)
        var t = (Int32(uval & 0x0F) << 3) + 132
        t <<= seg
        let lin = (uval & 0x80) != 0 ? (132 - t) : (t - 132)
        return Int16(clamping: lin)
    }

    // MARK: A-law

    static func alawEncode(_ samples: [Float]) -> Data {
        var out = Data(capacity: samples.count)
        for s in samples {
            out.append(alawEncode(linear: Int32(clamping: Int(s * 32768.0))))
        }
        return out
    }

    static func alawDecode(_ data: Data) -> [Float] {
        data.map { Float(alawDecode($0)) / 32768.0 }
    }

    static func alawEncode(linear: Int32) -> UInt8 {
        var v = linear >> 3
        var mask: UInt8 = 0xD5
        if v < 0 {
            mask = 0x55
            v = -v - 1
        }
        if v > 8159 { v = 8159 }

        let segEnds: [Int32] = [0x1F, 0x3F, 0x7F, 0xFF, 0x1FF, 0x3FF, 0x7FF, 0xFFF]
        var seg = 0
        while seg < 7 && v > segEnds[seg] { seg += 1 }

        var aval = UInt8(seg << 4)
        if seg < 2 {
            aval |= UInt8(truncatingIfNeeded: (v >> 1) & 0x0F)
        } else {
            aval |= UInt8(truncatingIfNeeded: (v >> Int32(seg)) & 0x0F)
        }
        return aval ^ mask
    }

    static func alawDecode(_ a: UInt8) -> Int16 {
        let v: UInt8 = a ^ 0x55
        var t = Int32(v & 0x0F) << 4
        let seg = Int32((v & 0x70) >> 4)
        if seg == 0 {
            t += 8
        } else if seg == 1 {
            t += 0x108
        } else {
            t += 0x108
            t <<= (seg - 1)
        }
        let lin = (v & 0x80) != 0 ? t : -t
        return Int16(clamping: lin)
    }
}
