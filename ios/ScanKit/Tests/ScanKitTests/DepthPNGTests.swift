import XCTest
import CoreGraphics
import ImageIO
@testable import ScanKit

final class DepthPNGTests: XCTestCase {
    func testMetersToMillimetersClampsInvalidValues() {
        XCTAssertEqual(DepthPNG.millimeters(fromMeters: [1.234, .nan, -1, 70]), [1234, 0, 0, 65535])
    }

    func testSixteenBitRoundTrip() throws {
        let px: [UInt16] = [0, 1, 1000, 65535, 2, 3, 4, 5, 300, 400, 500, 600]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try DepthPNG.write16(px, width: 4, height: 3, to: url)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 4)
        XCTAssertEqual(image.height, 3)
        XCTAssertEqual(image.bitsPerComponent, 16)

        var out = [UInt16](repeating: 0, count: 12)
        let ctx = try XCTUnwrap(out.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: 4, height: 3, bitsPerComponent: 16, bytesPerRow: 8,
                      space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
        })
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 4, height: 3))
        XCTAssertEqual(out, px)
    }

    func testEightBitWrite() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try DepthPNG.write8([0, 1, 2, 2, 1, 0], width: 3, height: 2, to: url)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.bitsPerComponent, 8)
        XCTAssertEqual(image.width, 3)
    }
}
