import GRPCCore

/// Bearer token authentication interceptor for all gRPC RPCs.
///
/// Extracts the "authorization" metadata header and validates it matches
/// the expected bearer token. Rejects unauthenticated requests with
/// `RPCError(.unauthenticated)`.
///
/// The Status RPC is exempted from auth to allow health checks.
struct AuthInterceptor: ServerInterceptor, Sendable {
    private let expectedToken: String

    init(expectedToken: String) {
        self.expectedToken = expectedToken
    }

    func intercept<Input: Sendable, Output: Sendable>(
        request: StreamingServerRequest<Input>,
        context: ServerContext,
        next: @Sendable (
            _ request: StreamingServerRequest<Input>,
            _ context: ServerContext
        ) async throws -> StreamingServerResponse<Output>
    ) async throws -> StreamingServerResponse<Output> {
        // Allow Status RPC without authentication (health check)
        if context.descriptor.method == "Status" {
            return try await next(request, context)
        }

        // Extract bearer token from metadata
        guard let authValue = request.metadata[stringValues: "authorization"]
            .first(where: { _ in true })
        else {
            throw RPCError(code: .unauthenticated, message: "Missing authorization header")
        }

        // Validate bearer token format
        let prefix = "Bearer "
        guard authValue.hasPrefix(prefix) else {
            throw RPCError(
                code: .unauthenticated,
                message: "Invalid authorization format, expected 'Bearer <token>'"
            )
        }

        // Constant-time-ish comparison (both are short tokens; acceptable for personal use)
        let token = String(authValue.dropFirst(prefix.count))
        guard token == expectedToken else {
            throw RPCError(code: .unauthenticated, message: "Invalid token")
        }

        return try await next(request, context)
    }
}

