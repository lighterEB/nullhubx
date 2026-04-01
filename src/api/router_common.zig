pub const Response = struct {
    status: []const u8,
    content_type: []const u8,
    body: []const u8,
};

pub fn jsonResponse(body: []const u8) Response {
    return .{ .status = "200 OK", .content_type = "application/json", .body = body };
}

pub fn jsonResponseWithStatus(status: []const u8, body: []const u8) Response {
    return .{ .status = status, .content_type = "application/json", .body = body };
}

pub fn internalServerError() Response {
    return jsonResponseWithStatus("500 Internal Server Error", "{\"error\":\"internal server error\"}");
}

pub fn methodNotAllowed() Response {
    return jsonResponseWithStatus("405 Method Not Allowed", "{\"error\":\"method not allowed\"}");
}

pub fn notFound() Response {
    return jsonResponseWithStatus("404 Not Found", "{\"error\":\"not found\"}");
}
