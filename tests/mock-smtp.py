#!/usr/bin/env python3
"""A loopback SMTP impersonator for ewe-mail's test — plain TCP on 127.0.0.1
(the tool allows that only with EWE_MAIL_INSECURE=1), one client at a time.
EHLO, AUTH PLAIN (initial response or challenge) and AUTH LOGIN, QUIT. It
NEVER relays anything: MAIL/RCPT/DATA are refused with 503 and logged, so a
test can prove nothing was sent.
Usage: mock-smtp.py <port> [--log FILE] [user:password ...]
       (default account tester:mail-pass; every command line goes to FILE)
"""
import base64
import socket
import sys

args = sys.argv[1:]
PORT = int(args.pop(0))
LOG = None
if "--log" in args:
    i = args.index("--log")
    LOG = args[i + 1]
    del args[i:i + 2]
USERS = dict(a.split(":", 1) for a in args) or {"tester": "mail-pass"}


def log(line):
    if LOG:
        with open(LOG, "a") as f:
            f.write(line + "\n")


def serve(conn):
    f = conn.makefile("rwb", buffering=0)

    def send(line):
        f.write(line.encode() + b"\r\n")

    def read():
        raw = f.readline()
        return raw.rstrip(b"\r\n").decode("utf-8", "replace") if raw else None

    def check(user, pw):
        return USERS.get(user) == pw and user != ""

    send("220 mock-smtp ESMTP ready")
    while True:
        line = read()
        if line is None:
            return
        verb = line.split(" ", 1)[0].upper()
        log(verb if verb == "AUTH" else line)   # never log credentials
        if verb in ("EHLO", "HELO"):
            send("250-mock-smtp")
            send("250-AUTH PLAIN LOGIN")
            send("250 8BITMIME")
        elif verb == "AUTH":
            parts = line.split()
            mech = parts[1].upper() if len(parts) > 1 else ""
            try:
                if mech == "PLAIN":
                    if len(parts) > 2:
                        blob = parts[2]
                    else:
                        send("334 ")
                        blob = read() or ""
                    _, u, p = base64.b64decode(blob).decode().split("\0")
                elif mech == "LOGIN":
                    if len(parts) > 2:
                        u = base64.b64decode(parts[2]).decode()
                    else:
                        send("334 " + base64.b64encode(b"Username:").decode())
                        u = base64.b64decode(read() or "").decode()
                    send("334 " + base64.b64encode(b"Password:").decode())
                    p = base64.b64decode(read() or "").decode()
                else:
                    send("504 5.5.4 unrecognized mechanism")
                    continue
            except (ValueError, UnicodeDecodeError):
                send("501 5.5.2 bad auth data")
                continue
            if check(u, p):
                send("235 2.7.0 Authentication successful")
            else:
                send("535 5.7.8 Authentication credentials invalid")
        elif verb in ("MAIL", "RCPT", "DATA", "BDAT"):
            send("503 5.5.1 this mock never sends mail")
        elif verb == "QUIT":
            send("221 2.0.0 bye")
            return
        elif verb in ("NOOP", "RSET"):
            send("250 OK")
        else:
            send("502 5.5.2 command not recognized")


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
