import Foundation

extension BooksTrackAPI {

    private func createMultipartFormDataBody(data: Data, boundary: String, fieldName: String, fileName: String, contentType: String) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    /// Imports a CSV file.
    func importCSV(data csvData: Data) async throws -> (jobId: String, authToken: String) {
        let url = baseURL.appendingPathComponent("/api/v2/imports")

        let boundary = UUID().uuidString
        let multipartBody = createMultipartFormDataBody(
            data: csvData,
            boundary: boundary,
            fieldName: "file",
            fileName: "import.csv",
            contentType: "text/csv"
        )

        var request = makeRequest(url: url, method: "POST", body: multipartBody, contentType: "multipart/form-data; boundary=\(boundary)")
        request.timeoutInterval = 30.0 // 30s timeout for POST

        let (data, _) = try await performRequest(request: request)
        let response = try decodeEnvelope(JobInitiationResponse.self, from: data)
        return (jobId: response.jobId, authToken: response.authToken)
    }

    /// Gets the results of an import job.
    func getImportResults(jobId: String) async throws -> ImportResults {
        let url = baseURL.appendingPathComponent("/api/v2/imports/\(jobId)/results")

        let request = makeRequest(url: url)
        let (data, _) = try await performRequest(request: request)
        return try decodeEnvelope(ImportResults.self, from: data)
    }

    /// Gets the status of an import job.
    func getJobStatus(jobId: String) async throws -> ImportJobStatus {
        let url = baseURL.appendingPathComponent("/api/v2/imports/\(jobId)")

        let request = makeRequest(url: url)
        let (data, _) = try await performRequest(request: request)
        return try decodeEnvelope(ImportJobStatus.self, from: data)
    }
}
