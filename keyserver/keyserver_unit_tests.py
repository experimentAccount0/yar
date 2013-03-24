#!/usr/bin/env python
#-------------------------------------------------------------------------------
#
# keyserver_unit_tests.py
#
#-------------------------------------------------------------------------------

import time
import socket
import threading
import unittest
import re
import httplib
import httplib2
import json

import tornado.httpserver
import tornado.ioloop
import tornado.options
import tornado.web
import tornado.netutil

import keyserver

#-------------------------------------------------------------------------------

_json_utf8_content_type_reg_ex = re.compile(
 	"^\s*application/json;\s+charset\=utf-{0,1}8\s*$",
 	re.IGNORECASE )

#-------------------------------------------------------------------------------

class KeyServer(threading.Thread):

	@classmethod
	def _get_socket(cls):
		[sock] = tornado.netutil.bind_sockets(
			0,
			"localhost",
			family=socket.AF_INET)
		return sock

	def __init__(self):
		threading.Thread.__init__(self)
		self.daemon = True

		sock = self.__class__._get_socket()
		self.port = sock.getsockname()[1]

		http_server = tornado.httpserver.HTTPServer(keyserver._tornado_app)
		http_server.add_sockets([sock])

		# this might not be required but want to give the server 
		# a bit of time to get itself settled
		time.sleep(1)

	def run(self):
		tornado.ioloop.IOLoop.instance().start()

	def stop(self):
		tornado.ioloop.IOLoop.instance().stop()

#-------------------------------------------------------------------------------

class TestStatus(unittest.TestCase):
	
	@classmethod
	def setUpClass(cls):
		cls._key_server = KeyServer()
		cls._key_server.start()

	@classmethod
	def tearDownClass(cls):
		cls._key_server.stop()
		cls._key_server = None

	@property
	def url(self):
		return "http://localhost:%s/status" % self.__class__._key_server.port

	def test_get(self):
		http_client = httplib2.Http()
		response, content = http_client.request(self.url, "GET")

		self.assertIsNotNone(response)
		self.assertTrue(httplib.OK == response.status)
		self.assertTrue("content-type" in response)
		content_type = response["content-type"]
		self.assertIsNotNone(_json_utf8_content_type_reg_ex.match(content_type))

		self.assertIsNotNone(content)
		content = json.loads(content)
		self.assertTrue("status" in content)
		self.assertTrue(content["status"] == "ok")
		self.assertTrue("version" in content)
		self.assertTrue(content["version"] == "1.0")

	def _test_bad_method(self,method):
		http_client = httplib2.Http()
		response, content = http_client.request(self.url, method)
		self.assertIsNotNone(response)
		self.assertTrue(httplib.METHOD_NOT_ALLOWED == response.status)

	def test_post(self):
		self._test_bad_method("POST")

	def test_put( self ):
		self._test_bad_method("PUT")

	def test_delete( self ):
		self._test_bad_method("DELETE")

#-------------------------------------------------------------------------------

if __name__ == "__main__":
	unittest.main()

#------------------------------------------------------------------- End-of-File