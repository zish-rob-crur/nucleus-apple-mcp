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
    let dailyURL: URL
    let monthURL: URL
}

struct WrittenRawSamples: Equatable {
    let revisionId: String
    let manifestURL: URL
    let sampleURLs: [URL]
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
        storage: StorageStatus
    ) throws -> WrittenRevision {
        let dailyURL = try url(forRelativePath: Self.dailyDateRelpath(for: revision.date), storage: storage, createParent: true)
        try writeJSON(revision, to: dailyURL)

        let monthURL = try url(forRelativePath: Self.dailyMonthRelpath(for: revision.date), storage: storage, createParent: true)
        let month = String(revision.date.prefix(7))
        let updatedMonth = try mergeMonthIndex(revision: revision, month: month, existingURL: monthURL)
        try writeJSON(updatedMonth, to: monthURL)

        return WrittenRevision(revisionId: revision.commitId, dailyURL: dailyURL, monthURL: monthURL)
    }

    func writeRawSamples(
        _ export: RawSamplesExport,
        revisionId: String,
        storage: StorageStatus
    ) throws -> WrittenRawSamples {
        let baseDir = try url(forRelativePath: Self.rawDateDirectoryRelpath(for: export.meta.date), storage: storage, createParent: true)
        try fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true, attributes: nil)

        let typesDir = baseDir.appendingPathComponent("types", isDirectory: true)
        if fileManager.fileExists(atPath: typesDir.path(percentEncoded: false)) {
            try fileManager.removeItem(at: typesDir)
        }
        try fileManager.createDirectory(at: typesDir, withIntermediateDirectories: true, attributes: nil)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let grouped = Dictionary(grouping: export.samples, by: \.key)
        var sampleURLs: [URL] = []
        var manifestTypes: [String: RawTypeFile] = [:]

        for key in export.meta.typeStatus.keys.sorted() {
            let records = grouped[key] ?? []
            let relpath: String?
            if records.isEmpty {
                relpath = nil
            } else {
                let typeURL = typesDir.appendingPathComponent("\(key).jsonl", isDirectory: false)
                try writeJSONLines(records, encoder: encoder, to: typeURL)
                sampleURLs.append(typeURL)
                relpath = Self.rawTypeFileRelpath(for: export.meta.date, typeKey: key)
            }

            manifestTypes[key] = RawTypeFile(
                status: export.meta.typeStatus[key] ?? .no_data,
                recordCount: export.meta.typeCounts[key] ?? records.count,
                relpath: relpath
            )
        }

        let manifest = RawSamplesManifest(
            schemaVersion: "health.raw.manifest.v1",
            commitId: revisionId,
            date: export.meta.date,
            day: export.meta.day,
            generatedAt: export.meta.generatedAt,
            collector: export.meta.collector,
            types: manifestTypes
        )
        let manifestURL = baseDir.appendingPathComponent("manifest.json", isDirectory: false)
        try writeJSON(manifest, to: manifestURL)

        return WrittenRawSamples(revisionId: revisionId, manifestURL: manifestURL, sampleURLs: sampleURLs.sorted { $0.path < $1.path })
    }

    func writeCommit(
        _ commit: HealthSyncCommit,
        storage: StorageStatus
    ) throws -> URL {
        let commitURL = try url(forRelativePath: Self.commitRelpath(for: commit.commitId), storage: storage, createParent: true)
        try writeJSON(commit, to: commitURL)
        return commitURL
    }

    static func rawManifestRelpath(for date: String) -> String {
        "health/raw/dates/\(date)/manifest.json"
    }

    static func rawTypeFileRelpath(for date: String, typeKey: String) -> String {
        "health/raw/dates/\(date)/types/\(typeKey).jsonl"
    }

    static func dailyDateRelpath(for date: String) -> String {
        "health/daily/dates/\(date).json"
    }

    static func dailyMonthRelpath(for date: String) -> String {
        let month = String(date.prefix(7))
        return "health/daily/months/\(month).json"
    }

    static func rawDateDirectoryRelpath(for date: String) -> String {
        "health/raw/dates/\(date)"
    }

    static func commitRelpath(for commitId: String) -> String {
        let prefix = commitId.prefix(8)
        let year = prefix.prefix(4)
        let month = prefix.dropFirst(4).prefix(2)
        let day = prefix.dropFirst(6).prefix(2)
        return "health/commits/\(year)/\(month)/\(day)/\(commitId).json"
    }

    private func mergeMonthIndex(revision: DailyRevision, month: String, existingURL: URL) throws -> DailyMonthIndex {
        let decoder = JSONDecoder()
        var days: [DailyRevision] = []

        if let data = try? Data(contentsOf: existingURL),
           let existing = try? decoder.decode(DailyMonthIndex.self, from: data) {
            days = existing.days.filter { $0.date != revision.date }
        }

        days.append(revision)
        days.sort { $0.date < $1.date }

        return DailyMonthIndex(
            schemaVersion: "health.daily.month.v1",
            month: month,
            generatedAt: revision.generatedAt,
            days: days
        )
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }

    private func writeJSONLines<T: Encodable>(_ values: [T], encoder: JSONEncoder, to url: URL) throws {
        let tmpURL = url.deletingLastPathComponent()
            .appendingPathComponent(".tmp-\(UUID().uuidString)-\(url.lastPathComponent)", isDirectory: false)

        fileManager.createFile(atPath: tmpURL.path(percentEncoded: false), contents: nil, attributes: nil)
        let handle = try FileHandle(forWritingTo: tmpURL)
        defer { try? handle.close() }

        let newline = Data([0x0A])
        for value in values {
            try handle.write(contentsOf: encoder.encode(value))
            try handle.write(contentsOf: newline)
        }

        if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.moveItem(at: tmpURL, to: url)
    }

    private func url(forRelativePath relpath: String, storage: StorageStatus, createParent: Bool) throws -> URL {
        let url = relpath.split(separator: "/").reduce(storage.rootURL) { partial, component in
            partial.appendingPathComponent(String(component), isDirectory: false)
        }
        if createParent {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        }
        return url
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
