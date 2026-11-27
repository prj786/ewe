#!/usr/bin/env python3
"""A loopback stand-in for Mozilla's ISPDB and a provider's own autoconfig
host, for ewe-mail's test (EWE_MAIL_ISPDB / EWE_MAIL_AUTOCONFIG_URL point
here, so the test never touches the network).
Usage: mock-autoconfig.py <port> <imap-port> <smtp-port>
  GET /v1.1/ispdb.test          config naming 127.0.0.1:<imap-port> / :<smtp-port>
  GET /domain/own.test/config   a config with %EMAILDOMAIN% and a local-part login
  anything else                 404 (-> autoconfig falls through to its guess)
"""
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT, IMAP, SMTP = (int(x) for x in sys.argv[1:4])
CFG = """<?xml version="1.0"?>
<clientConfig version="1.1"><emailProvider id="%(id)s">
 <incomingServer type="pop3"><hostname>pop.%(id)s</hostname><port>995</port><socketType>SSL</socketType><username>%%EMAILADDRESS%%</username></incomingServer>
 <incomingServer type="imap"><hostname>%(imap)s</hostname><port>%(iport)d</port><socketType>SSL</socketType><username>%(iuser)s</username></incomingServer>
 <outgoingServer type="smtp"><hostname>%(smtp)s</hostname><port>%(sport)d</port><socketType>STARTTLS</socketType><username>%%EMAILADDRESS%%</username></outgoingServer>
</emailProvider></clientConfig>"""
PAGES = {
    "/v1.1/ispdb.test": CFG % {"id": "ispdb.test", "imap": "127.0.0.1", "iport": IMAP, "iuser": "%EMAILADDRESS%",
                               "smtp": "127.0.0.1", "sport": SMTP},
    "/domain/own.test/config": CFG % {"id": "own.test", "imap": "imap.%EMAILDOMAIN%", "iport": 993,
                                      "iuser": "%EMAILLOCALPART%", "smtp": "smtp.%EMAILDOMAIN%", "sport": 587},
}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        body = PAGES.get(self.path)
        if body is None:
            self.send_response(404)
            self.end_headers()
            return
        b = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/xml")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)


HTTPServer(("127.0.0.1", PORT), H).serve_forever()
