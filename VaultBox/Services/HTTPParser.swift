import Foundation

// MARK: - HTTPRequest

struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
    let queryParameters: [String: String]
}

// MARK: - HTTPResponse

struct HTTPResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data

    func serialize() -> Data {
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 404: statusText = "Not Found"
        case 400: statusText = "Bad Request"
        case 413: statusText = "Payload Too Large"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }

        var response = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        var allHeaders = headers
        allHeaders["Content-Length"] = "\(body.count)"
        if allHeaders["Connection"] == nil {
            allHeaders["Connection"] = "close"
        }

        for (key, value) in allHeaders.sorted(by: { $0.key < $1.key }) {
            response += "\(key): \(value)\r\n"
        }
        response += "\r\n"

        var data = Data(response.utf8)
        data.append(body)
        return data
    }

    static func ok(html: String) -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            headers: [
                "Content-Type": "text/html; charset=utf-8",
                "Cache-Control": "no-store"
            ],
            body: Data(html.utf8)
        )
    }

    static func ok(json: Data) -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: json
        )
    }

    static func ok(data: Data, contentType: String, filename: String) -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            headers: [
                "Content-Type": contentType,
                "Content-Disposition": "attachment; filename=\"\(filename)\""
            ],
            body: data
        )
    }

    static func notFound() -> HTTPResponse {
        HTTPResponse(
            statusCode: 404,
            headers: ["Content-Type": "text/plain"],
            body: Data("Not Found".utf8)
        )
    }

    static func error(_ message: String, code: Int = 500) -> HTTPResponse {
        HTTPResponse(
            statusCode: code,
            headers: ["Content-Type": "text/plain"],
            body: Data(message.utf8)
        )
    }
}

// MARK: - MultipartFile

struct MultipartFile: Sendable {
    let filename: String
    let contentType: String
    let data: Data
}

// MARK: - HTTPParser

enum HTTPParser {

    static func isRequestComplete(_ data: Data) -> Bool {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.firstRange(of: separator) else { return false }
        let headerData = data[data.startIndex..<headerRange.lowerBound]
        guard let headerPart = String(data: headerData, encoding: .utf8) else { return false }
        let lines = headerPart.components(separatedBy: "\r\n")

        var contentLength = 0
        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                contentLength = Int(value) ?? 0
                break
            }
        }

        let bodyStart = headerRange.upperBound
        let bodyLength = data.distance(from: bodyStart, to: data.endIndex)

        return bodyLength >= contentLength
    }

    static func parseRequest(from data: Data) -> HTTPRequest? {
        parseRequestLatin1(from: data)
    }

    private static func parseRequestLatin1(from data: Data) -> HTTPRequest? {
        // Find \r\n\r\n boundary in raw bytes
        let separator: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A]
        guard let separatorRange = data.firstRange(of: Data(separator)) else { return nil }

        let headerData = data[data.startIndex..<separatorRange.lowerBound]
        guard let headerStr = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerStr.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let fullPath = String(parts[1])

        var path = fullPath
        var queryParameters: [String: String] = [:]
        if let queryStart = fullPath.firstIndex(of: "?") {
            path = String(fullPath[fullPath.startIndex..<queryStart])
            let queryString = String(fullPath[fullPath.index(after: queryStart)...])
            for pair in queryString.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    queryParameters[String(kv[0])] = String(kv[1])
                }
            }
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        let body = data[separatorRange.upperBound...]

        return HTTPRequest(
            method: method,
            path: path,
            headers: headers,
            body: Data(body),
            queryParameters: queryParameters
        )
    }

    static func extractBoundary(from contentType: String) -> String? {
        let parts = contentType.components(separatedBy: ";")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("boundary=") {
                var boundary = String(trimmed.dropFirst("boundary=".count))
                if boundary.hasPrefix("\"") && boundary.hasSuffix("\"") {
                    boundary = String(boundary.dropFirst().dropLast())
                }
                return boundary
            }
        }
        return nil
    }

    static func parseMultipartBody(_ body: Data, boundary: String) -> [MultipartFile] {
        let boundaryData = Data("--\(boundary)".utf8)
        let endBoundaryData = Data("--\(boundary)--".utf8)
        let crlfcrlf = Data("\r\n\r\n".utf8)

        var files: [MultipartFile] = []
        var searchStart = body.startIndex

        while let boundaryRange = body[searchStart...].firstRange(of: boundaryData) {
            let partStart = boundaryRange.upperBound

            // Skip \r\n after boundary
            let contentStart: Data.Index
            if partStart + 2 <= body.endIndex,
               body[partStart] == 0x0D, body[partStart + 1] == 0x0A {
                contentStart = partStart + 2
            } else {
                contentStart = partStart
            }

            // Check if this is the end boundary
            if body[searchStart...].starts(with: endBoundaryData) {
                break
            }

            // Find next boundary
            guard let nextBoundaryRange = body[contentStart...].firstRange(of: boundaryData) else {
                break
            }

            let partData = body[contentStart..<nextBoundaryRange.lowerBound]

            // Remove trailing \r\n before boundary
            let trimmedPartData: Data
            if partData.count >= 2 {
                let lastTwo = partData.suffix(2)
                if lastTwo.elementsEqual([0x0D, 0x0A]) {
                    trimmedPartData = partData.dropLast(2)
                } else {
                    trimmedPartData = Data(partData)
                }
            } else {
                trimmedPartData = Data(partData)
            }

            // Split part into headers and body
            if let headerEnd = trimmedPartData.firstRange(of: crlfcrlf) {
                let headerData = trimmedPartData[trimmedPartData.startIndex..<headerEnd.lowerBound]
                let fileBody = trimmedPartData[headerEnd.upperBound...]

                if let headerStr = String(data: headerData, encoding: .utf8) {
                    let filename = extractFilename(from: headerStr)
                    let contentType = extractContentType(from: headerStr)

                    if let filename, !fileBody.isEmpty {
                        files.append(MultipartFile(
                            filename: filename,
                            contentType: contentType ?? "application/octet-stream",
                            data: Data(fileBody)
                        ))
                    }
                }
            }

            searchStart = nextBoundaryRange.lowerBound
        }

        return files
    }

    private static func extractFilename(from headers: String) -> String? {
        let lines = headers.components(separatedBy: "\r\n")
        for line in lines {
            let lower = line.lowercased()
            if lower.contains("content-disposition") && lower.contains("filename=") {
                if let filenameRange = line.range(of: "filename=\"") {
                    let afterQuote = line[filenameRange.upperBound...]
                    if let endQuote = afterQuote.firstIndex(of: "\"") {
                        return String(afterQuote[afterQuote.startIndex..<endQuote])
                    }
                }
                // Without quotes
                if let filenameRange = line.range(of: "filename=") {
                    let value = line[filenameRange.upperBound...]
                    let trimmed = value.trimmingCharacters(in: .whitespaces)
                    if let semi = trimmed.firstIndex(of: ";") {
                        return String(trimmed[trimmed.startIndex..<semi])
                    }
                    return String(trimmed)
                }
            }
        }
        return nil
    }

    private static func extractContentType(from headers: String) -> String? {
        let lines = headers.components(separatedBy: "\r\n")
        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("content-type:") {
                return String(line.dropFirst("content-type:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
