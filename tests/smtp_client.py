#!/usr/bin/env python3
"""Send one mail: smtp_client.py PORT MAIL_FROM RCPT. Prints the last SMTP reply code."""
import socket
import sys

port, mail_from, rcpt = int(sys.argv[1]), sys.argv[2], sys.argv[3]
sock = socket.create_connection(("127.0.0.1", port), timeout=10)
replies = sock.makefile("rb")


def reply():
    while True:
        line = replies.readline().decode("utf-8", "replace")
        if len(line) < 4 or line[3] != "-":
            return line[:3]


def send(command):
    sock.sendall((command + "\r\n").encode())
    return reply()


def deliver():
    reply()
    send("EHLO test")
    code = send(f"MAIL FROM:<{mail_from}>")
    if not code.startswith("2"):
        return code
    code = send(f"RCPT TO:<{rcpt}>")
    if not code.startswith("2"):
        return code
    send("DATA")
    sock.sendall(b"From: header@client.example\r\nSubject: test\r\nBcc: hidden@x.example\r\n\r\nbody\r\n")
    return send(".")


print(deliver())
send("QUIT")
