#!/usr/bin/env python3
"""A loopback Nextcloud impersonator for the test suite — just enough of
the real thing for ewe-cloud and ewe-conf's WebDAV backend:

  POST /index.php/login/v2            Login Flow v2 start
  GET  /login/v2/flow/<token>         "the person signed in" (the browser step)
  POST /login/v2/poll                 404 until the flow completed, then the grant
  GET  /ocs/v2.php/cloud/user         display name / email / quota (basic auth)
  DELETE /ocs/v2.php/core/apppassword revoke the app password
  GET  /index.php/avatar/<user>/<n>   a PNG
  /remote.php/dav/files/<user>/…      WebDAV: MKCOL, PUT (If-Match /
                                      If-None-Match → 412), GET (ETag),
                                      PROPFIND depth 0/1, DELETE
  /remote.php/dav/calendars/<user>/   CalDAV: PROPFIND depth 1 lists one
                                      calendar "Personal"; REPORT
                                      calendar-query on it answers three
                                      VEVENTs relative to today (a timed one
                                      with a VALARM, an all-day one, one
                                      expanded recurrence instance)

State lives in one JSON file so a test can inspect or forge it (a "foreign
machine" is just another PUT without If-Match). Usage:
    mock-nextcloud.py <port> <state.json>
Credentials: user `tester`, app password `app-pass-0123456789abcdef`.
"""
import hashlib
import json
import sys
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
from xml.sax.saxutils import escape

PORT, STATE = int(sys.argv[1]), sys.argv[2]
BASE = "http://127.0.0.1:%d" % PORT
USER, APP_PW = "tester", "app-pass-0123456789abcdef"
PNG = bytes.fromhex("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489"
                    "0000000d4944415478da63f8ffff3f0005fe02fe0d2f8f6c0000000049454e44ae426082")


def load():
    try:
        return json.load(open(STATE))
    except Exception:
        return {"flows": {}, "files": {}, "revoked": False, "puts": 0}


def save(s):
    json.dump(s, open(STATE, "w"))


def httpdate(t):
    return time.strftime("%a, %d %b %Y %H:%M:%S GMT", time.gmtime(t))


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    # ── plumbing ──
    def _send(self, code, body=b"", ctype="application/json", extra=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _json(self, obj, code=200):
        self._send(code, json.dumps(obj).encode())

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def _authed(self):
        import base64
        a = self.headers.get("Authorization", "")
        if not a.startswith("Basic "):
            return False
        try:
            u, p = base64.b64decode(a[6:]).decode().split(":", 1)
        except Exception:
            return False
        s = load()
        return u == USER and p == APP_PW and not s.get("revoked")

    def _dav_path(self):
        prefix = "/remote.php/dav/files/%s/" % USER
        p = urllib.parse.unquote(urllib.parse.urlsplit(self.path).path)
        if not p.startswith(prefix):
            return None
        return p[len(prefix):].strip("/")

    def _etag_for(self, s):
        s["puts"] = s.get("puts", 0) + 1
        return '"%s"' % hashlib.sha1(("%d" % s["puts"]).encode()).hexdigest()[:16]

    # ── verbs ──
    def do_POST(self):
        p = urllib.parse.urlsplit(self.path).path
        body = self._body()
        if p == "/index.php/login/v2":
            s = load()
            tok = "flow%d" % (len(s["flows"]) + 1)
            s["flows"][tok] = {"done": False}
            save(s)
            return self._json({"poll": {"token": tok, "endpoint": BASE + "/login/v2/poll"},
                               "login": BASE + "/login/v2/flow/" + tok})
        if p == "/login/v2/poll":
            tok = urllib.parse.parse_qs(body.decode()).get("token", [""])[0]
            s = load()
            f = s["flows"].get(tok)
            if not f or not f["done"]:
                return self._json({}, 404)
            s["revoked"] = False
            save(s)
            return self._json({"server": BASE, "loginName": USER, "appPassword": APP_PW})
        self._json({"error": "unknown"}, 404)

    def do_GET(self):
        p = urllib.parse.urlsplit(self.path).path
        if p.startswith("/login/v2/flow/"):
            tok = p.rsplit("/", 1)[1]
            s = load()
            if tok in s["flows"]:
                s["flows"][tok]["done"] = True
                save(s)
                return self._send(200, b"<html>signed in</html>", "text/html")
            return self._send(404, b"no such flow", "text/plain")
        if p == "/ocs/v2.php/cloud/user":
            if self.headers.get("OCS-APIRequest", "").lower() != "true":
                return self._json({"message": "OCS-APIRequest header missing"}, 400)
            if not self._authed():
                return self._json({"message": "unauthorised"}, 401)
            return self._json({"ocs": {"meta": {"status": "ok", "statuscode": 200},
                                       "data": {"id": USER, "displayname": "Test User",
                                                "email": "tester@example.org",
                                                "quota": {"free": 900, "used": 100,
                                                          "total": 1000, "relative": 10.0}}}})
        if p.startswith("/index.php/avatar/"):
            if not self._authed():
                return self._json({}, 401)
            return self._send(200, PNG, "image/png")
        rel = self._dav_path()
        if rel is not None:
            if not self._authed():
                return self._json({}, 401)
            s = load()
            f = s["files"].get(rel)
            if not f:
                return self._send(404, b"", "text/plain")
            return self._send(200, f["content"].encode("latin-1"), "application/octet-stream",
                              {"ETag": f["etag"], "Last-Modified": httpdate(f["mtime"])})
        self._json({"error": "unknown"}, 404)

    def do_DELETE(self):
        p = urllib.parse.urlsplit(self.path).path
        if p == "/ocs/v2.php/core/apppassword":
            if not self._authed():
                return self._json({}, 401)
            s = load()
            s["revoked"] = True
            save(s)
            return self._json({"ocs": {"meta": {"status": "ok", "statuscode": 200}, "data": []}})
        rel = self._dav_path()
        if rel is not None:
            if not self._authed():
                return self._json({}, 401)
            s = load()
            gone = [k for k in s["files"] if k == rel or k.startswith(rel + "/")]
            for k in gone:
                del s["files"][k]
            save(s)
            return self._send(204 if gone else 404)
        self._json({"error": "unknown"}, 404)

    def do_MKCOL(self):
        rel = self._dav_path()
        if rel is None:
            return self._json({}, 404)
        if not self._authed():
            return self._json({}, 401)
        s = load()
        if rel in s["files"]:
            return self._send(405)
        s["files"][rel] = {"dir": True, "etag": '"dir"', "mtime": time.time(), "content": ""}
        save(s)
        self._send(201)

    def do_PUT(self):
        rel = self._dav_path()
        body = self._body()
        if rel is None:
            return self._json({}, 404)
        if not self._authed():
            return self._json({}, 401)
        s = load()
        cur = s["files"].get(rel)
        parent = rel.rsplit("/", 1)[0] if "/" in rel else ""
        if parent and parent not in s["files"]:
            return self._send(409, b"parent collection missing", "text/plain")
        ifm, ifnm = self.headers.get("If-Match"), self.headers.get("If-None-Match")
        if ifnm == "*" and cur:
            return self._send(412, b"exists", "text/plain")
        if ifm and (not cur or cur["etag"] != ifm.strip()):
            return self._send(412, b"etag mismatch", "text/plain")
        etag = self._etag_for(s)
        s["files"][rel] = {"dir": False, "etag": etag, "mtime": time.time(),
                           "content": body.decode("latin-1")}
        save(s)
        self._send(201 if not cur else 204, extra={"ETag": etag, "OC-ETag": etag})

    # ── CalDAV (the calendar of the account) ──
    def _cal_path(self):
        prefix = "/remote.php/dav/calendars/%s/" % USER
        p = urllib.parse.unquote(urllib.parse.urlsplit(self.path).path)
        if not p.startswith(prefix):
            return None
        return p[len(prefix):].strip("/")

    def _cal_events_ics(self):
        """Three VEVENTs relative to today, already 'expanded' the way a
        calendar-query with <expand> hands them back."""
        import datetime as dt
        today = dt.date.today()
        d1 = today + dt.timedelta(days=1)
        d2 = today + dt.timedelta(days=2)
        d3 = today + dt.timedelta(days=3)
        stamp = lambda d, hh, mm: "%04d%02d%02dT%02d%02d00" % (d.year, d.month, d.day, hh, mm)
        return [
            ("ev1.ics", "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:ev1@mock\r\n"
             "SUMMARY:Standup\r\nLOCATION:Room 4\r\n"
             "DTSTART;TZID=Europe/Tbilisi:%s\r\nDTEND;TZID=Europe/Tbilisi:%s\r\n"
             "BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT15M\r\nEND:VALARM\r\n"
             "END:VEVENT\r\nEND:VCALENDAR\r\n" % (stamp(d1, 10, 0), stamp(d1, 10, 30))),
            ("ev2.ics", "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:ev2@mock\r\n"
             "SUMMARY:Public holiday\r\nDTSTART;VALUE=DATE:%s\r\nDTEND;VALUE=DATE:%s\r\n"
             "END:VEVENT\r\nEND:VCALENDAR\r\n" % (d2.strftime("%Y%m%d"), d3.strftime("%Y%m%d"))),
            ("ev3.ics", "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:ev3@mock\r\n"
             "RECURRENCE-ID:%sZ\r\nSUMMARY:Weekly sync\r\nDTSTART:%sZ\r\nDURATION:PT45M\r\n"
             "END:VEVENT\r\nEND:VCALENDAR\r\n" % (stamp(d3, 8, 0), stamp(d3, 8, 0))),
        ]

    def do_REPORT(self):
        rel = self._cal_path()
        self._body()
        if rel is None:
            return self._json({}, 404)
        if not self._authed():
            return self._json({}, 401)
        if rel != "personal":
            return self._send(404)
        parts = ['<?xml version="1.0"?><d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">']
        for name, ics in self._cal_events_ics():
            parts.append("<d:response><d:href>/remote.php/dav/calendars/%s/personal/%s</d:href><d:propstat><d:prop>"
                         '<d:getetag>"%s"</d:getetag><c:calendar-data>%s</c:calendar-data>'
                         "</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>"
                         % (USER, name, name, escape(ics)))
        parts.append("</d:multistatus>")
        self._send(207, "".join(parts).encode(), 'application/xml; charset="utf-8"')

    def _propfind_calendars(self, rel):
        if not self._authed():
            return self._json({}, 401)
        depth = self.headers.get("Depth", "0")
        parts = ['<?xml version="1.0"?><d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" '
                 'xmlns:a="http://apple.com/ns/ical/">']
        home = "/remote.php/dav/calendars/%s/" % USER
        parts.append("<d:response><d:href>%s</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype>"
                     "</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>" % home)
        if rel == "" and depth != "0" or rel == "personal":
            parts.append("<d:response><d:href>%spersonal/</d:href><d:propstat><d:prop>"
                         "<d:displayname>Personal</d:displayname><a:calendar-color>#0082C9FF</a:calendar-color>"
                         "<d:resourcetype><d:collection/><c:calendar/></d:resourcetype>"
                         '<c:supported-calendar-component-set><c:comp name="VEVENT"/></c:supported-calendar-component-set>'
                         "</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>" % home)
        parts.append("</d:multistatus>")
        self._send(207, "".join(parts).encode(), 'application/xml; charset="utf-8"')

    def do_PROPFIND(self):
        cal = self._cal_path()
        if cal is not None:
            self._body()
            return self._propfind_calendars(cal)
        rel = self._dav_path()
        self._body()
        if rel is None:
            return self._json({}, 404)
        if not self._authed():
            return self._json({}, 401)
        s = load()
        depth = self.headers.get("Depth", "0")
        if rel not in s["files"]:
            return self._send(404)
        items = [rel]
        if depth != "0" and s["files"][rel].get("dir"):
            items += [k for k in s["files"] if k.startswith(rel + "/") and "/" not in k[len(rel) + 1:]]
        parts = ['<?xml version="1.0"?><d:multistatus xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">']
        for k in items:
            f = s["files"][k]
            href = "/remote.php/dav/files/%s/%s" % (USER, urllib.parse.quote(k)) + ("/" if f.get("dir") else "")
            rtype = "<d:collection/>" if f.get("dir") else ""
            parts.append("<d:response><d:href>%s</d:href><d:propstat><d:prop>"
                         "<d:getetag>%s</d:getetag><d:getlastmodified>%s</d:getlastmodified>"
                         "<d:resourcetype>%s</d:resourcetype><d:getcontentlength>%d</d:getcontentlength>"
                         "</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>"
                         % (escape(href), escape(f["etag"]), httpdate(f["mtime"]), rtype,
                            len(f["content"])))
        parts.append("</d:multistatus>")
        self._send(207, "".join(parts).encode(), 'application/xml; charset="utf-8"')


if __name__ == "__main__":
    save(load())
    HTTPServer(("127.0.0.1", PORT), H).serve_forever()
