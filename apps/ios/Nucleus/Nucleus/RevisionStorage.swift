import Foundation
import CryptoKit

struct StorageStatus: Equatable {
    enum Backend: String {
        case icloudDrive = "icloud_drive"
        case localDocuments = "local_documents"
    }

    let backend: Backend
    let rootURL: URL
}

struct WrittenRevision: Equatable {
    let revisionId: String
    let revisionURL: URL
    let latestURL: URL
}

struct WrittenRawSamples: Equatable {
    let revisionId: String
    let rawURL: URL
    let metaURL: URL
}

enum RevisionStorageError: Error, LocalizedError {
    case invalidDate(String)
    case cannotResolveRoot

    var errorDescription: String? {
        switch self {
        case .invalidDate(let value):
            "Invalid date: \(value)"
        case .cannotResolveRoot:
            "Unable to resolve storage root."
        }
    }
}

final class RevisionStorage: @unchecked Sendable {
    private let fileManager = FileManager.default

    func resolveStatus(preferICloud: Bool = true) throws -> StorageStatus {
        if preferICloud, let url = iCloudDocumentsURL() {
            return StorageStatus(backend: .icloudDrive, rootURL: url)
        }

        guard let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw RevisionStorageError.cannotResolveRoot
        }
        return StorageStatus(backend: .localDocuments, rootURL: url)
    }

    func writeDailyRevision(
        _ revision: DailyRevision,
        revisionId: String,
        storage: StorageStatus
    ) throws -> WrittenRevision {
        guard let ymd = DateFormatting.ymdComponents(from: revision.date) else {
            throw RevisionStorageError.invalidDate(revision.date)
        }

        let dayDir = storage.rootURL
            .appendingPathComponent("health", isDirectory: true)
            .appendingPathComponent("v0", isDirectory: true)
            .appendingPathComponent("data", isDirectory: true)
            .appendingPathComponent(String(format: "%04d", ymd.year), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", ymd.month), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", ymd.day), isDirectory: true)

        let revisionsDir = dayDir.appendingPathComponent("revisions", isDirectory: true)
        try fileManager.createDirectory(at: revisionsDir, withIntermediateDirectories: true, attributes: nil)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(revision)

        let revisionURL = revisionsDir.appendingPathComponent("\(revisionId).json", isDirectory: false)
        try data.write(to: revisionURL, options: [.atomic])

        let latest = LatestPointer(
            date: revision.date,
            latestGeneratedAt: revision.generatedAt,
            revisionId: revisionId,
            revisionRelpath: "revisions/\(revisionId).json"
        )
        let latestData = try encoder.encode(latest)
        let latestURL = dayDir.appendingPathComponent("latest.json", isDirectory: false)
        try latestData.write(to: latestURL, options: [.atomic])

        return WrittenRevision(revisionId: revisionId, revisionURL: revisionURL, latestURL: latestURL)
    }

    func writeRawSamples(
        _ export: RawSamplesExport,
        revisionId: String,
        storage: StorageStatus
    ) throws -> WrittenRawSamples {
        guard let ymd = DateFormatting.ymdComponents(from: export.meta.date) else {
            throw RevisionStorageError.invalidDate(export.meta.date)
        }

        let dayDir = storage.rootURL
            .appendingPathComponent("health", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
            .appendingPathComponent("raw", isDirectory: true)
            .appendingPathComponent("data", isDirectory: true)
            .appendingPathComponent(String(format: "%04d", ymd.year), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", ymd.month), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", ymd.day), isDirectory: true)

        let revisionsDir = dayDir.appendingPathComponent("revisions", isDirectory: true)
        try fileManager.createDirectory(at: revisionsDir, withIntermediateDirectories: true, attributes: nil)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let rawURL = revisionsDir.appendingPathComponent("\(revisionId).jsonl", isDirectory: false)
        let tmpURL = revisionsDir.appendingPathComponent(".tmp-\(revisionId)-\(UUID().uuidString).jsonl", isDirectory: false)

        fileManager.createFile(atPath: tmpURL.path(percentEncoded: false), contents: nil, attributes: nil)
        let handle = try FileHandle(forWritingTo: tmpURL)
        defer { try? handle.close() }

        let newline = Data([0x0A])

        for sample in export.samples {
            try handle.write(contentsOf: encoder.encode(sample))
            try handle.write(contentsOf: newline)
        }

        try fileManager.moveItem(at: tmpURL, to: rawURL)

        let metaURL = revisionsDir.appendingPathComponent("\(revisionId).meta.json", isDirectory: false)
        let metaData = try encoder.encode(export.meta)
        try metaData.write(to: metaURL, options: [.atomic])

        return WrittenRawSamples(revisionId: revisionId, rawURL: rawURL, metaURL: metaURL)
    }

    private func iCloudDocumentsURL() -> URL? {
        guard let base = fileManager.url(forUbiquityContainerIdentifier: nil) else { return nil }
        return base.appendingPathComponent("Documents", isDirectory: true)
    }
}

enum S3UploadError: Error, LocalizedError {
    case invalidEndpoint
    case invalidRelativePath
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "Invalid S3 endpoint."
        case .invalidRelativePath:
            "Unable to derive relative path for upload."
        case .requestFailed(let code, let message):
            "Upload failed (\(code)): \(message)"
        }
    }
}

final class S3ObjectStoreUploader: @unchecked Sendable {
    struct PutResult: Equatable {
        let key: String
        let etag: String?
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func putFile(
        _ localURL: URL,
        relativeTo rootURL: URL,
        config: S3ObjectStoreConfig
    ) async throws -> PutResult {
        let relativePath = try Self.relativeObjectPath(for: localURL, rootURL: rootURL)
        let key = Self.joinPrefix(config.prefix, relativePath)
        return try await putFile(localURL, bucket: config.bucket, key: key, config: config)
    }

    func putFile(
        _ localURL: URL,
        bucket: String,
        key: String,
        config: S3ObjectStoreConfig
    ) async throws -> PutResult {
        let payloadHashHex = try Self.sha256Hex(fileURL: localURL)

        let (url, canonicalURI, host) = try Self.makeURL(
            endpoint: config.endpoint,
            bucket: bucket,
            key: key,
            usePathStyle: config.usePathStyle
        )

        let now = Date()
        let amzDate = Self.amzDate(now)
        let dateStamp = Self.dateStamp(now)
        let region = config.region.isEmpty ? "auto" : config.region

        let method = "PUT"
        let contentType = Self.contentType(for: localURL)

        let headersToSend: [String: String] = [
            "Host": host,
            "x-amz-date": amzDate,
            "x-amz-content-sha256": payloadHashHex,
        ]

        let signedHeadersLower = ["host", "x-amz-content-sha256", "x-amz-date"]
        let canonicalHeaders = signedHeadersLower
            .map { name -> String in
                let value: String = switch name {
                case "host": host
                case "x-amz-date": amzDate
                case "x-amz-content-sha256": payloadHashHex
                default: ""
                }
                return "\(name):\(value.trimmingCharacters(in: .whitespacesAndNewlines))\n"
            }
            .joined()

        let signedHeaders = signedHeadersLower.joined(separator: ";")

        let canonicalRequest = [
            method,
            canonicalURI,
            "",
            canonicalHeaders,
            signedHeaders,
            payloadHashHex,
        ].joined(separator: "\n")

        let canonicalRequestHash = Self.sha256Hex(data: Data(canonicalRequest.utf8))

        let scope = "\(dateStamp)/\(region)/s3/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            canonicalRequestHash,
        ].joined(separator: "\n")

        let signingKey = Self.sigV4SigningKey(secretAccessKey: config.credentials.secretAccessKey, dateStamp: dateStamp, region: region, service: "s3")
        let signature = Self.hmacSha256Hex(key: signingKey, message: Data(stringToSign.utf8))

        let authorization = "AWS4-HMAC-SHA256 Credential=\(config.credentials.accessKeyId)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        var request = URLRequest(url: url)
        request.httpMethod = method
        for (k, v) in headersToSend {
            request.setValue(v, forHTTPHeaderField: k)
        }
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        let (_, response) = try await session.upload(for: request, fromFile: localURL)
        guard let http = response as? HTTPURLResponse else {
            throw S3UploadError.requestFailed(-1, "Invalid response.")
        }

        let etag = http.value(forHTTPHeaderField: "ETag")
        guard (200...299).contains(http.statusCode) else {
            throw S3UploadError.requestFailed(http.statusCode, HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }

        return PutResult(key: key, etag: etag)
    }

    private static func makeURL(endpoint: URL, bucket: String, key: String, usePathStyle: Bool) throws -> (url: URL, canonicalURI: String, host: String) {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              let scheme = components.scheme,
              let baseHost = components.host,
              !scheme.isEmpty,
              !baseHost.isEmpty else {
            throw S3UploadError.invalidEndpoint
        }

        let trimmedKey = key.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let objectPath = usePathStyle ? "\(bucket)/\(trimmedKey)" : trimmedKey
        let canonicalURI = "/" + awsPercentEncodePath(objectPath)

        if usePathStyle {
            components.percentEncodedPath = canonicalURI
            guard let url = components.url else { throw S3UploadError.invalidEndpoint }
            return (url, canonicalURI, baseHost)
        }

        components.host = "\(bucket).\(baseHost)"
        components.percentEncodedPath = canonicalURI
        guard let url = components.url else { throw S3UploadError.invalidEndpoint }
        return (url, canonicalURI, components.host ?? baseHost)
    }

    private static func relativeObjectPath(for fileURL: URL, rootURL: URL) throws -> String {
        let filePath = fileURL.standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path

        guard filePath.hasPrefix(rootPath) else { throw S3UploadError.invalidRelativePath }
        let rel = String(filePath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !rel.isEmpty else { throw S3UploadError.invalidRelativePath }
        return rel
    }

    private static func joinPrefix(_ prefix: String, _ relpath: String) -> String {
        let p = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if p.isEmpty { return relpath }
        return "\(p)/\(relpath)"
    }

    private static func contentType(for url: URL) -> String? {
        let lower = url.lastPathComponent.lowercased()
        if lower.hasSuffix(".meta.json") { return "application/json" }
        if lower.hasSuffix(".json") { return "application/json" }
        if lower.hasSuffix(".jsonl") { return "application/x-ndjson" }
        return nil
    }

    private static func sha256Hex(fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }

        let digest = hasher.finalize()
        return Self.hexString(Data(digest))
    }

    private static func sha256Hex(data: Data) -> String {
        hexString(Data(SHA256.hash(data: data)))
    }

    private static func sigV4SigningKey(secretAccessKey: String, dateStamp: String, region: String, service: String) -> Data {
        let kSecret = Data(("AWS4" + secretAccessKey).utf8)
        let kDate = hmacSha256(key: kSecret, message: Data(dateStamp.utf8))
        let kRegion = hmacSha256(key: kDate, message: Data(region.utf8))
        let kService = hmacSha256(key: kRegion, message: Data(service.utf8))
        let kSigning = hmacSha256(key: kService, message: Data("aws4_request".utf8))
        return kSigning
    }

    private static func hmacSha256(key: Data, message: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: symmetricKey)
        return Data(mac)
    }

    private static func hmacSha256Hex(key: Data, message: Data) -> String {
        hexString(hmacSha256(key: key, message: message))
    }

    private static func amzDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func dateStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    private static func awsPercentEncodePath(_ path: String) -> String {
        let segments = path.split(separator: "/", omittingEmptySubsequences: true)
        return segments.map { awsPercentEncode(String($0)) }.joined(separator: "/")
    }

    private static func awsPercentEncode(_ value: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
