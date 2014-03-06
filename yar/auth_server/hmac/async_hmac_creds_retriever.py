"""This module hides the gory details of async'ly interacting
with the key server to retrieve credentials."""

import httplib
import logging

import tornado.httpclient

from yar.key_server import jsonschemas
from yar.util import mac
from yar.util import trhutil

_logger = logging.getLogger("AUTHSERVER.%s" % __name__)

"""This host:port combination define the location of the key server."""
key_server_address = "127.0.0.1:8070"


class AsyncHMACCredsRetriever(object):
    """Wraps the gory details of async crednetials retrieval."""

    def __init__(self, mac_key_identifier):
        object.__init__(self)
        self._mac_key_identifier = mac_key_identifier

    def fetch(self, callback):
        """Retrieve the credentials for ```mac_key_identifier```
        and when done call ```callback```."""

        self._callback = callback

        url = "http://%s/v1.0/creds/%s" % (
            key_server_address,
            self._mac_key_identifier)
        http_request = tornado.httpclient.HTTPRequest(
            url=url,
            method="GET",
            follow_redirects=False)
        http_client = tornado.httpclient.AsyncHTTPClient()
        http_client.fetch(http_request, self._on_fetch_done)

    def _on_fetch_done(self, response):
        """Called when request to the key server returns."""
        _logger.info("Key Server (%s - %s) responded in %d ms",
            response.effective_url,
            response.request.method,
            int(response.request_time * 1000))

        if response.error or response.code != httplib.OK:
            self._callback(False, self._mac_key_identifier)
            return

        response = trhutil.Response(response)
        body = response.get_json_body(
            None,
            jsonschemas.get_creds_response)
        if body is None:
            self._callback(False, self._mac_key_identifier)
            return

        _logger.info(
            "For mac key identifier '%s' retrieved credentials '%s'",
            self._mac_key_identifier,
            body)

        self._callback(
            True,
            mac.MACKeyIdentifier(body["hmac"]["mac_key_identifier"]),
            body["is_deleted"],
            body["hmac"]["mac_algorithm"],
            mac.MACKey(body["hmac"]["mac_key"]),
            body["principal"])
