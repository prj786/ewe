#!/usr/bin/env python3
"""A loopback IMAP impersonator for ewe-mail's test — plain TCP (the tool
allows that only for 127.0.0.1 with EWE_MAIL_INSECURE=1), one client at a
time, just the verbs imaplib sends for the badge:
  CAPABILITY · LOGIN (user `tester`, password `mail-pass`) · STATUS INBOX
  (UNSEEN) · SELECT/EXAMINE INBOX · UID SEARCH UNSEEN · UID FETCH … BODY.PEEK
  [HEADER.FIELDS (FROM SUBJECT DATE)] · LOGOUT
Three messages, two unseen (UIDs 101 and 103). Usage: mock-imap.py <port>
"""
import socket
import sys

PORT = int(sys.argv[1])
USER, PW = "tester", "mail-pass"
MSGS = {
    101: (b"From: =?utf-8?q?Nino_Bera=C3=B0?= <nino@example.org>\r\nSubject: Lunch on Friday?\r\n"
          b"Date: Wed, 02 Sep 2026 10:15:00 +0400\r\n\r\n"),
    102: (b"From: Newsletter <news@example.org>\r\nSubject: Seen already\r\n"
          b"Date: Tue, 01 Sep 2026 09:00:00 +0400\r\n\r\n"),
    103: (b"From: ops@example.org\r\nSubject: =?UTF-8?B?U2VydmVyIOKAlCBhbGwgZ29vZA==?=\r\n"
          b"Date: Wed, 02 Sep 2026 12:30:00 +0400\r\n\r\n"),
}
UNSEEN = [101, 103]


def serve(conn):
    f = conn.makefile("rwb", buffering=0)

    def send(line):
        f.write(line + b"\r\n")

    send(b"* OK mock IMAP ready")
    authed = False
    while True:
        raw = f.readline()
        if not raw:
            return
        line = raw.rstrip(b"\r\n")
        parts = line.split(b" ", 2)
        if len(parts) < 2:
            continue
        tag, cmd = parts[0], parts[1].upper()
        rest = parts[2] if len(parts) > 2 else b""
        if cmd == b"CAPABILITY":
            send(b"* CAPABILITY IMAP4rev1 UIDPLUS")
            send(tag + b" OK CAPABILITY completed")
        elif cmd == b"LOGIN":
            u, _, p = rest.partition(b" ")
            u, p = u.strip(b'"'), p.strip(b'"')
            if u == USER.encode() and p == PW.encode():
                authed = True
                send(tag + b" OK LOGIN completed")
            else:
                send(tag + b" NO [AUTHENTICATIONFAILED] Invalid credentials")
        elif not authed:
            send(tag + b" NO not logged in")
        elif cmd == b"STATUS":
            send(b"* STATUS INBOX (UNSEEN %d)" % len(UNSEEN))
            send(tag + b" OK STATUS completed")
        elif cmd in (b"SELECT", b"EXAMINE"):
            send(b"* %d EXISTS" % len(MSGS))
            send(b"* 0 RECENT")
            send(b"* OK [UIDVALIDITY 1] UIDs valid")
            send(b"* FLAGS (\\Seen)")
            send(tag + b" OK [READ-ONLY] EXAMINE completed")
        elif cmd == b"UID" and rest.upper().startswith(b"SEARCH"):
            send(b"* SEARCH " + b" ".join(str(u).encode() for u in UNSEEN))
            send(tag + b" OK SEARCH completed")
        elif cmd == b"UID" and rest.upper().startswith(b"FETCH"):
            ids = rest.split(b" ", 2)[1].decode()
            n = 0
            for u in ids.split(","):
                uid = int(u)
                if uid not in MSGS:
                    continue
                n += 1
                body = MSGS[uid]
                send(b"* %d FETCH (UID %d BODY[HEADER.FIELDS (FROM SUBJECT DATE)] {%d}" % (n, uid, len(body)))
                f.write(body)
                send(b")")
            send(tag + b" OK FETCH completed")
        elif cmd == b"LOGOUT":
            send(b"* BYE mock closing")
            send(tag + b" OK LOGOUT completed")
            return
        elif cmd == b"NOOP":
            send(tag + b" OK NOOP")
        else:
            send(tag + b" BAD unsupported in the mock: " + cmd)


if __name__ == "__main__":
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", PORT))
    srv.listen(4)
    while True:
        conn, _ = srv.accept()
        try:
            serve(conn)
        except (OSError, ValueError):
            pass
        finally:
            conn.close()
