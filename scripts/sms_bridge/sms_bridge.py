#!/usr/bin/env python3
"""SMS bridge: move text between a GSM modem and the BuildPro backend.

WHY this is a separate process: the backend runs in Docker Desktop on Windows, which
cannot pass a COM/USB serial port into a container. So the container owns every DECISION
(what to text, who may release, what the code is) and this script on the host owns the
HARDWARE: it takes queued messages out of `/api/v1/sms/gateway/outbox/`, hands them to the
modem, reports what happened, then posts whatever arrived back to
`/api/v1/sms/gateway/inbound/`.

Run it on the shop's own computer, next to Docker:

    python sms_bridge.py --api http://localhost:8000 --key <SMS_GATEWAY_KEY> \
        --driver at --port COM5 --baud 115200

Testing without hardware:

    python sms_bridge.py --api http://localhost:8000 --key <KEY> --driver console

The bridge never decides anything: it does not know what a release is, it cannot move
stock, and a message it fails to deliver is retried by the backend's queue.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import queue
import re
import sys
import threading
import time
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any

DEFAULT_API = "http://localhost:8000"
DEFAULT_INTERVAL = 3.0
HEARTBEAT_SECONDS = 60.0
OUTBOX_LIMIT = 5
#: A text-mode SMS longer than this is split by the network (each part billed).
SMS_LENGTH = 160


def log(message):
    stamp = datetime.now(UTC).astimezone().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{stamp}] {message}", flush=True)


# ---------------------------------------------------------------------------
# AT parsing (pure functions: unit-tested without hardware)
# ---------------------------------------------------------------------------


class AtError(RuntimeError):
    """The modem said ERROR, or stopped answering."""


class AtTimeout(AtError):
    """Nothing (or not what we waited for) arrived before the deadline."""


def split_at_fields(text):
    """`1,"REC UNREAD","+63917...",,"26/11/20,14:30:12+32"` -> its five fields.

    Splits on commas that are OUTSIDE quotes, which is what makes the timestamp
    (itself full of punctuation) come out whole and the empty 4th field survive.
    """
    fields = []
    current = []
    in_quotes = False
    for char in text:
        if char == '"':
            in_quotes = not in_quotes  # the quotes delimit fields; they are not content
            continue
        if char == "," and not in_quotes:
            fields.append("".join(current).strip())
            current = []
            continue
        current.append(char)
    fields.append("".join(current).strip())
    return fields


_CMGL_HEADER = re.compile(r"^\+CMGL:\s*(?P<rest>.*)$")


def parse_cmgl(response):
    """`AT+CMGL="ALL"` text-mode output -> `[{index, status, phone, scts, body}]`.

    Each `+CMGL:` line is a header; the lines under it are the message body (a long SMS
    arrives wrapped, and the parts are joined with a space). A trailing `OK` ends the
    list. Anything unparseable is skipped rather than raised: one odd row must not stop
    the other messages in the same batch.
    """
    messages = []
    current = None
    lines = [line.rstrip("\r\n") for line in (response or "").splitlines()]
    lines = [line for line in lines if line.strip()]
    last = len(lines) - 1
    for position, line in enumerate(lines):
        header = _CMGL_HEADER.match(line.strip())
        if header:
            fields = split_at_fields(header.group("rest"))
            if not fields or not fields[0].isdigit():
                current = None
                continue
            current = {
                "index": int(fields[0]),
                "status": fields[1] if len(fields) > 1 else "",
                "phone": fields[2] if len(fields) > 2 else "",
                "scts": fields[4] if len(fields) > 4 else "",
                "lines": [],
            }
            messages.append(current)
            continue
        # `OK` ends the list - but a message whose whole body is `OK` is the same two
        # characters. Only the LAST one can be the terminator; anything earlier is text.
        if line.strip() in {"OK", "ERROR"} and position == last:
            current = None
            continue
        if current is not None:
            current["lines"].append(line.strip())
    parsed = []
    for message in messages:
        body = " ".join(message["lines"]).strip()
        parsed.append(
            {
                "index": message["index"],
                "status": message["status"],
                "phone": message["phone"],
                "scts": message["scts"],
                "body": body,
            }
        )
    return parsed


def parse_signal(response):
    """`+CSQ: 21,99` -> 21 (99 means "not known", which is reported as 0)."""
    match = re.search(r"\+CSQ:\s*(\d+)", response or "")
    if not match:
        return 0
    value = int(match.group(1))
    return 0 if value == 99 else value


def parse_registration(response):
    """True for `+CREG: 0,1` / `+CREG: 0,5` (home or roaming), False otherwise."""
    match = re.search(r"\+C[E]?REG:\s*\d+\s*,\s*(\d+)", response or "")
    return bool(match) and match.group(1) in {"1", "5"}


def parse_operator(response):
    """`+COPS: 0,0,"Globe Telecom"` -> `Globe Telecom`."""
    match = re.search(r'\+COPS:\s*\d+,\d+,"([^"]*)"', response or "")
    return match.group(1) if match else ""


def inbound_key(phone, scts, body):
    """The bridge's idempotency token: same sender, timestamp and text -> same answer.

    A modem that is unplugged mid-post leaves the message on the SIM; on reconnect it is
    sent again, and this key is what stops the backend releasing the same claim twice.
    """
    material = f"{phone}|{scts}|{body}".encode()
    return hashlib.sha256(material).hexdigest()


def clean_text(text):
    """One line, ASCII only, no `\\r`: a stray CR would end the SMS early in text mode."""
    flat = (text or "").replace("\r", " ").replace("\n", " ")
    return "".join(ch for ch in flat if 32 <= ord(ch) < 127)


# ---------------------------------------------------------------------------
# Transport: a line reader over anything that speaks pyserial's tiny API
# ---------------------------------------------------------------------------


def pyserial_factory(port, baud):
    """Open a real modem. Imported HERE so the tests need no pyserial and no device."""
    import serial  # imported late: the tests need no pyserial

    return serial.Serial(port=port, baudrate=baud, timeout=0.2)


class SerialChannel:
    """Read a serial-like object until a pattern appears, or the deadline passes."""

    def __init__(self, port, baud=115200, factory=None, clock=time.monotonic):
        self.port = port
        self.baud = baud
        self.factory = factory or pyserial_factory
        self.clock = clock
        # The open serial object, set only by `open()`. Typed `Any` on purpose: it is a
        # pyserial port here and a scripted fake in the tests, and only the three methods
        # used below (`write`, `flush`, `read`/`in_waiting`) are part of the contract.
        self.port_handle: Any = None
        self._buffer = ""

    def open(self):
        self.port_handle = self.factory(self.port, self.baud)
        self._buffer = ""
        return self

    def close(self):
        handle, self.port_handle = self.port_handle, None
        if handle is not None:
            handle.close()

    def write(self, text):
        self.port_handle.write(text.encode("ascii", "ignore"))
        self.port_handle.flush()

    def read_until(self, patterns, timeout):
        """Return `(index, matched_text)` for the first pattern seen, else raise.

        Raises `AtTimeout` at the deadline, which is what turns "the modem is asleep" into
        a reported failure instead of a hung bridge.
        """
        deadline = self.clock() + timeout
        while True:
            for index, pattern in enumerate(patterns):
                position = self._buffer.find(pattern)
                if position >= 0:
                    seen = self._buffer[: position + len(pattern)]
                    self._buffer = self._buffer[position + len(pattern) :]
                    return index, seen
            if self.clock() > deadline:
                raise AtTimeout(f"no {patterns!r} within {timeout}s (port {self.port})")
            waiting = getattr(self.port_handle, "in_waiting", 0) or 1
            chunk = self.port_handle.read(waiting)
            if chunk:
                self._buffer += (
                    chunk.decode("ascii", "replace")
                    if isinstance(chunk, (bytes, bytearray))
                    else chunk
                )


@dataclass
class InboundMessage:
    """One SMS read off the SIM, plus the handle needed to delete it afterwards."""

    phone: str
    text: str
    received_at: str
    key: str
    index: int = field(default=0)


# ---------------------------------------------------------------------------
# Drivers
# ---------------------------------------------------------------------------


class Driver:
    """What the loop needs from any modem. Three methods, so a phone app can join later."""

    name = "base"

    def open(self):
        return self

    def close(self):
        pass

    def send(self, phone, text):
        raise NotImplementedError

    def poll(self):
        raise NotImplementedError

    def ack(self, message):
        """Called ONLY after the backend accepted the message (then it is deleted)."""

    def info(self):
        return {"driver": self.name}


class ATDriver(Driver):
    """A bare GSM board over 3GPP TS 27.005 text mode (SIM800, SIM900, SIM7600, A7670...).

    Text mode (`AT+CMGF=1`) with the GSM character set, and storage on the SIM's own
    message slots so a power cut does not lose an inbound DONE.
    """

    name = "at"

    def __init__(
        self,
        port,
        baud=115200,
        factory=None,
        command_timeout=5.0,
        send_timeout=60.0,
        prompt_timeout=20.0,
        clock=time.monotonic,
    ):
        self.channel = SerialChannel(port, baud, factory=factory, clock=clock)
        self.command_timeout = command_timeout
        self.send_timeout = send_timeout
        self.prompt_timeout = prompt_timeout
        self.details = {}

    # -- lifecycle ---------------------------------------------------------
    def open(self):
        self.channel.open()
        self._initialise()
        return self

    def close(self):
        self.channel.close()

    def _initialise(self):
        self.command("AT")
        self.command("ATE0")  # no echo: the response is what matters
        self.command("AT+CMEE=2")  # numeric errors become readable
        self.command("AT+CMGF=1")  # SMS text mode
        self.command('AT+CSCS="GSM"')
        try:
            self.command('AT+CPMS="SM","SM","SM"')
        except AtError as error:
            # A modem with a different storage layout still sends and receives; refusing
            # to start here would ground a working board over a preference.
            log(f"note: message storage left at the modem's default ({error})")

        sim = self.command("AT+CPIN?")
        if "READY" not in sim.upper():
            raise AtError(
                f"SIM is not ready ({sim.strip()}) - is it inserted and unlocked?"
            )
        # Registration can take a few seconds after power-up; one retry is enough to
        # tell "still looking" from "no signal at all".
        if not self._registered():
            time.sleep(3)
            if not self._registered():
                raise AtError(
                    "the modem has not registered on the network (antenna? SIM credit?)"
                )
        log("modem ready")

    def _registered(self):
        for command in ("AT+CREG?", "AT+CEREG?"):
            try:
                if parse_registration(self.command(command)):
                    return True
            except AtError:
                continue
        return False

    # -- commands ----------------------------------------------------------
    def command(self, text, timeout=None):
        """Send one AT command and return everything up to `OK` (raises on ERROR)."""
        self.channel.write(f"{text}\r")
        index, seen = self.channel.read_until(
            ["\r\nOK\r\n", "\r\nERROR\r\n", "+CME ERROR", "+CMS ERROR"],
            timeout or self.command_timeout,
        )
        if index != 0:
            raise AtError(f"{text} -> {seen.strip()}")
        return seen

    # -- outbound ----------------------------------------------------------
    def send(self, phone, text):
        body = clean_text(text).strip()[:SMS_LENGTH]
        if not body:
            raise AtError("refusing to send an empty message")
        self.channel.write(f'AT+CMGS="{phone}"\r')
        index, seen = self.channel.read_until(
            ["\r\n>", ">", "\r\nERROR\r\n"], self.prompt_timeout
        )
        if "ERROR" in seen:
            raise AtError(f'AT+CMGS="{phone}" refused ({seen.strip()})')
        if index not in (0, 1):
            # The `>` prompt is what says "send the body now"; writing without it types
            # the message into the command line and the modem answers ERROR.
            raise AtError(f'no ">" prompt for {phone} ({seen.strip()})')
        self.channel.write(body + "\x1a")
        index, seen = self.channel.read_until(
            ["+CMGS:", "\r\nERROR\r\n", "+CMS ERROR", "+CME ERROR"], self.send_timeout
        )
        if index != 0:
            raise AtError(f"send to {phone} failed ({seen.strip()})")
        # Drain the trailing OK so the next command does not read this one's answer.
        try:
            self.channel.read_until(
                ["\r\nOK\r\n", "\r\nERROR\r\n"], self.command_timeout
            )
        except AtError:
            pass
        return seen.strip()

    # -- inbound -----------------------------------------------------------
    def poll(self):
        response = self.command('AT+CMGL="ALL"', timeout=30)
        messages = []
        for row in parse_cmgl(response):
            messages.append(
                InboundMessage(
                    phone=row["phone"],
                    text=row["body"],
                    received_at=row["scts"],
                    key=inbound_key(row["phone"], row["scts"], row["body"]),
                    index=row["index"],
                )
            )
        return messages

    def ack(self, message):
        """Delete the SIM slot: the backend has it, so the modem must not redeliver it."""
        self.command(f"AT+CMGD={message.index}")

    # -- status ------------------------------------------------------------
    def info(self):
        details = {
            "driver": self.name,
            "port": self.channel.port,
            "baud": self.channel.baud,
        }
        try:
            details["signal"] = parse_signal(self.command("AT+CSQ"))
        except AtError:
            details["signal"] = 0
        try:
            details["operator"] = parse_operator(self.command("AT+COPS?"))
        except AtError:
            details["operator"] = ""
        details["registered"] = self._registered()
        return details


class ConsoleDriver(Driver):
    """No hardware: outgoing texts are printed, incoming ones are typed on stdin.

    Type a line exactly as the phone would send it:

        +639171234567 DONE 000123 4821
    """

    name = "console"

    def __init__(self, stream=None):
        self.stream = stream or sys.stdin
        self.inbox = queue.Queue()
        self._stop = threading.Event()
        self._reader = None

    def open(self):
        self._reader = threading.Thread(target=self._read_lines, daemon=True)
        self._reader.start()
        log("console driver: type `+639171234567 DONE 000123 4821` to simulate a reply")
        return self

    def _read_lines(self):
        while not self._stop.is_set():
            line = self.stream.readline()
            if not line:
                time.sleep(0.2)
                continue
            line = line.strip()
            if not line:
                continue
            parts = line.split(maxsplit=1)
            if len(parts) != 2:
                log("console: expected `<phone> <text>`")
                continue
            phone, text = parts
            stamp = datetime.now(UTC).strftime("%y/%m/%d,%H:%M:%S+00")
            self.inbox.put(
                InboundMessage(
                    phone=phone,
                    text=text,
                    received_at=stamp,
                    key=inbound_key(phone, stamp, text),
                )
            )

    def close(self):
        self._stop.set()

    def send(self, phone, text):
        print(f"  -> SMS to {phone}: {text}", flush=True)

    def poll(self):
        messages = []
        while True:
            try:
                messages.append(self.inbox.get_nowait())
            except queue.Empty:
                return messages

    def ack(self, message):
        pass

    def info(self):
        return {
            "driver": self.name,
            "port": "stdin",
            "signal": 0,
            "operator": "console",
        }


# ---------------------------------------------------------------------------
# Backend client
# ---------------------------------------------------------------------------


class Backend:
    """The four gateway calls, and nothing else."""

    def __init__(self, api, key, timeout=15.0, session=None):
        self.api = api.rstrip("/")
        self.key = key
        self.timeout = timeout
        self._session = session

    @property
    def session(self):
        if self._session is None:
            import requests  # imported late: `--help` works without it

            self._session = requests.Session()
        return self._session

    @property
    def headers(self):
        return {"X-SMS-Gateway-Key": self.key}

    def outbox(self, limit=OUTBOX_LIMIT):
        response = self.session.get(
            f"{self.api}/api/v1/sms/gateway/outbox/",
            params={"limit": limit},
            headers=self.headers,
            timeout=self.timeout,
        )
        response.raise_for_status()
        return response.json()

    def result(self, message_id, ok, error=""):
        response = self.session.post(
            f"{self.api}/api/v1/sms/gateway/outbox/{message_id}/result/",
            json={"ok": ok, "error": error},
            headers=self.headers,
            timeout=self.timeout,
        )
        response.raise_for_status()
        return response.json()

    def inbound(self, message):
        response = self.session.post(
            f"{self.api}/api/v1/sms/gateway/inbound/",
            json={
                "from": message.phone,
                "body": message.text,
                "received_at": message.received_at,
                "key": message.key,
            },
            headers=self.headers,
            timeout=self.timeout,
        )
        response.raise_for_status()
        return response.json()

    def heartbeat(self, info):
        response = self.session.post(
            f"{self.api}/api/v1/sms/gateway/heartbeat/",
            json={"info": info},
            headers=self.headers,
            timeout=self.timeout,
        )
        response.raise_for_status()
        return response.json()


# ---------------------------------------------------------------------------
# The loop
# ---------------------------------------------------------------------------


def drain_outbox(driver, backend):
    """Send every queued message, reporting each result to the backend."""
    sent = 0
    for message in backend.outbox():
        try:
            driver.send(message["phone"], message["body"])
        except Exception as error:  # noqa: BLE001 - one bad message must not stop the rest
            log(f"send {message['id']} to {message['phone']} failed: {error}")
            backend.result(message["id"], ok=False, error=str(error)[:500])
            continue
        backend.result(message["id"], ok=True)
        sent += 1
        log(f"sent {message['id']} to {message['phone']}")
    return sent


def drain_inbox(driver, backend):
    """Post every received message, and delete it from the SIM only once accepted."""
    handled = 0
    for message in driver.poll():
        try:
            answer = backend.inbound(message)
        except Exception as error:  # noqa: BLE001 - stay on the SIM and retry next cycle
            log(f"inbound from {message.phone} not accepted, kept on the SIM: {error}")
            continue
        driver.ack(message)
        handled += 1
        log(
            f"inbound from {message.phone}: {answer.get('status')} {answer.get('reply', '')}"
        )
    return handled


def run(
    driver,
    backend,
    interval=DEFAULT_INTERVAL,
    once=False,
    clock=time.monotonic,
    sleep=time.sleep,
):
    """One heartbeat/outbox/inbox cycle every `interval` seconds, reconnect on failure."""
    last_heartbeat = 0.0
    backoff = 1.0
    while True:
        try:
            driver.open()
            backoff = 1.0
            while True:
                if clock() - last_heartbeat >= HEARTBEAT_SECONDS:
                    try:
                        backend.heartbeat(driver.info())
                    except Exception as error:  # noqa: BLE001
                        log(f"heartbeat failed: {error}")
                    last_heartbeat = clock()
                drain_outbox(driver, backend)
                drain_inbox(driver, backend)
                if once:
                    return
                sleep(interval)
        except KeyboardInterrupt:
            log("stopping")
            return
        except Exception as error:  # noqa: BLE001 - serial errors, backend down, anything
            log(f"loop error: {error}; reconnecting in {backoff:.0f}s")
            try:
                driver.close()
            except Exception as close_error:  # noqa: BLE001
                log(f"could not close the port cleanly: {close_error}")
            sleep(backoff)
            backoff = min(backoff * 2, 60.0)


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------


def build_parser():
    parser = argparse.ArgumentParser(
        description="BuildPro SMS bridge (Bodega pick-ups)"
    )
    parser.add_argument(
        "--api",
        default=os.environ.get("SMS_API", DEFAULT_API),
        help="backend base URL (env SMS_API)",
    )
    parser.add_argument(
        "--key",
        default=os.environ.get("SMS_GATEWAY_KEY", ""),
        help="the backend's SMS_GATEWAY_KEY (env SMS_GATEWAY_KEY)",
    )
    parser.add_argument(
        "--driver",
        default=os.environ.get("SMS_DRIVER", "at"),
        choices=["at", "console"],
        help="hardware driver (env SMS_DRIVER)",
    )
    parser.add_argument(
        "--port",
        default=os.environ.get("SMS_PORT", ""),
        help="serial port, e.g. COM5 or /dev/ttyUSB0 (env SMS_PORT)",
    )
    parser.add_argument(
        "--baud",
        type=int,
        default=int(os.environ.get("SMS_BAUD", "115200")),
        help="serial baud rate (env SMS_BAUD)",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=float(os.environ.get("SMS_INTERVAL", DEFAULT_INTERVAL)),
        help="seconds between cycles (env SMS_INTERVAL)",
    )
    parser.add_argument("--once", action="store_true", help="one cycle, then exit")
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    if not args.key:
        print("No gateway key. Pass --key or set SMS_GATEWAY_KEY.", file=sys.stderr)
        return 2
    if args.driver == "at" and not args.port:
        print("--driver at needs --port (COM5, /dev/ttyUSB0, ...).", file=sys.stderr)
        return 2
    driver = ATDriver(args.port, args.baud) if args.driver == "at" else ConsoleDriver()
    backend = Backend(args.api, args.key)
    log(f"bridge starting: {args.api} driver={args.driver} port={args.port or '-'}")
    try:
        run(driver, backend, interval=args.interval, once=args.once)
    except KeyboardInterrupt:
        log("stopping")
    finally:
        driver.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
