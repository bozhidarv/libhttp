//! HTTP status code definitions and utilities

/// HTTP status codes as defined in RFC 7231
pub const Status = enum(u16) {
    // 1xx Informational
    continue_ = 100,
    switching_protocols = 101,
    
    // 2xx Success
    ok = 200,
    created = 201,
    accepted = 202,
    no_content = 204,
    
    // 3xx Redirection
    moved_permanently = 301,
    found = 302,
    not_modified = 304,
    
    // 4xx Client Error
    bad_request = 400,
    unauthorized = 401,
    forbidden = 403,
    not_found = 404,
    method_not_allowed = 405,
    
    // 5xx Server Error
    internal_server_error = 500,
    not_implemented = 501,
    bad_gateway = 502,
    service_unavailable = 503,

    /// Get the reason phrase for a status code
    pub fn reasonPhrase(self: Status) []const u8 {
        return switch (self) {
            .continue_ => "Continue",
            .switching_protocols => "Switching Protocols",
            .ok => "OK",
            .created => "Created",
            .accepted => "Accepted",
            .no_content => "No Content",
            .moved_permanently => "Moved Permanently",
            .found => "Found",
            .not_modified => "Not Modified",
            .bad_request => "Bad Request",
            .unauthorized => "Unauthorized",
            .forbidden => "Forbidden",
            .not_found => "Not Found",
            .method_not_allowed => "Method Not Allowed",
            .internal_server_error => "Internal Server Error",
            .not_implemented => "Not Implemented",
            .bad_gateway => "Bad Gateway",
            .service_unavailable => "Service Unavailable",
        };
    }

    /// Create status from integer code
    pub fn fromCode(code: u16) Status {
        return @enumFromInt(code);
    }

    /// Check if status indicates success (2xx)
    pub fn isSuccess(self: Status) bool {
        const code = @intFromEnum(self);
        return code >= 200 and code < 300;
    }

    /// Check if status indicates client error (4xx)
    pub fn isClientError(self: Status) bool {
        const code = @intFromEnum(self);
        return code >= 400 and code < 500;
    }

    /// Check if status indicates server error (5xx)
    pub fn isServerError(self: Status) bool {
        const code = @intFromEnum(self);
        return code >= 500 and code < 600;
    }
};

const std = @import("std");

test "status properties" {
    try std.testing.expect(Status.ok.isSuccess());
    try std.testing.expect(Status.not_found.isClientError());
    try std.testing.expect(Status.internal_server_error.isServerError());
    try std.testing.expectEqualStrings("OK", Status.ok.reasonPhrase());
}
