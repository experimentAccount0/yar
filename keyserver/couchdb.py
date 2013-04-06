#!/usr/bin/env python
#-------------------------------------------------------------------------------
#
# couchdb.py
#
#-------------------------------------------------------------------------------

import json
import httplib

import tornado.httpclient

#-------------------------------------------------------------------------------

class CouchDB(object):

	_host = "localhost"
	_port = "5984"
	_database = "macaa"

	_put_headers = tornado.httputil.HTTPHeaders({
		"Content-Type": "application/json; charset=utf8",
		"Accept": "application/json",
		"Accept-Encoding": "charset=utf8",
	})

	def _url(self,path,*args):
		url = "http://%s:%s/%s/%s" % (
			self.__class__._host,
			self.__class__._port,
			self.__class__._database,
			# :TODO: is the args[0][0] below really the right way to do this?
			(path % args[0][0])
			)
		return url

	def _fetch(self,dict,path,*args):
		url = self._url(path,args)
		try:
			http_client = tornado.httpclient.HTTPClient()
			if dict is None:
				response = http_client.fetch(url)
			else:
				body = json.dumps(dict)
				response = http_client.fetch(
					url,
					method='PUT',
					headers=self.__class__._put_headers,
					body=body)
		except tornado.httpclient.HTTPError:
			return (httplib.INTERNAL_SERVER_ERROR, None)
		rv = None
		body = response.body
		if body is not None and 0 < len(body):
			body_as_dict = json.loads(body)
			if 'rows' in body_as_dict:
				rv = []
				for row in body_as_dict['rows']:
					doc = row['value']
					rv.append(doc)
			else:
				rv = body_as_dict
		return (response.code,rv)

	def get(self,path,*args):
		return self._fetch(None,path,args)

	def put(self,dict,path,*args):
		return self._fetch(dict,path,args)

#-------------------------------------------------------------------------------

if __name__ == "__main__":
	pass

#------------------------------------------------------------------- End-of-File
