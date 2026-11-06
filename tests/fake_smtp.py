#!/usr/bin/env python3
"""Fake upstream SMTP server: accepts everything and logs what it receives."""
import base64
import socketserver
import sys


class Handler(socketserver.StreamRequestHandler):
    def say(self, line):
        self.wfile.write((line + "\r\n").encode())
        self.wfile.flush()

    def handle(self):
        self.say("220 fake ESMTP")
        in_data = False
        while True:
            raw = self.rfile.readline()
            if not raw:
                return
            line = raw.decode("utf-8", "replace").rstrip("\r\n")
            if in_data:
                print("DATA|" + line, flush=True)
                if line == ".":
                    in_data = False
                    self.say("250 queued")
                continue
            print("CMD|" + line, flush=True)
            command = line.upper()
            if command.startswith("EHLO"):
                self.wfile.write(b"250-fake\r\n250-AUTH PLAIN\r\n250-DSN\r\n250 8BITMIME\r\n")
                self.wfile.flush()
            elif command.startswith("AUTH PLAIN"):
                password = base64.b64decode(line.split(" ", 2)[2]).split(b"\0")[2]
                print("PASSWORD|[" + password.decode() + "]", flush=True)
                self.say("235 ok")
            elif command == "DATA":
                in_data = True
                self.say("354 go")
            elif command == "QUIT":
                self.say("221 bye")
                return
            else:
                self.say("250 ok")


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


Server(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
