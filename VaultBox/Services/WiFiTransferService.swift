import Foundation
import Network

// MARK: - TransferItemPayload

struct TransferItemPayload: Sendable, Codable {
    let id: String
    let filename: String
    let type: String
    let fileSize: Int64
    let createdAt: Date
}

// MARK: - WiFiTransferDelegate

@MainActor
protocol WiFiTransferDelegate: AnyObject, Sendable {
    func transferServiceDidReceiveFile(data: Data, filename: String, contentType: String) async throws
    func transferServiceNeedsItems() async throws -> [TransferItemPayload]
    func transferServiceNeedsDecryptedFile(itemID: String) async throws -> (Data, String, String)
    func transferServiceNeedsThumbnail(itemID: String) async throws -> Data
}

// MARK: - WiFiTransferService

actor WiFiTransferService {

    private var listener: NWListener?
    private var connections: [Int: NWConnection] = [:]
    private var connectionClients: [Int: String] = [:]
    private var recentClients: [String: Date] = [:]
    private var nextConnectionID = 0
    private var inactivityTask: Task<Void, Never>?
    private var clientCleanupTask: Task<Void, Never>?
    private static let clientPresenceSeconds: TimeInterval = 15

    private(set) var isRunning = false
    private(set) var connectedDeviceCount = 0
    private(set) var localIPAddress: String?

    var onStateChange: (@Sendable () -> Void)?
    weak var delegate: WiFiTransferDelegate?

    func setDelegate(_ delegate: WiFiTransferDelegate) {
        self.delegate = delegate
    }

    // MARK: - Start / Stop

    func start() throws {
        let params = NWParameters.tcp
        params.acceptLocalOnly = true

        let listener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: Constants.wifiTransferPort))

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task {
                await self.handleListenerState(state)
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task {
                await self.handleNewConnection(connection)
            }
        }

        self.listener = listener
        self.localIPAddress = Self.getWiFiAddress()
        listener.start(queue: .global(qos: .userInitiated))
        startClientCleanupTimer()

        isRunning = true
        notifyStateChange()
        resetInactivityTimer()
    }

    func stop() {
        inactivityTask?.cancel()
        inactivityTask = nil
        clientCleanupTask?.cancel()
        clientCleanupTask = nil

        for (_, connection) in connections {
            connection.cancel()
        }
        connections.removeAll()
        connectionClients.removeAll()
        recentClients.removeAll()

        listener?.cancel()
        listener = nil

        isRunning = false
        connectedDeviceCount = 0
        localIPAddress = nil
        notifyStateChange()
    }

    // MARK: - Listener State

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .failed:
            stop()
        case .cancelled:
            isRunning = false
            notifyStateChange()
        default:
            break
        }
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        let id = nextConnectionID
        nextConnectionID += 1
        connections[id] = connection
        connectionClients[id] = Self.clientIdentifier(for: connection)
        markClientSeen(forConnectionID: id)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task {
                await self.handleConnectionState(state, id: id)
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
        receiveData(on: connection, id: id)
    }

    private func handleConnectionState(_ state: NWConnection.State, id: Int) {
        switch state {
        case .failed, .cancelled:
            connections.removeValue(forKey: id)
            connectionClients.removeValue(forKey: id)
            buffers.removeValue(forKey: id)
            pruneInactiveClients()
        default:
            break
        }
    }

    private func receiveData(on connection: NWConnection, id: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            Task {
                var handledRequest = false
                if let data, !data.isEmpty {
                    handledRequest = await self.accumulateAndProcess(data: data, connection: connection, id: id)
                }

                if handledRequest {
                    return
                }

                if isComplete || error != nil {
                    await self.closeConnection(id: id)
                } else {
                    await self.receiveData(on: connection, id: id)
                }
            }
        }
    }

    private var buffers: [Int: Data] = [:]

    private func accumulateAndProcess(data: Data, connection: NWConnection, id: Int) async -> Bool {
        if buffers[id] == nil {
            buffers[id] = Data()
        }
        buffers[id]!.append(data)

        if buffers[id]!.count > Constants.wifiTransferMaxRequestBytes {
            buffers.removeValue(forKey: id)
            let response = HTTPResponse.error("Upload too large", code: 413)
            sendResponse(response, on: connection, id: id)
            return true
        }

        guard HTTPParser.isRequestComplete(buffers[id]!) else {
            return false
        }

        let requestData = buffers[id]!
        buffers.removeValue(forKey: id)
        markClientSeen(forConnectionID: id)

        guard let request = HTTPParser.parseRequest(from: requestData) else {
            let response = HTTPResponse.error("Bad Request", code: 400)
            sendResponse(response, on: connection, id: id)
            return true
        }

        if request.path != "/api/ping" {
            resetInactivityTimer()
        }

        let response = await handleRequest(request)
        sendResponse(response, on: connection, id: id)
        return true
    }

    private func sendResponse(_ response: HTTPResponse, on connection: NWConnection, id: Int) {
        let data = response.serialize()
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            Task {
                await self.closeConnection(id: id)
            }
        })
    }

    private func closeConnection(id: Int) {
        buffers.removeValue(forKey: id)
        if let connection = connections.removeValue(forKey: id) {
            connection.cancel()
        }
        connectionClients.removeValue(forKey: id)
        pruneInactiveClients()
    }

    // MARK: - HTTP Routing

    private func handleRequest(_ request: HTTPRequest) async -> HTTPResponse {
        let path = request.path
        let method = request.method.uppercased()

        if method == "GET" && path == "/" {
            return .ok(html: WiFiTransferHTML.mainPage)
        }

        if method == "GET" && path == "/api/items" {
            return await handleGetItems()
        }

        if method == "GET" && path == "/api/ping" {
            return .ok(json: Data("{\"ok\":true}".utf8))
        }

        if method == "GET" && path.hasPrefix("/download/") {
            let itemID = String(path.dropFirst("/download/".count))
            return await handleDownload(itemID: itemID)
        }

        if method == "GET" && path.hasPrefix("/thumbnail/") {
            let itemID = String(path.dropFirst("/thumbnail/".count))
            return await handleThumbnail(itemID: itemID)
        }

        if method == "POST" && path == "/upload" {
            return await handleUpload(request)
        }

        return .notFound()
    }

    private func handleGetItems() async -> HTTPResponse {
        guard let delegate else { return .error("Service unavailable", code: 500) }

        do {
            let items = try await delegate.transferServiceNeedsItems()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let json = try encoder.encode(items)
            return .ok(json: json)
        } catch {
            return .error("Failed to fetch items", code: 500)
        }
    }

    private func handleDownload(itemID: String) async -> HTTPResponse {
        guard let delegate else { return .error("Service unavailable", code: 500) }

        do {
            let (data, contentType, filename) = try await delegate.transferServiceNeedsDecryptedFile(itemID: itemID)
            return .ok(data: data, contentType: contentType, filename: filename)
        } catch {
            return .notFound()
        }
    }

    private func handleThumbnail(itemID: String) async -> HTTPResponse {
        guard let delegate else { return .error("Service unavailable", code: 500) }

        do {
            let data = try await delegate.transferServiceNeedsThumbnail(itemID: itemID)
            return HTTPResponse(
                statusCode: 200,
                headers: ["Content-Type": "image/jpeg"],
                body: data
            )
        } catch {
            return .notFound()
        }
    }

    private func handleUpload(_ request: HTTPRequest) async -> HTTPResponse {
        guard let delegate else { return .error("Service unavailable", code: 500) }
        guard let contentType = request.headers["Content-Type"] ?? request.headers["content-type"],
              let boundary = HTTPParser.extractBoundary(from: contentType) else {
            return .error("Missing multipart boundary", code: 400)
        }

        let files = HTTPParser.parseMultipartBody(request.body, boundary: boundary)
        guard !files.isEmpty else {
            return .error("No files in upload", code: 400)
        }

        var uploadedCount = 0
        for file in files {
            do {
                try await delegate.transferServiceDidReceiveFile(
                    data: file.data,
                    filename: file.filename,
                    contentType: file.contentType
                )
                uploadedCount += 1
            } catch {
                // Continue with remaining files
            }
        }

        let responseJSON = "{\"uploaded\": \(uploadedCount)}"
        return .ok(json: Data(responseJSON.utf8))
    }

    // MARK: - Inactivity Timer

    private func resetInactivityTimer() {
        inactivityTask?.cancel()
        inactivityTask = Task { [weak self] in
            let timeoutSeconds = UInt64(Constants.wifiTransferTimeoutMinutes) * 60
            try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)

            guard !Task.isCancelled else { return }
            await self?.stop()
        }
    }

    private func startClientCleanupTimer() {
        clientCleanupTask?.cancel()
        clientCleanupTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self.pruneInactiveClients()
            }
        }
    }

    private func markClientSeen(forConnectionID id: Int) {
        guard let client = connectionClients[id], !client.isEmpty else { return }
        recentClients[client] = Date()
        pruneInactiveClients()
    }

    private func pruneInactiveClients() {
        let cutoff = Date().addingTimeInterval(-Self.clientPresenceSeconds)
        recentClients = recentClients.filter { $0.value >= cutoff }
        let count = recentClients.count
        if connectedDeviceCount != count {
            connectedDeviceCount = count
            notifyStateChange()
        }
    }

    // MARK: - Wi-Fi Address

    static func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            guard addrFamily == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)
            guard name == "en0" else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil, 0,
                NI_NUMERICHOST
            )
            hostname.withUnsafeBufferPointer { buffer in
                let bytes = buffer.map { UInt8(bitPattern: $0) }
                let nullTermIdx = bytes.firstIndex(of: 0) ?? bytes.endIndex
                address = String(decoding: bytes[..<nullTermIdx], as: UTF8.self)
            }
        }

        return address
    }

    private static func clientIdentifier(for connection: NWConnection) -> String {
        switch connection.endpoint {
        case let .hostPort(host, _):
            return host.debugDescription
        default:
            return ""
        }
    }

    // MARK: - Notify

    private func notifyStateChange() {
        let callback = onStateChange
        callback?()
    }
}
