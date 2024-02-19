/**
 * Defines the HttpResponse struct and associated functions and symbols.
 */
module http_primitives.response;

import http_primitives.util.multivalue_map;
import std.range;

/**
 * A struct describing the contents of an HTTP response.
 */
struct HttpResponse {
    /**
     * The status of this response.
     */
    HttpResponseStatusInfo status = HttpStatus.OK;

    /**
     * A multi-valued map of headers to send with this response.
     */
    MultiValueMap!(string, string, false) headers;

    /**
     * The output range to write the response to.
     */
    OutputRange!(ubyte[]) outputRange;

    /**
     * A private flag indicating whether this response has written its status
     * and headers. This is used to make sure they're only written once, no
     * matter how many times the included "write..." functions are called.
     * Use `response.isFlushed` to check the value.
     */
    private bool statusAndHeadersWritten;
}

/**
 * Determines if the given HTTP response has been "flushed", that is, its
 * status and headers have been written. Once a response has been flushed, it
 * is no longer possible to change the status or headers, as they've already
 * been sent to the client.
 * Params:
 *   response = The response to check.
 * Returns: True if the response has already been flushed, or false otherwise.
 */
bool isFlushed(const HttpResponse response) {
    return response.statusAndHeadersWritten;
}

/**
 * Flushes the given HTTP response's status and headers, by writing them to
 * the response's output range as properly formatted HTTP response. After this
 * function is called on an HTTP response, editing its status or headers will
 * have no effect.
 * Params:
 *   response = The response to flush.
 */
void flushHeaders(ref HttpResponse response) {
    if (response.isFlushed) return; // TODO: Throw exception?
    import std.array : Appender;
    import std.conv : to;
    Appender!string app;
    // Write the status line.
    app ~= "HTTP/1.1 " ~ response.status.code.to!string ~ " " ~ response.status.text ~ "\r\n";
    // Then each header.
    foreach (name, value; response.headers) {
        app ~= name ~ ": " ~ value ~ "\r\n";
    }
    app ~= "\r\n"; // Write a final line break to denote the end of the headers section.
    response.outputRange.put(cast(ubyte[]) app[]);
    response.statusAndHeadersWritten = true;
}

/**
 * Writes data from the given input range into the given response's output
 * range. If the response's status and headers have not yet been flushed to the
 * output range, they'll be written beforehand.
 * Params:
 *   response = The response to write data to.
 *   inputRange = The input range containing the data to write.
 *   size = The size of the data.
 *   contentType = The mime type of the data.
 */
void writeBody(I)(
    ref HttpResponse response,
    I inputRange,
    ulong size,
    string contentType
) if (isInputRange!(I) && is(ElementType!(I) == ubyte[])) {
    import std.conv : to;
    if (!response.isFlushed) {
        response.headers.add("Content-Length", size.to!string);
        response.headers.add("Content-Type", contentType);
        response.flushHeaders();
    }
    while (!inputRange.empty) {
        ubyte[] chunk = inputRange.front;
        response.outputRange.put(chunk);
    }
}

/**
 * Writes an array of bytes to the given response's output range. Since this
 * calls `writeBody`, it follows the same logic of flushing status and headers
 * if they weren't already before this call.
 * Params:
 *   response = The response to write data to.
 *   data = The data to write.
 *   contentType = The mime type of the data.
 */
void writeBodyBytes(ref HttpResponse response, ubyte[] data, string contentType = "application/octet-stream") {
    writeBody(response, [data], data.length, contentType);
}

/**
 * Writes a string to the given response's output range.
 * Params:
 *   response = The response to write data to.
 *   data = The data to write.
 *   contentType = The mime type of the data.
 */
void writeBodyString(ref HttpResponse response, string data, string contentType = "text/plain; charset=utf-8") {
    writeBodyBytes(response, cast(ubyte[]) data, contentType);
}

/** 
 * A struct containing basic information about a response status.
 */
struct HttpResponseStatusInfo {
    /**
     * The integer status code for this response status.
     */
    ushort code;

    /**
     * A textual description of this response status.
     */
    string text;
}

/** 
 * An enum defining all valid HTTP response statuses:
 * See here: https://developer.mozilla.org/en-US/docs/Web/HTTP/Status
 */
enum HttpStatus : HttpResponseStatusInfo {
    // Information
    CONTINUE                        = HttpResponseStatusInfo(100, "Continue"),
    SWITCHING_PROTOCOLS             = HttpResponseStatusInfo(101, "Switching Protocols"),
    PROCESSING                      = HttpResponseStatusInfo(102, "Processing"),
    EARLY_HINTS                     = HttpResponseStatusInfo(103, "Early Hints"),

    // Success
    OK                              = HttpResponseStatusInfo(200, "OK"),
    CREATED                         = HttpResponseStatusInfo(201, "Created"),
    ACCEPTED                        = HttpResponseStatusInfo(202, "Accepted"),
    NON_AUTHORITATIVE_INFORMATION   = HttpResponseStatusInfo(203, "Non-Authoritative Information"),
    NO_CONTENT                      = HttpResponseStatusInfo(204, "No Content"),
    RESET_CONTENT                   = HttpResponseStatusInfo(205, "Reset Content"),
    PARTIAL_CONTENT                 = HttpResponseStatusInfo(206, "Partial Content"),
    MULTI_STATUS                    = HttpResponseStatusInfo(207, "Multi-Status"),
    ALREADY_REPORTED                = HttpResponseStatusInfo(208, "Already Reported"),
    IM_USED                         = HttpResponseStatusInfo(226, "IM Used"),

    // Redirection
    MULTIPLE_CHOICES                = HttpResponseStatusInfo(300, "Multiple Choices"),
    MOVED_PERMANENTLY               = HttpResponseStatusInfo(301, "Moved Permanently"),
    FOUND                           = HttpResponseStatusInfo(302, "Found"),
    SEE_OTHER                       = HttpResponseStatusInfo(303, "See Other"),
    NOT_MODIFIED                    = HttpResponseStatusInfo(304, "Not Modified"),
    TEMPORARY_REDIRECT              = HttpResponseStatusInfo(307, "Temporary Redirect"),
    PERMANENT_REDIRECT              = HttpResponseStatusInfo(308, "Permanent Redirect"),

    // Client error
    BAD_REQUEST                     = HttpResponseStatusInfo(400, "Bad Request"),
    UNAUTHORIZED                    = HttpResponseStatusInfo(401, "Unauthorized"),
    PAYMENT_REQUIRED                = HttpResponseStatusInfo(402, "Payment Required"),
    FORBIDDEN                       = HttpResponseStatusInfo(403, "Forbidden"),
    NOT_FOUND                       = HttpResponseStatusInfo(404, "Not Found"),
    METHOD_NOT_ALLOWED              = HttpResponseStatusInfo(405, "Method Not Allowed"),
    NOT_ACCEPTABLE                  = HttpResponseStatusInfo(406, "Not Acceptable"),
    PROXY_AUTHENTICATION_REQUIRED   = HttpResponseStatusInfo(407, "Proxy Authentication Required"),
    REQUEST_TIMEOUT                 = HttpResponseStatusInfo(408, "Request Timeout"),
    CONFLICT                        = HttpResponseStatusInfo(409, "Conflict"),
    GONE                            = HttpResponseStatusInfo(410, "Gone"),
    LENGTH_REQUIRED                 = HttpResponseStatusInfo(411, "Length Required"),
    PRECONDITION_FAILED             = HttpResponseStatusInfo(412, "Precondition Failed"),
    PAYLOAD_TOO_LARGE               = HttpResponseStatusInfo(413, "Payload Too Large"),
    URI_TOO_LONG                    = HttpResponseStatusInfo(414, "URI Too Long"),
    UNSUPPORTED_MEDIA_TYPE          = HttpResponseStatusInfo(415, "Unsupported Media Type"),
    RANGE_NOT_SATISFIABLE           = HttpResponseStatusInfo(416, "Range Not Satisfiable"),
    EXPECTATION_FAILED              = HttpResponseStatusInfo(417, "Expectation Failed"),
    IM_A_TEAPOT                     = HttpResponseStatusInfo(418, "I'm a teapot"),
    MISDIRECTED_REQUEST             = HttpResponseStatusInfo(421, "Misdirected Request"),
    UNPROCESSABLE_CONTENT           = HttpResponseStatusInfo(422, "Unprocessable Content"),
    LOCKED                          = HttpResponseStatusInfo(423, "Locked"),
    FAILED_DEPENDENCY               = HttpResponseStatusInfo(424, "Failed Dependency"),
    TOO_EARLY                       = HttpResponseStatusInfo(425, "Too Early"),
    UPGRADE_REQUIRED                = HttpResponseStatusInfo(426, "Upgrade Required"),
    PRECONDITION_REQUIRED           = HttpResponseStatusInfo(428, "Precondition Required"),
    TOO_MANY_REQUESTS               = HttpResponseStatusInfo(429, "Too Many Requests"),
    REQUEST_HEADER_FIELDS_TOO_LARGE = HttpResponseStatusInfo(431, "Request Header Fields Too Large"),
    UNAVAILABLE_FOR_LEGAL_REASONS   = HttpResponseStatusInfo(451, "Unavailable For Legal Reasons"),

    // Server error
    INTERNAL_SERVER_ERROR           = HttpResponseStatusInfo(500, "Internal Server Error"),
    NOT_IMPLEMENTED                 = HttpResponseStatusInfo(501, "Not Implemented"),
    BAD_GATEWAY                     = HttpResponseStatusInfo(502, "Bad Gateway"),
    SERVICE_UNAVAILABLE             = HttpResponseStatusInfo(503, "Service Unavailable"),
    GATEWAY_TIMEOUT                 = HttpResponseStatusInfo(504, "Gateway Timeout"),
    HTTP_VERSION_NOT_SUPPORTED      = HttpResponseStatusInfo(505, "HTTP Version Not Supported"),
    VARIANT_ALSO_NEGOTIATES         = HttpResponseStatusInfo(506, "Variant Also Negotiates"),
    INSUFFICIENT_STORAGE            = HttpResponseStatusInfo(507, "Insufficient Storage"),
    LOOP_DETECTED                   = HttpResponseStatusInfo(508, "Loop Detected"),
    NOT_EXTENDED                    = HttpResponseStatusInfo(510, "Not Extended"),
    NETWORK_AUTHENTICATION_REQUIRED = HttpResponseStatusInfo(511, "Network Authentication Required")
}
