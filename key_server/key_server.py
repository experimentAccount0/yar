#!/usr/bin/env python
"""The key server's mainline."""

import logging

import tornado.httpserver
import tornado.web

import tsh

import clparser
import key_server_request_handler

_logger = logging.getLogger("KEYSERVER.%s" % __name__)

if __name__ == "__main__":
    clp = clparser.CommandLineParser()
    (clo, cla) = clp.parse_args()

    logging.basicConfig(level=clo.logging_level)

    tsh.install_handler()

    key_server_request_handler._key_store = clo.key_store

    _logger.info(
        "Key server listening on %d and using key store '%s'",
        clo.port,
        clo.key_store)

    handlers = [
        (r"/v1.0/creds(?:/([^/]+))?", key_server_request_handler.RequestHandler),
    ]
    app = tornado.web.Application(handlers=handlers)

    http_server = tornado.httpserver.HTTPServer(app)
    http_server.listen(clo.port)
    tornado.ioloop.IOLoop.instance().start()
