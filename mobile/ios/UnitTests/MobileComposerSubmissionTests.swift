import XCTest

private final class ComposerURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> [String: Any])?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "composer.example" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let data = try JSONSerialization.data(withJSONObject: handler(request))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class MobileComposerSubmissionTests: XCTestCase {
    private var session: URLSession!
    private var transport: MobileComposerTransport!
    override func setUp() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ComposerURLProtocol.self]
        session = URLSession(configuration: configuration)
        transport = MobileComposerTransport(session: session, origin: URL(string: "https://composer.example")!)
    }
    override func tearDown() async throws {
        session.invalidateAndCancel()
        ComposerURLProtocol.handler = nil
        session = nil
        transport = nil
    }

    func testFileReceiptAndPhotoReachThePromptInSelectionOrder() async throws {
        var paths: [String] = []
        ComposerURLProtocol.handler = { request in
            paths.append(request.url!.path)
            if request.url!.path.hasSuffix("uploadFileBinary") {
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                XCTAssertEqual(query.first { $0.name == "sessionId" }?.value, "session-one")
                XCTAssertEqual(query.first { $0.name == "name" }?.value, "测试 & notes.txt")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
                XCTAssertEqual(try Self.bodyData(request), Data("hello".utf8))
                return ["ok": true, "value": ["receiptId": "receipt-one"]]
            }
            let args = try Self.arguments(request)
            let prompt = args["request"] as! [String: Any]
            XCTAssertEqual(prompt["sessionId"] as? String, "session-one")
            let content = prompt["content"] as! [[String: Any]]
            XCTAssertEqual(content.map { $0["type"] as! String }, ["file", "image", "text"])
            XCTAssertEqual(content[0]["receiptId"] as? String, "receipt-one")
            XCTAssertEqual(content[1]["data"] as? String, Data([1, 2, 3]).base64EncodedString())
            XCTAssertEqual(content[2]["text"] as? String, "检查附件")
            XCTAssertEqual(prompt["requestId"] as? String, "request-one")
            return ["result": ["ok": true, "value": [:]]]
        }
        try await transport.submit(text: "检查附件", attachments: [
            MobileDraftAttachment(name: "测试 & notes.txt", data: Data("hello".utf8), image: false),
            MobileDraftAttachment(name: "photo.jpg", data: Data([1, 2, 3]), image: true)
        ], mode: .message, sessionId: "session-one", requestId: "request-one")
        XCTAssertEqual(paths, ["/api/session/uploadFileBinary", "/api/session/prompt"])
    }

    func testPlanAndGoalUseCommandsWithAttachments() async throws {
        var lines: [String] = []
        ComposerURLProtocol.handler = { request in
            XCTAssertEqual(request.url!.path, "/api/commands/execute")
            let args = try Self.arguments(request)
            XCTAssertEqual(args["agentId"] as? String, "session-one")
            lines.append(args["line"] as! String)
            let attachments = args["submittedAttachments"] as! [[String: Any]]
            XCTAssertEqual(attachments.count, 1)
            XCTAssertEqual(attachments[0]["type"] as? String, "image")
            return ["result": ["ok": true, "value": ["result": ["kind": "success"]]]]
        }
        for mode in [MobileComposerMode.plan, .goal] {
            try await transport.submit(text: "检查附件", attachments: [
                MobileDraftAttachment(name: "photo.jpg", data: Data([1]), image: true)
            ], mode: mode, sessionId: "session-one", requestId: UUID().uuidString)
        }
        XCTAssertEqual(lines, ["/plan 检查附件", "/goal 检查附件"])
    }

    func testRejectedCommandAndUploadDoNotFallThroughToPrompt() async throws {
        var calls = 0
        ComposerURLProtocol.handler = { _ in
            calls += 1
            return ["result": ["ok": true, "value": ["result": ["kind": "error", "text": "command unavailable"]]]]
        }
        do {
            try await transport.submit(text: "检查", attachments: [], mode: .plan, sessionId: "one", requestId: UUID().uuidString)
            XCTFail("A rejected command must fail the submission")
        } catch { XCTAssertEqual(error.localizedDescription, "command unavailable") }
        XCTAssertEqual(calls, 1)
        ComposerURLProtocol.handler = { request in
            XCTAssertTrue(request.url!.path.hasSuffix("uploadFileBinary"))
            return ["ok": false, "error": ["code": "failed"]]
        }
        do {
            try await transport.submit(text: "检查", attachments: [
                MobileDraftAttachment(name: "a.txt", data: Data([1]), image: false)
            ], mode: .message, sessionId: "one", requestId: UUID().uuidString)
            XCTFail("A rejected upload must stop the submission")
        } catch { XCTAssertTrue(error.localizedDescription.contains("附件已保留")) }
    }

    func testModeSelectionCannotExecuteControlTextAsAnObjective() async throws {
        ComposerURLProtocol.handler = { _ in
            XCTFail("Invalid mode input must be rejected before any upload or command")
            return [:]
        }
        for (mode, text) in [(MobileComposerMode.goal, "clear"), (.goal, "pause"), (.goal, "edit objective"),
                             (.goal, ""), (.plan, "off")] {
            do {
                try await transport.submit(text: text, attachments: [], mode: mode, sessionId: "one",
                                           requestId: UUID().uuidString)
                XCTFail("Control text must not run through the objective composer")
            } catch { XCTAssertTrue(error is MobileComposerFailure) }
        }
    }

    private static func bodyData(_ request: URLRequest) throws -> Data {
        let data: Data
        if let body = request.httpBody { data = body }
        else {
            let stream = try XCTUnwrap(request.httpBodyStream)
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            data = body
        }
        return data
    }

    private static func arguments(_ request: URLRequest) throws -> [String: Any] {
        let body = try JSONSerialization.jsonObject(with: bodyData(request)) as! [String: Any]
        return (body["payload"] as! [String: Any])["args"] as! [String: Any]
    }
}
