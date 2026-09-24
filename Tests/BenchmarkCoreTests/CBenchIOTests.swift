import Testing
import Foundation
import CBenchIO

@Suite final class CBenchIOTests {
    
    var tempFile: String!
    
    init() {
        let tempDir = NSTemporaryDirectory()
        tempFile = (tempDir as NSString).appendingPathComponent(UUID().uuidString + ".tmp")
    }
    
    deinit {
        try? FileManager.default.removeItem(atPath: tempFile)
    }
    
    @Test func testPrepareFileAndNotAllZeros() {
        let ctx = cbench_ctx_create()
        defer { cbench_ctx_destroy(ctx) }
        
        let size: UInt64 = 16 * 1024 * 1024 // 16 MiB
        let err = cbench_prepare_file(ctx, tempFile, size)
        #expect(err == 0)
        
        var st = stat()
        #expect(stat(tempFile, &st) == 0)
        #expect(UInt64(st.st_size) == size)
        #expect(UInt64(st.st_blocks) * 512 >= size, "File must not be sparse")
        
        let handle = FileHandle(forReadingAtPath: tempFile)!
        let data = handle.readData(ofLength: 4096)
        handle.closeFile()
        
        #expect(data.count == 4096)
        let zeros = Data(repeating: 0, count: 4096)
        #expect(data != zeros, "File must not be filled with zeros")
    }
    
    @Test func testRunPassSeqReadQD1() {
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
        
        #expect(err == 0)
        #expect(result.error == 0)
        #expect(result.bytes > 0)
        #expect(result.ios > 0)
    }
    
    @Test func testRunPassSeqWriteQD8() {
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
        
        #expect(err == 0)
        #expect(result.error == 0)
        #expect(result.bytes == size, "Sequential write pass must match file_size exactly")
    }
    
    @Test func testRunPassRndQD1WithLatencies() {
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
            max_seconds: 0.1, // Short
            max_bytes: 0
        )
        
        var result = cbench_result()
        var latencies = [UInt64](repeating: 0, count: 1000)
        var latenciesCount: UInt64 = 0
        
        let err = cbench_run_pass(ctx, tempFile, &params, &result, &latencies, UInt64(latencies.count), &latenciesCount)
        
        #expect(err == 0)
        #expect(result.error == 0)
        #expect(latenciesCount == result.ios, "Latencies count should equal ios")
    }
    
    @Test func testCancellation() {
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
        
        #expect(err == -100)
        #expect(result.error == -100)
        #expect(elapsed < 1.0, "Must return in less than a second")
    }
}
