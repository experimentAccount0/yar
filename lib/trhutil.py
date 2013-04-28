#!/usr/bin/env python
"""This module contains a series of utilities for writing
Tornado request handlers."""

import httplib
import re
import json
import uuid
import logging

import tornado.web
import jsonschema

#-------------------------------------------------------------------------------

def _is_json_utf8_content_type(content_type):
	"""Returns True if ```content_type``` is a valid utf8 json
	content type otherwise returns False."""
	if content_type is None:
		return False
	json_utf8_content_type_reg_ex = re.compile(
		"^\s*application/json;\s+charset\=utf-{0,1}8\s*$",
		re.IGNORECASE )
	if not json_utf8_content_type_reg_ex.match(content_type):
		return False
	return True

#-------------------------------------------------------------------------------

class RequestHandler(tornado.web.RequestHandler):
	"""When a request handler uses this as its base class rather than
	tornado.web.RequestHandler the request handler gains access to
	a collection of useful utility methods that operate on requests
	and responses. The utility methods focus on requests and responses
	that use JSON."""

	def get_request_body_if_exists(self, value_if_not_found=None):
		"""Return the request's body if one exists otherwise return None."""
		if 0 == self.request.headers.get("Content-Length", 0):
			return None
		return self.request.body

	def get_json_request_body(self):
		"""Get the request's JSON body and convert it into a dict.
		If there's not body, the body isn't JSON, etc then return
		None otherwise return the dict."""
		content_type = self.request.headers.get("content-type", None)
		if not _is_json_utf8_content_type(content_type):
			return None

		body = self.get_request_body_if_exists(self)
		if not body:
			return None

		try:
			body_as_dict = json.loads(body)
		except:
			return None

		return body_as_dict

	def get_value_from_json_request_body(self, key, value_if_not_found=None):
		# :TODO: fix this comment 'cause it's not RST
		"""This method is a shortcut for:
		body = self.get_json_request_body()
		if body is None:
			value = value_if_not_found
		else:
			value = body.get(key, value_if_not)"""
		body_as_dict = self.get_json_request_body()
		if body_as_dict is None:
			return value_if_not_found

		return body_as_dict.get(key, value_if_not_found)

#-------------------------------------------------------------------------------

class Response(object):
	"""A wrapper for a ```tornado.httpclient.HTTPResponse``` that exposes
	a number of useful, commonly used methods."""

	def __init__(self, response):
		object.__init__(self)
		self._response = response

	def get_json_body(self, schema=None):
		"""Extract and return the JSON document from a
		```tornado.httpclient.HTTPResponse``` as well as optionally
		validating the document against a schema. If there's
		an error along the way return None."""
		if httplib.OK != self._response.code:
			return None

		content_length = self._response.headers.get("content-length", 0)
		if 0 == content_length:
			return None

		content_type = self._response.headers.get("content-type", None)
		if not _is_json_utf8_content_type(content_type):
			return None

		try:
			body = json.loads(self._response.body)
		except:
			return None

		if schema:
			try:
				jsonschema.validate(body, schema)
			except Exception as ex:
				print ">>>%s<<<" % str(ex)
				return None

		return body

#------------------------------------------------------------------- End-of-File