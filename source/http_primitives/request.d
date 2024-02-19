/**
 * Defines the HttpRequest struct and associated functions and symbols.
 */
module http_primitives.request;

import http_primitives.util.multivalue_map;
import http_primitives.util.optional;
import std.range.primitives : isOutputRange;
import std.range.interfaces : InputRange;
import std.socket : Address;

/**
 * A struct describing the contents of an HTTP request.
 */
struct HttpRequest {
    /**
     * The HTTP method, or verb, which was requested.
     */
    Method method = Method.GET;

    /**
     * The URL that was requested.
     */
    string url = "";

    /**
     * The HTTP version of this request.
     */
    ubyte httpVersion = 1;

    /**
     * A multi-valued map of headers that were provided to this request.
     */
    StringMultiValueMap headers;

    /**
     * A multi-valued map of query parameters that were provided to this
     * request, as parsed from the request's URL.
     */
    StringMultiValueMap queryParams;

    /**
     * The remote address that this request came from.
     */
    Address remoteAddress;

    /**
     * The input range from which the request body can be read.
     */
    InputRange!(ubyte[]) inputRange;
}

/**
 * Gets a header value from a request, or returns a default value if the header
 * doesn't exist or is of an invalid format.
 * Params:
 *   request = The request to get the header from.
 *   name = The name of the header.
 *   defaultValue = The default value to use.
 * Returns: The header, converted to the given type T, or the default value if
 * no such header could be found.
 */
T getHeaderAs(T)(HttpRequest request, string name, T defaultValue = T.init) {
    import std.conv : to, ConvException;
    try {
        return request.headers.getFirst(name)
            .mapIfPresent!(s => s.to!T)
            .orElse(defaultValue);
    } catch (ConvException e) {
        return defaultValue;
    }
}

/**
 * Gets a query parameter value from a request, or returns a default value if
 * the parameter doesn't exist or is of an invalid format.
 * Params:
 *   request = The request to get the query parameter from.
 *   name = The name of the query parameter.
 *   defaultValue = The default value to use.
 * Returns: The query parameter, converted to the given type T, or the default
 * value if no such query parameter could be found.
 */
T getQueryParamAs(T)(HttpRequest request, string name, T defaultValue = T.init) {
    import std.conv : to, ConvException;
    try {
        return request.queryParams.getFirst(name)
            .mapIfPresent!(s => s.to!T)
            .orElse(defaultValue);
    } catch (ConvException e) {
        return defaultValue;
    }
}

/**
 * The default maximum request body size, in bytes, that will be read.
 */
immutable DEFAULT_MAX_READ_SIZE = 1024 * 1024 * 1024;

/**
 * Settings used when reading the body of an HTTP request.
 */
struct RequestBodyReadSettings {
    /**
     * Whether to require requests to have a valid "Content-Length" header. If
     * true, then request content is only read if the request has declared a
     * valid content length. Otherwise, reads will quit and read 0 bytes.
     */
    bool enforceContentLength = true;

    /**
     * An optional maximum body size limit to use. If set, then request bodies
     * larger than the given size will not be read.
     */
    Optional!ulong maxBodySize = Optional!ulong.of(DEFAULT_MAX_READ_SIZE);
}

/**
 * Reads the body of a request in its entirety, passing it to the given output
 * range for further use.
 * Params:
 *   request = The request to read the body from.
 *   outputRange = The output range to pass the body content to. This range
 *                 should accept chunks of `ubyte[]` data.
 *   readSettings = Various settings to use when reading the content.
 * Returns: 
 */
ulong readBody(O)(
    HttpRequest request,
    O outputRange,
    const RequestBodyReadSettings readSettings = RequestBodyReadSettings.init
) if (
    isOutputRange!(O, ubyte[])
) {
    Optional!ulong contentLengthOpt = Optional!ulong.empty;
    // If we require a valid content length header, we'll try to read it first.
    if (readSettings.enforceContentLength) {
        auto contentLengthStr = request.headers.getFirst("Content-Length");
        if (contentLengthStr) {
            import std.conv : to, ConvException;
            try {
                ulong contentLength = contentLengthStr.value.to!ulong;
                if (
                    contentLength == 0 ||
                    (readSettings.maxBodySize && contentLength > readSettings.maxBodySize.value)
                ) return 0;
                contentLengthOpt = Optional!ulong.of(contentLength);
            } catch (ConvException e) {
                // Invalid content length header string. Cancel reading.
                return 0;
            }
        } else {
            return 0;
        }
    }
    // Now do the actual reading.
    ulong bytesRead = 0;
    while (
        !request.inputRange.empty &&
        (!contentLengthOpt || bytesRead < contentLengthOpt.value) &&
        (!readSettings.maxBodySize || bytesRead < readSettings.maxBodySize.value)
    ) {
        ubyte[] chunk = request.inputRange.front;
        size_t bytesToRead = chunk.length;
        if (readSettings.enforceContentLength && chunk.length > (contentLengthOpt.value - bytesRead)) {
            bytesToRead = cast(size_t) (contentLengthOpt.value - bytesRead);
        }
        if (readSettings.maxBodySize && bytesToRead > (readSettings.maxBodySize.value - bytesRead)) {
            bytesToRead = cast(size_t) (readSettings.maxBodySize.value - bytesRead);
        }
        outputRange.put(chunk[0..bytesToRead]);
        bytesRead += bytesToRead;
        request.inputRange.popFront;
    }
    return bytesRead;
}

unittest {
    import std.range.interfaces : inputRangeObject;
    import std.array;
    import std.stdio;

    /// Helper function to turn string content into an input range, simulating a request body.
    InputRange!(ubyte[]) toRange(string content, size_t blockSize = 8192) {
        ubyte[][] chunks;
        size_t idx = 0;
        while (idx < content.length) {
            size_t len = content.length;
            if (len > blockSize) len = blockSize;
            chunks ~= cast(ubyte[]) content[idx .. idx + len];
            idx += len;
        }
        return inputRangeObject(chunks);
    }

    // Test a basic scenario with a content length.
    HttpRequest r1;
    r1.headers.add("Content-Length", "5");
    r1.inputRange = toRange("Hello");
    Appender!(ubyte[]) out1;
    ulong bytesRead = r1.readBody(&out1);
    assert(bytesRead == 5);
    assert(cast(string) out1[] == "Hello");

    // Test that if no content length is provided, but we enforce content length, that 0 bytes are read.
    HttpRequest r2;
    Appender!(ubyte[]) out2;
    bytesRead = r2.readBody(&out2, RequestBodyReadSettings(true));
    assert(bytesRead == 0);
    assert(out2[].length == 0);

    // Test that if content length is provided, and we enforce content length, that only that many bytes are read.
    HttpRequest r3;
    r3.headers.add("Content-Length", "5");
    r3.inputRange = toRange("Testing testing testing");
    Appender!(ubyte[]) out3;
    bytesRead = r3.readBody(&out3, RequestBodyReadSettings(true));
    assert(bytesRead == 5);
    assert(cast(string) out3[] == "Testi");

    // Test that if content length is provided but invalid, that 0 bytes are read.
    HttpRequest r4;
    r4.headers.add("Content-Length", "Not a number");
    r4.inputRange = toRange("Hello world!");
    Appender!(ubyte[]) out4;
    bytesRead = r4.readBody(&out4, RequestBodyReadSettings(true));
    assert(bytesRead == 0);
    assert(out4[].length == 0);
}

/**
 * Reads the entire content of a request's body, and returns it as an array of
 * ubytes.
 * Params:
 *   request = The request to read the body of.
 *   readSettings = Various settings to use when reading the content.
 * Returns: The array of bytes that was read.
 */
ubyte[] readBodyAsBytes(
    HttpRequest request,
    const RequestBodyReadSettings readSettings = RequestBodyReadSettings.init
) {
    import std.array : Appender;
    Appender!(ubyte[]) app;
    request.readBody(&app, readSettings);
    return app[];
}

/**
 * Reads the entire content of a request's body, and returns it as a string. No
 * encoding checks are performed; the bytes are simply returned as a string.
 * Params:
 *   request = The request to read the body of.
 *   readSettings = Various settings to use when reading the content.
 * Returns: The string that was read.
 */
string readBodyAsString(
    HttpRequest request,
    const RequestBodyReadSettings readSettings = RequestBodyReadSettings.init
) {
    return cast(string) request.readBodyAsBytes(readSettings);
}

/**
 * Reads the request's body and parses it as JSON using std.json. If parsing
 * fails, a `JSONException` is thrown.
 * Params:
 *   request = The request to read the body of.
 *   readSettings = Various settings to use when reading the content.
 * Returns: A `JSONValue` that was parsed from the request's body.
 */
auto readBodyAsJson(
    HttpRequest request,
    const RequestBodyReadSettings readSettings = RequestBodyReadSettings.init
) {
    string bodyContent = request.readBodyAsString(readSettings);
    import std.json : parseJSON;
    return parseJSON(bodyContent);
}

/**
 * Reads the request's body and parses it as form-urlencoded key-value pairs,
 * according to https://url.spec.whatwg.org/#application/x-www-form-urlencoded
 * Params:
 *   request = The request to read the body of.
 *   stripWhitespace = Whether to strip whitespace from parsed values. Not part
 *                     of the spec, but offered as a convenience.
 *   readSettings = Various settings to use when reading the content.
 * Returns: A multi-valued map of key-value pairs.
 */
StringMultiValueMap readBodyAsFormUrlEncoded(
    HttpRequest request,
    bool stripWhitespace = true,
    const RequestBodyReadSettings readSettings = RequestBodyReadSettings.init
) {
    import http_primitives.form_urlencoded;
    string bodyContent = request.readBodyAsString(readSettings);
    return parseFormUrlEncoded(bodyContent, stripWhitespace);
}

/** 
 * Enumeration of all possible HTTP request methods as unsigned integer values
 * for efficient logic.
 * 
 * https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods
 */
enum Method : ushort {
    GET     = 1 << 0,
    HEAD    = 1 << 1,
    POST    = 1 << 2,
    PUT     = 1 << 3,
    DELETE  = 1 << 4,
    CONNECT = 1 << 5,
    OPTIONS = 1 << 6,
    TRACE   = 1 << 7,
    PATCH   = 1 << 8
}

/**
 * Gets the string name of an HTTP method.
 * Params:
 *   method = The method to get the name of.
 * Returns: The string representation of the method.
 */
string getMethodName(Method method) {
    import std.traits : EnumMembers;
    static foreach (member; EnumMembers!Method) {
        if (method == member) {
            return __traits(identifier, member);
        }
    }
    assert(false, "Code should not reach this point.");
}

unittest {
    assert(getMethodName(Method.GET) == "GET");
    assert(getMethodName(Method.PATCH) == "PATCH");
}

/**
 * Gets the HTTP method for a given name.
 * Params:
 *   name = The name of the HTTP method to get.
 * Returns: An optional which resolves to the method if a match was found.
 */
Optional!Method methodFromName(string name) {
    import std.traits : EnumMembers;
    import std.string : toLower;
    static foreach (member; EnumMembers!Method) {
        if (name == __traits(identifier, member) || name == toLower(__traits(identifier, member))) {
            return Optional!Method.of(member);
        }
    }
    return Optional!Method.empty;
}

unittest {
    assert(methodFromName("GET").value == Method.GET);
    assert(methodFromName("post").value == Method.POST);
    assert(methodFromName("not a method").isNull);
}

/**
 * Creates a bitmask for the given list of methods, such that if a method is
 * present in the list, its corresponding bit will be 1. This can be used to
 * efficiently check if a method is in a pre-configured list of methods.
 * Params:
 *   methods = The list of methods to make a bitmask from.
 * Returns: The bitmask.
 * ---
 * ushort mask = createMethodMask([Method.GET, Method.HEAD]);
 * assert((Method.GET & mask) > 0);
 * assert((Method.HEAD & mask) > 0);
 * assert((Method.POST & mask) == 0);
 * ---
 */
ushort createMethodMask(const(Method[]) methods) {
    ushort mask = 0;
    foreach (method; methods) mask |= method;
    return mask;
}

unittest {
    ushort emptyMask = createMethodMask([]);
    assert(emptyMask == 0);

    ushort singleMask = createMethodMask([Method.POST]);
    assert((singleMask & Method.POST) > 0);
    assert((singleMask & Method.GET) == 0);

    ushort multiMask = createMethodMask([Method.POST, Method.PUT]);
    assert((multiMask & Method.POST) > 0);
    assert((multiMask & Method.PUT) > 0);
    assert((multiMask & Method.DELETE) == 0);
}

/**
 * Gets a list of methods that are present in a given method mask, as may have
 * been created by `createMethodMask`.
 * Params:
 *   mask = The mask to get methods from.
 * Returns: The list of methods in the mask.
 */
Method[] getMethodsFromMask(ushort mask) {
    import std.array : Appender;
    import std.traits : EnumMembers;
    Appender!(Method[]) app;
    static foreach (member; EnumMembers!Method) {
        if ((mask & member) > 0) app ~= member;
    }
    return app[];
}

unittest {
    import std.algorithm : canFind;

    assert(getMethodsFromMask(0) == []);
    Method[] m1 = [Method.GET];
    assert(getMethodsFromMask(createMethodMask(m1)) == m1);
    Method[] m2 = [Method.POST, Method.PATCH, Method.HEAD];
    // Ordering is not guaranteed to be the same!
    Method[] m2Result = getMethodsFromMask(createMethodMask(m2));
    assert(m2Result.length == 3);
    assert(m2Result.canFind(Method.POST));
    assert(m2Result.canFind(Method.PATCH));
    assert(m2Result.canFind(Method.HEAD));
}
