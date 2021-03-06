"""This module contains all the logic required to parse the key
service's command line."""

import optparse
import logging

from yar.util import clparserutil


class CommandLineParser(optparse.OptionParser):
    """This class parses the key service's command line."""

    def __init__(self):
        optparse.OptionParser.__init__(
            self,
            "usage: %prog [options]",
            option_class=clparserutil.Option)

        default = logging.ERROR
        fmt = (
            "logging level "
            "[DEBUG,INFO,WARNING,ERROR,CRITICAL,FATAL]"
            " - default = %s"
        )
        help = fmt % logging.getLevelName(default)
        self.add_option(
            "--log",
            action="store",
            dest="logging_level",
            default=default,
            type="logginglevel",
            help=help)

        default = "127.0.0.1:8070"
        help = "address:port to listen on - default = %s" % default
        self.add_option(
            "--lon",
            action="store",
            dest="listen_on",
            default=default,
            type="hostcolonportparsed",
            help=help)

        default = "127.0.0.1:5984/creds"
        fmt = (
            "key store - "
            "host:port/database"
            " - default = %s"
        )
        help = fmt % default
        self.add_option(
            "--key_store",
            action="store",
            dest="key_store",
            default=default,
            type="couchdb",
            help=help)

        default = None
        help = "syslog unix domain socket - default = %s" % default
        self.add_option(
            "--syslog",
            action="store",
            dest="syslog",
            default=default,
            type="unixdomainsocket",
            help=help)

        default = None
        help = "log to this file - default = %s" % default
        self.add_option(
            "--logfile",
            action="store",
            dest="logging_file",
            default=default,
            type="string",
            help=help)
