import XCTest
import CBenchIO

final class CBenchIOTests: XCTestCase {
    
    var tempFile: String!
    
    override func setUp() {
        super.setUp()
        let tempDir = NSTemporaryDirectory()
        tempFile = (tempDir as NSString).appendingPathComponent(UUID().uuidString + ".tmp")
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempFile)
        super.tearDown()
    }
    
    func testPrepareFileAndNotAllZeros() {
        let ctx = cbench_ctx_create()
        defer { cbench_ctx_destroy(ctx) }
        
        let size: UInt64 = 16 * 1024 * 1024 // 16 MiB
        let err = cbench_prepare_file(ctx, tempFile, size)
        XCTAssertEqual(err, 0)
        
        var st = stat()
        XCTAssertEqual(stat(tempFile, &st), 0)
        XCTAssertEqual(UInt64(st.st_size), size)
        XCTAssertTrue(UInt64(st.st_blocks) * 512 >= size, "Fichier ne doit pas être creux")
        
        let handle = FileHandle(forReadingAtPath: tempFile)!
        let data = handle.readData(ofLength: 4096)
        handle.closeFile()
        
        XCTAssertEqual(data.count, 4096)
        let zeros = Data(repeating: 0, count: 4096)
        XCTAssertNotEqual(data, zeros, "Fichier ne doit pas être rempli de zéros")
    }
    
    func testRunPassSeqReadQD1() {
        let ctx = cbench_ctx_create()
        defer { cbench_ctx_destroy(ctx) }
        
        let size: UInt64 = 16 * 1024 * 1024
        cbench_prepare_file(ctx, tempFile, size)
        
        var params = cbench_params(
            pattern: CBENCH_SEQ,
            direction: CBENCH_READ,
            block_size: 1048576,
            queue_depth: 1,
            file_size: size,
            max_seconds: 0.3,
            max_bytes: 0
        )
        
        var result = cbench_result()
        let err = cbench_run_pass(ctx, tempFile, &params, &result, nil, 0, nil)
        
        XCTAssertEqual(err, 0)
        XCTAssertEqual(result.error, 0)
        XCTAssertTrue(result.bytes > 0)
        XCTAssertTrue(result.ios > 0)
    }
    
    func testRunPassSeqWriteQD8() {
        let ctx = cbench_ctx_create()
        defer { cbench_ctx_destroy(ctx) }
        
        let size: UInt64 = 16 * 1024 * 1024
        cbench_prepare_file(ctx, tempFile, size)
        
        var params = cbench_params(
            pattern: CBENCH_SEQ,
            direction: CBENCH_WRITE,
            block_size: 1048576,
            queue_depth: 8,
            file_size: size,
            max_seconds: 0,
            max_bytes: 0
        )
        
        var result = cbench_result()
        let err = cbench_run_pass(ctx, tempFile, &params, &result, nil, 0, nil)
        
        XCTAssertEqual(err, 0)
        XCTAssertEqual(result.error, 0)
        XCTAssertEqual(result.bytes, size, "Passe d'écriture séquentielle doit correspondre exactement à file_size")
    }
    
    func testRunPassRndQD1WithLatencies() {
        let ctx = cbench_ctx_create()
        defer { cbench_ctx_destroy(ctx) }
        
        let size: UInt64 = 16 * 1024 * 1024
        cbench_prepare_file(ctx, tempFile, size)
        
        var params = cbench_params(
            pattern: CBENCH_RND,
            direction: CBENCH_READ,
            block_size: 4096,
            queue_depth: 1,
            file_size: size,
            max_seconds: 0.1, // Court
            max_bytes: 0
        )
        
        var result = cbench_result()
        var latencies = [UInt64](repeating: 0, count: 1000)
        var latenciesCount: UInt64 = 0
        
        let err = cbench_run_pass(ctx, tempFile, &params, &result, &latencies, UInt64(latencies.count), &latenciesCount)
        
        XCTAssertEqual(err, 0)
        XCTAssertEqual(result.error, 0)
        XCTAssertEqual(latenciesCount, result.ios, "Latencies count should equal ios")
    }
    
    func testCancellation() {
        let ctx = cbench_ctx_create()
        defer { cbench_ctx_destroy(ctx) }
        
        let size: UInt64 = 16 * 1024 * 1024
        cbench_prepare_file(ctx, tempFile, size)
        
        var params = cbench_params(
            pattern: CBENCH_SEQ,
            direction: CBENCH_READ,
            block_size: 1048576,
            queue_depth: 4,
            file_size: size,
            max_seconds: 5.0, // Should be cancelled long before this
            max_bytes: 0
        )
        
        var result = cbench_result()
        
        let start = Date()
        
        struct SafeCtx: @unchecked Sendable { let ptr: OpaquePointer? }
        let safeCtx = SafeCtx(ptr: ctx)
        let bgThread = Thread {
            Thread.sleep(forTimeInterval: 0.05)
            cbench_ctx_cancel(safeCtx.ptr)
        }
        bgThread.start()
        
        let err = cbench_run_pass(ctx, tempFile, &params, &result, nil, 0, nil)
        let elapsed = Date().timeIntervalSince(start)
        
        XCTAssertEqual(err, -100)
        XCTAssertEqual(result.error, -100)
        XCTAssertLessThan(elapsed, 1.0, "Doit retourner en moins d'une seconde")
    }
}
