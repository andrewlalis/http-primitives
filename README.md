# HTTP Primitives

A library that provides a common set of basic components for dealing with HTTP
and related protocols in web servers.

This library defines, among others, the following symbols:

* `HttpRequest` to represent an incoming HTTP request.
* `HttpResponse` to represent an outgoing HTTP response.
* `HttpRequestHandler` to represent a logical component that processes requests.

The main motivating factor for this library is to provide framework-agnostic
components that allow diverse systems to interact, instead of requiring users
to commit to one single ecosystem or niche implementation. A lot of this
library's content originated from [Handy-Http](https://github.com/andrewlalis/handy-httpd).
