"""This module contains a collection of key server specific utilities."""

import json
import logging

import tornado.httpclient

import trhutil


_logger = logging.getLogger("KEYSERVER.%s" % __name__)


def _filter_out_non_model_creds_properties(creds):
    """When a dictionary representing a set of credentials
    is created, the dictionary may contain entries that are
    no part of the externally exposed model. This function
    takes a dictionary (```dict```), selects only the
    model properties in ```dict``` and returns a new
    dictionary containing only the model properties."""
    rv = {}
    keys = [
        "is_deleted",
        "mac_algorithm",
        "mac_key",
        "mac_key_identifier",
        "owner"
    ]
    for key in keys:
        if key in creds:
            rv[key] = creds[key]
    return rv


class AsyncAction(object):
    """```AsyncAction``` is an abstract base class for all key
    server classes which encapsulate async interaction between
    the key server and key store. The primary intent of this
    class is to abstract away all tornado details from the
    derived classes and isolate the async control code into
    a single spot. This isolation makes mock creation in unit
    tests super."""

    def __init__(self, key_store):
        object.__init__(self)
        self.key_store = key_store

    def async_req_to_key_store(
        self,
        path,
        method,
        body,
        callback):

        self._requestors_callback = callback

        json_encoded_body = json.dumps(body) if body else None

        url = "http://%s/%s" % (self.key_store, path)
        headers = tornado.httputil.HTTPHeaders({
            "Content-Type": "application/json; charset=utf8",
            "Accept": "application/json",
            "Accept-Encoding": "charset=utf8"
        })
        request=tornado.httpclient.HTTPRequest(
            url,
            method=method,
            headers=headers,
            body=json_encoded_body)
        http_client = tornado.httpclient.AsyncHTTPClient()
        http_client.fetch(
            request,
            callback=self._http_client_fetch_callback)

    def _http_client_fetch_callback(self, response):
        wrapped_response = trhutil.Response(response)
        code = response.code
        body = wrapped_response.get_json_body()
        self._requestors_callback(code, body)