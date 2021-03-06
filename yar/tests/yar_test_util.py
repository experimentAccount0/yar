"""This module implements a collection of utilities for unit testing yar"""

import json
import re
import socket
import threading
import unittest
import uuid

import jsonschema
import tornado.ioloop
import tornado.netutil


class Server(object):
    """An abstract base class for mock auth service, key service and
    app service. The primary reason for this class to exist is so the
    constructor can find an available port for the server to run and
    save that port & associated socket object in the socket and
    port properties."""

    def __init__(self):
        """Opens a random but available socket and assigns it to the
        socket property. The socket's port is also assigned to the
        port property."""
        object.__init__(self)

        [self.socket] = tornado.netutil.bind_sockets(
            0,
            "127.0.0.1",
            family=socket.AF_INET)
        self.port = self.socket.getsockname()[1]

    def shutdown(self):
        """Can be overriden by derived classes to perform server
        type specific shutdown. This method is a no-op but derived
        classes should call this method in case this is not a no-op
        in the future."""
        pass


class IOLoop(threading.Thread):
    """This class makes it easy for a test case's `setUpClass()` to start
    a Tornado io loop on the non-main thread so that the io loop, auth service
    key service and app service can operate 'in the background' while the
    unit test runs on the main thread."""

    def __init__(self):
        threading.Thread.__init__(self)
        self.daemon = True

    def run(self):
        tornado.ioloop.IOLoop.instance().start()

    def stop(self):
        tornado.ioloop.IOLoop.instance().stop()


class TestCase(unittest.TestCase):

    @classmethod
    def random_non_none_non_zero_length_str(cls):
        """Return a random, non-None, non-zero-length string."""
        return str(uuid.uuid4()).replace("-", "")

    def _is_json(self, str_that_might_be_json):
        """Return ```True``` if ```str_that_might_be_json``` is a
        valid JSON string otherwise return ```False```."""
        if str_that_might_be_json is None:
            return False
        try:
            json.loads(str_that_might_be_json)
        except:
            return False
        return True

    def assertIsJSON(self, str_that_should_be_json):
        """assert that ```str_that_should_be_json``` is a
        valid JSON string."""
        self.assertTrue(self._is_json(str_that_should_be_json))

    def assertIsNotJSON(self, str_that_should_not_be_json):
        """assert that ```str_that_should_not_be_json``` is not a
        valid JSON string."""
        self.assertFalse(self._is_json(str_that_should_not_be_json))

    def _is_valid_json(self, str_that_might_be_valid_json, schema):
        """Return ```True``` is ```str_that_might_be_valid_json``` is
        a json document that is successfully validated by the
        JSON schema ```schema```."""
        if not self._is_json(str_that_might_be_valid_json):
            return False
        try:
            jsonschema.validate(str_that_might_be_valid_json, schema)
        except:
            return False
        return True

    def assertIsValidJSON(self, str_that_should_be_valid_json, schema):
        """assert that ```str_that_should_not_be_valid_json``` is a JSON
        document and is valid according to the JSON schema ```schema```."""
        self.assertIsJSON(str_that_should_be_valid_json)
        self.assertFalse(self._is_valid_json(str_that_should_be_valid_json, schema))

    def assertIsNotValidJSON(self, str_that_should_not_be_valid_json, schema):
        """assert that ```str_that_should_not_be_valid_json``` is a JSON
        document but is not valid according to the JSON schema ```schema```."""
        self.assertIsJSON(str_that_should_not_be_valid_json)
        self.assertFalse(self._is_valid_json(str_that_should_not_be_valid_json, schema))

    def assertIsJsonUtf8ContentType(self, content_type):
        """Allows the caller to assert if ```content_type```
        is valid for specifying utf8 json content in an http header. """
        self.assertIsNotNone(content_type)
        json_utf8_content_type_reg_ex = re.compile(
            "^\s*application/json;\s+charset\=utf-{0,1}8\s*$",
            re.IGNORECASE)
        self.assertIsNotNone(json_utf8_content_type_reg_ex.match(content_type))
