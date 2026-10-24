import CoreGraphics
import Foundation
import ImageIO

public enum DepthPNGError: Error {
    case encodeFailed
}

/// Lossless grayscale PNGs for depth (16-bit millimeters) and confidence (8-bit) maps.
public enum DepthPNG {
    /// Meters to millimeters; NaN, infinite and non-positive depths become 0, and the result saturates at 65535.
    public static func millimeters(fromMeters meters: [Float]) -> [UInt16] {
        meters.map { m in
            guard m.isFinite, m > 0 else { return 0 }
            return UInt16(min(65535, (m * 1000).rounded()))
        }
    }

    public static func write16(_ px: [UInt16], width: Int, height: Int, to url: URL) throws {
        let bytes = px.flatMap { v -> [UInt8] in [UInt8(v & 0xFF), UInt8(v >> 8)] }
        try write(bytes, width: width, height: height, bitsPerComponent: 16,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Little.rawValue),
                  to: url)
    }

    public static func write8(_ px: [UInt8], width: Int, height: Int, to url: URL) throws {
        try write(px, width: width, height: height, bitsPerComponent: 8,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), to: url)
    }

    private static func write(_ bytes: [UInt8], width: Int, height: Int, bitsPerComponent: Int,
                              bitmapInfo: CGBitmapInfo, to url: URL) throws {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: bitsPerComponent,
                                  bitsPerPixel: bitsPerComponent, bytesPerRow: width * bitsPerComponent / 8,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: bitmapInfo, provider: provider,
                                  decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { throw DepthPNGError.encodeFailed }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw DepthPNGError.encodeFailed }
    }
}
