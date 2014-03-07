To start the Auth Server:

~~~~~
auth_server
~~~~~

[auth_server](../../bin/auth_server) has a number of command
line options. Use the --help option to list them.

~~~~~
auth_server --help
Usage: auth_server [options]

Options:
  -h, --help            show this help message and exit
  --log=LOGGING_LEVEL   logging level
                        [DEBUG,INFO,WARNING,ERROR,CRITICAL,FATAL] - default =
                        ERROR
  --lon=LISTEN_ON       address:port to listen on - default = [('127.0.0.1',
                        8000)]
  --authmethod=APP_SERVER_AUTH_METHOD
                        app server's authorization method - default = YAR
  --keyserver=KEY_SERVER
                        key server - default = 127.0.0.1:8070
  --appserver=APP_SERVER
                        app server - default = 127.0.0.1:8080
  --maxage=MAXAGE       max age (in seconds) of valid request - default = 30
  --noncestore=NONCE_STORE
                        memcached servers for nonce store - default =
                        ['127.0.0.1:11211']
  --syslog=SYSLOG       syslog unix domain socket - default = None
~~~~~

When starting to use infrastructure like the Auth Server the natural instinct
would be to send the Auth Server a request using [cURL](http://en.wikipedia.org/wiki/CURL).
[cURL](http://en.wikipedia.org/wiki/CURL) is very effective when
using [Basic Authentication](http://en.wikipedia.org/wiki/Basic_authentication)

~~~~~
curl -s -u c4a8dfc4cb4b40a2a6bf1102720d9a06: http://127.0.0.1:5984/dave-was-here.html
~~~~~

To issue requests to the Auth Server using
[OAuth 2.0 Message Authentication Code (MAC) Tokens](http://tools.ietf.org/html/draft-ietf-oauth-v2-http-mac-02)
authentication [yarcurl](../../bin/yarcurl) is the recommended command line tool
rather than [cURL](http://en.wikipedia.org/wiki/CURL).

~~~~~
yarcurl GET http://127.0.0.1:5984/dave-was-here.html
~~~~~