import CryptoKit
import Foundation

struct R2Object: Sendable {
    let key: String
    let size: Int64
    let lastModified: Date
}

struct R2Uploader: Sendable {
    enum Error: Swift.Error, LocalizedError {
        case invalidConfig
        case uploadFailed(Int, String)
        case networkError(String)

        var errorDescription: String? {
            switch self {
            case .invalidConfig: "R2 configuration is incomplete"
            case .uploadFailed(let code, let msg): "Upload failed (HTTP \(code))\(msg.isEmpty ? "" : ": \(msg)")"
            case .networkError(let msg): "Network error: \(msg)"
            }
        }
    }

    func upload(item: ImageItem, config: R2Config) async throws -> ImageItem {
        guard config.isValid else { throw Error.invalidConfig }
        let fileURL = item.webpURL ?? ImageProcessor.cacheURL(for: item.title)
        guard let data = try? Data(contentsOf: fileURL) else { throw Error.networkError("Could not read AVIF file") }

        let key = "\(item.title).avif"
        let payloadHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        let now = Date()
        let amzDate = formatISO8601(now)
        let dateStamp = formatDate(now)
        let region = "auto"

        let host = "\(config.bucketName).\(config.resolvedEndpoint)"
        let encodedKey = key.s3Encoded
        let canonicalURI = "/\(encodedKey)"

        let canonicalHeaders = [
            "content-type:image/avif",
            "host:\(host)",
            "x-amz-content-sha256:\(payloadHash)",
            "x-amz-date:\(amzDate)",
        ].joined(separator: "\n") + "\n"

        let signedHeaders = "content-type;host;x-amz-content-sha256;x-amz-date"

        let canonicalRequest = ["PUT", canonicalURI, "", canonicalHeaders, signedHeaders, payloadHash].joined(separator: "\n")
        let canonicalRequestHash = SHA256.hash(data: Data(canonicalRequest.utf8)).map { String(format: "%02x", $0) }.joined()

        let stringToSign = ["AWS4-HMAC-SHA256", amzDate, "\(dateStamp)/\(region)/s3/aws4_request", canonicalRequestHash].joined(separator: "\n")

        let signingKey = deriveSigningKey(secret: config.secretAccessKey, date: dateStamp, region: region)
        let signature = hmacSHA256(key: signingKey, data: Data(stringToSign.utf8)).map { String(format: "%02x", $0) }.joined()

        let authorization = "AWS4-HMAC-SHA256 Credential=\(config.accessKeyId)/\(dateStamp)/\(region)/s3/aws4_request, SignedHeaders=\(signedHeaders), Signature=\(signature)"

        let urlString = "https://\(host)/\(encodedKey)"
        guard let url = URL(string: urlString) else { throw Error.networkError("Invalid URL: \(urlString)") }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "PUT"
        request.setValue("image/avif", forHTTPHeaderField: "Content-Type")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.httpBody = data

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw Error.networkError("Invalid response") }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: responseData, encoding: .utf8) ?? ""
            throw Error.uploadFailed(httpResponse.statusCode, body.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        var updated = item
        updated.status = .uploaded(url: "\(config.publicURLBaseNormalized)/\(key)")
        return updated
    }

    func delete(item: ImageItem, config: R2Config) async throws {
        guard config.isValid else { throw Error.invalidConfig }

        let key: String = {
            // R2-imported: originalFilename IS the R2 key
            if item.uploadedAt != nil, !item.originalFilename.isEmpty { return item.originalFilename }
            // Locally processed + uploaded: key is title.avif
            return "\(item.title).avif"
        }()
        let emptyHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

        let now = Date()
        let amzDate = formatISO8601(now)
        let dateStamp = formatDate(now)
        let region = "auto"
        let host = "\(config.bucketName).\(config.resolvedEndpoint)"
        let encodedKey = key.s3Encoded
        let canonicalURI = "/\(encodedKey)"

        let canonicalHeaders = [
            "content-type:application/octet-stream",
            "host:\(host)",
            "x-amz-content-sha256:\(emptyHash)",
            "x-amz-date:\(amzDate)",
        ].joined(separator: "\n") + "\n"
        let signedHeaders = "content-type;host;x-amz-content-sha256;x-amz-date"
        let canonicalRequest = ["DELETE", canonicalURI, "", canonicalHeaders, signedHeaders, emptyHash].joined(separator: "\n")
        let canonicalRequestHash = SHA256.hash(data: Data(canonicalRequest.utf8)).map { String(format: "%02x", $0) }.joined()

        let stringToSign = ["AWS4-HMAC-SHA256", amzDate, "\(dateStamp)/\(region)/s3/aws4_request", canonicalRequestHash].joined(separator: "\n")
        let signingKey = deriveSigningKey(secret: config.secretAccessKey, date: dateStamp, region: region)
        let signature = hmacSHA256(key: signingKey, data: Data(stringToSign.utf8)).map { String(format: "%02x", $0) }.joined()
        let authorization = "AWS4-HMAC-SHA256 Credential=\(config.accessKeyId)/\(dateStamp)/\(region)/s3/aws4_request, SignedHeaders=\(signedHeaders), Signature=\(signature)"

        let urlString = "https://\(host)/\(encodedKey)"
        guard let url = URL(string: urlString) else { throw Error.networkError("Invalid URL: \(urlString)") }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "DELETE"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(emptyHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw Error.networkError("Invalid response") }
        guard httpResponse.statusCode == 204 || httpResponse.statusCode == 200 else {
            let body = String(data: responseData, encoding: .utf8) ?? ""
            let detail = parseErrorResponse(responseData)
            throw Error.uploadFailed(httpResponse.statusCode, "DELETE \(key): \(detail ?? body)")
        }
    }

    private func parseErrorResponse(_ data: Data) -> String? {
        let parser = XMLParser(data: data)
        let delegate = ErrorParserDelegate()
        parser.delegate = delegate
        parser.parse()
        if let code = delegate.code, let message = delegate.message {
            return "\(code) — \(message)"
        }
        return nil
    }

    private final class ErrorParserDelegate: NSObject, XMLParserDelegate {
        var code: String?
        var message: String?
        private var currentElement = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            currentElement = elementName
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            switch currentElement {
            case "Code": code = (code ?? "") + text
            case "Message": message = (message ?? "") + text
            default: break
            }
        }
    }

    func listObjects(config: R2Config) async throws -> [R2Object] {
        guard config.isValid else { throw Error.invalidConfig }

        let emptyHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        let now = Date()
        let amzDate = formatISO8601(now)
        let dateStamp = formatDate(now)
        let region = "auto"
        let host = "\(config.bucketName).\(config.resolvedEndpoint)"
        let canonicalURI = "/"

        let queryString = "list-type=2"
        let canonicalHeaders = ["host:\(host)", "x-amz-content-sha256:\(emptyHash)", "x-amz-date:\(amzDate)"].joined(separator: "\n") + "\n"
        let signedHeaders = "host;x-amz-content-sha256;x-amz-date"
        let canonicalRequest = ["GET", canonicalURI, queryString, canonicalHeaders, signedHeaders, emptyHash].joined(separator: "\n")
        let canonicalRequestHash = SHA256.hash(data: Data(canonicalRequest.utf8)).map { String(format: "%02x", $0) }.joined()

        let stringToSign = ["AWS4-HMAC-SHA256", amzDate, "\(dateStamp)/\(region)/s3/aws4_request", canonicalRequestHash].joined(separator: "\n")
        let signingKey = deriveSigningKey(secret: config.secretAccessKey, date: dateStamp, region: region)
        let signature = hmacSHA256(key: signingKey, data: Data(stringToSign.utf8)).map { String(format: "%02x", $0) }.joined()
        let authorization = "AWS4-HMAC-SHA256 Credential=\(config.accessKeyId)/\(dateStamp)/\(region)/s3/aws4_request, SignedHeaders=\(signedHeaders), Signature=\(signature)"

        let urlString = "https://\(host)/?list-type=2"
        guard let url = URL(string: urlString) else { throw Error.networkError("Invalid URL") }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(emptyHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw Error.networkError("Invalid response") }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw Error.uploadFailed(httpResponse.statusCode, body)
        }

        return parseListObjectsXML(data)
    }

    private func parseListObjectsXML(_ data: Data) -> [R2Object] {
        let parser = XMLParser(data: data)
        let delegate = ListObjectsParserDelegate()
        parser.delegate = delegate
        parser.parse()
        return delegate.objects
    }

    private func formatISO8601(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date)
    }
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyyMMdd"
        return f.string(from: date)
    }
    private func deriveSigningKey(secret: String, date: String, region: String) -> Data {
        let kDate = hmacSHA256(key: Data("AWS4\(secret)".utf8), data: Data(date.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data("s3".utf8))
        return hmacSHA256(key: kService, data: Data("aws4_request".utf8))
    }
    private func hmacSHA256(key: Data, data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }
}

extension String {
    /// Encode for S3 canonical URI: encode everything except A-Z, a-z, 0-9, -, _, ., ~, /
    var s3Encoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~/")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

// MARK: - ListObjects XML Parser

private final class ListObjectsParserDelegate: NSObject, XMLParserDelegate {
    var objects: [R2Object] = []

    private var currentElement = ""
    private var currentKey = ""
    private var currentSize: Int64 = 0
    private var currentLastModified = Date()
    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        switch currentElement {
        case "Key": currentKey += text
        case "Size": currentSize = Int64(text) ?? 0
        case "LastModified":
            if let date = dateFormatter.date(from: text) ?? ISO8601DateFormatter().date(from: text) {
                currentLastModified = date
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "Contents" {
            if !currentKey.isEmpty {
                objects.append(R2Object(key: currentKey, size: currentSize, lastModified: currentLastModified))
            }
            currentKey = ""; currentSize = 0
        }
    }
}
