/**
 * This module defines a common interface for HTTP request processing.
 */
module http_primitives.handler;

import http_primitives.request;
import http_primitives.response;
import std.traits;

/**
 * An interface through which an HTTP request is processed. A server framework
 * or other bootstrapping will prepare a request and response, and pass their
 * references to a handler so that it may perform some logic and write to the
 * response.
 */
interface HttpRequestHandler {
    void handle(ref HttpRequest request, ref HttpResponse response);
}

/**
 * A template that resolves to `true` if the given callable argument is an
 * HTTP request handler function, such that a function F matches the signature
 * `void F(ref HttpRequest, ref HttpResponse)`.
 * Params:
 *   F = The callable to check.
 * Returns: True if the function is an http request handler.
 */
template isHttpRequestHandler(F) if (isCallable!F) {
    static if (!is(ReturnType!F == void) || arity!F != 2) {
        enum bool isHttpRequestHandler = false;
    } else {
        alias params = Parameters!F;
        alias storageClasses = ParameterStorageClassTuple!F;
        static if (
            is(params[0] == HttpRequest) &&
            storageClasses[0] == ParameterStorageClass.ref_ &&
            is(params[1] == HttpResponse) &&
            storageClasses[1] == ParameterStorageClass.ref_
        ) {
            enum bool isHttpRequestHandler = true;
        } else {
            enum bool isHttpRequestHandler = false;
        }
    }
}

unittest {
    void test1(ref HttpRequest req, ref HttpResponse resp) {}
    assert(isHttpRequestHandler!(typeof(test1)));

    void test2() {}
    assert(!isHttpRequestHandler!(typeof(test2)));
}

/**
 * Helper method that converts an HTTP handler function to an OOP-style
 * interface type, using an anonymous class definition.
 * Params:
 *   f = The function to wrap.
 * Returns: An implementation of `HttpRequestHandler` that delegates to the
 * given function.
 * ---
 * void foo(ref HttpRequest req, ref HttpResponse resp) {
 *   writeln("called foo");
 * }
 * HttpRequestHandler handler = wrapHandler(&foo);
 * ---
 */
HttpRequestHandler wrapHandler(F)(F f) if (isHttpRequestHandler!F) {
    return new class HttpRequestHandler {
        void handle(ref HttpRequest request, ref HttpResponse response) {
            f(request, response);
        }
    };
}

/**
 * Helper method that converts a function accepting a referenced HTTP request
 * into an HttpRequestHandler interface type.
 * Params:
 *   f = The function to wrap.
 * Returns: An implementation of `HttpRequestHandler` that passes its request
 * to the given function.
 */
HttpRequestHandler wrapHandler(void function(ref HttpRequest) f) {
    return new class HttpRequestHandler {
        void handle(ref HttpRequest request, ref HttpResponse response) {
            f(request);
        }
    };
}

/**
 * Helper method that converts a function accepting a referenced HTTP response
 * into an HttpRequestHandler interface type.
 * Params:
 *   f = The function to wrap.
 * Returns: An implementation of `HttpRequestHandler` that passes its response
 * to the given function.
 */
HttpRequestHandler wrapHandler(void function(ref HttpResponse) f) {
    return new class HttpRequestHandler {
        void handle(ref HttpRequest request, ref HttpResponse response) {
            f(response);
        }
    };
}

unittest {
    int x = 0;
    void test1(ref HttpRequest req, ref HttpResponse resp) {
        x = 1;
    }
    HttpRequestHandler handler = wrapHandler(&test1);
    HttpRequest req;
    HttpResponse resp;
    assert(x == 0);
    handler.handle(req, resp);
    assert(x == 1);
}
