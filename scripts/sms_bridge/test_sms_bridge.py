"""Tests for the SMS bridge. Run with: `python -m unittest` from this folder.

No hardware, no network, no pyserial: `FakeSerial` scripts the bytes a modem would send,
so the AT parsing and the prompt/response dance are tested where they actually break -
against the shapes real SIM800/SIM7600 boards produce.
"""

import unittest

from sms_bridge import (
    ATDriver,
    AtError,
    AtTimeout,
    InboundMessage,
    SerialChannel,
    clean_text,
    drain_inbox,
    inbound_key,
    parse_cmgl,
    parse_operator,
    parse_registration,
    parse_signal,
    run,
    split_at_fields,
)


class FakeSerial:
    """A serial port in a list: `incoming` is what the modem would say next."""

    def __init__(self, incoming=b"", chunk=64, clock=None):
        self.incoming = bytearray(incoming)
        self.written = bytearray()
        self.chunk = chunk
        self.clock = clock
        self.timeout = 0.2
        self.closed = False

    @property
    def in_waiting(self):
        return len(self.incoming)

    def read(self, size=1):
        if not self.incoming:
            # A real port blocks for its timeout here; the fake MOVES TIME instead, so
            # `AtTimeout` is reachable in a test without sleeping for real.
            if self.clock is not None:
                self.clock.advance(0.5)
            return b""
        size = min(size, self.chunk, len(self.incoming))
        chunk, self.incoming = self.incoming[:size], self.incoming[size:]
        return bytes(chunk)

    def write(self, data):
        self.written.extend(data)
        return len(data)

    def flush(self):
        pass

    def close(self):
        self.closed = True


class FakeClock:
    """A clock that only moves when the test says so (bounded timeouts, no sleeping)."""

    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now

    def advance(self, seconds):
        self.now += seconds


def driver_with(incoming, **kwargs):
    clock = FakeClock()
    fake = FakeSerial(incoming, clock=clock)
    driver = ATDriver(
        "COM5",
        factory=lambda port, baud: fake,
        clock=clock,
        command_timeout=kwargs.pop("command_timeout", 1.0),
        send_timeout=kwargs.pop("send_timeout", 1.0),
        prompt_timeout=kwargs.pop("prompt_timeout", 1.0),
    )
    return driver, fake, clock


class CMGLParsingTests(unittest.TestCase):
    REAL = (
        '+CMGL: 1,"REC UNREAD","+639171234567",,"26/11/20,14:30:12+32"\r\n'
        "DONE 000123 4821\r\n"
        '+CMGL: 2,"REC READ","+639200000000",,"26/11/20,14:31:00+32"\r\n'
        "OK\r\n"
        "\r\nOK\r\n"
    )

    def test_two_messages_come_back_with_sender_timestamp_and_body(self):
        self.assertEqual(
            parse_cmgl(self.REAL),
            [
                {
                    "index": 1,
                    "status": "REC UNREAD",
                    "phone": "+639171234567",
                    "scts": "26/11/20,14:30:12+32",
                    "body": "DONE 000123 4821",
                },
                {
                    "index": 2,
                    "status": "REC READ",
                    "phone": "+639200000000",
                    "scts": "26/11/20,14:31:00+32",
                    "body": "OK",
                },
            ],
        )

    def test_a_wrapped_long_message_keeps_all_of_its_lines(self):
        raw = (
            '+CMGL: 7,"REC UNREAD","+639171234567",,"26/11/20,14:30:12+32"\r\n'
            "DONE 000123\r\n"
            "4821\r\n"
            "OK\r\n"
        )
        (message,) = parse_cmgl(raw)
        self.assertEqual(message["body"], "DONE 000123 4821")

    def test_an_empty_sim_is_an_empty_list(self):
        self.assertEqual(parse_cmgl("\r\nOK\r\n"), [])

    def test_an_unreadable_header_is_skipped_not_raised(self):
        raw = (
            '+CMGL: notanindex,"REC UNREAD","+639",,"26"\r\n'
            "junk\r\n"
            '+CMGL: 3,"REC UNREAD","+639171234567",,"26/11/20,14:30:12+32"\r\n'
            "HELP\r\n"
            "OK\r\n"
        )
        (message,) = parse_cmgl(raw)
        self.assertEqual(message["index"], 3)

    def test_a_modem_that_reports_no_timestamp_still_parses(self):
        raw = '+CMGL: 4,"REC UNREAD","+639171234567"\r\nHELP\r\nOK\r\n'
        (message,) = parse_cmgl(raw)
        self.assertEqual(message["scts"], "")
        self.assertEqual(message["body"], "HELP")

    def test_fields_split_on_commas_outside_quotes(self):
        self.assertEqual(
            split_at_fields('1,"REC UNREAD","+639171234567",,"26/11/20,14:30:12+32"'),
            ["1", "REC UNREAD", "+639171234567", "", "26/11/20,14:30:12+32"],
        )


class SmallParsersTests(unittest.TestCase):
    def test_signal(self):
        self.assertEqual(parse_signal("+CSQ: 21,99"), 21)
        self.assertEqual(parse_signal("+CSQ: 99,99"), 0)
        self.assertEqual(parse_signal("ERROR"), 0)

    def test_registration(self):
        self.assertTrue(parse_registration("\r\n+CREG: 0,1\r\n\r\nOK\r\n"))
        self.assertTrue(parse_registration("\r\n+CEREG: 0,5\r\n\r\nOK\r\n"))
        self.assertFalse(parse_registration("\r\n+CREG: 0,2\r\n\r\nOK\r\n"))
        self.assertFalse(parse_registration("\r\nOK\r\n"))

    def test_operator(self):
        self.assertEqual(
            parse_operator('\r\n+COPS: 0,0,"Globe Telecom",7\r\n\r\nOK\r\n'),
            "Globe Telecom",
        )
        self.assertEqual(parse_operator("\r\nOK\r\n"), "")

    def test_the_inbound_key_is_stable_and_distinguishes_messages(self):
        first = inbound_key("+639171234567", "26/11/20,14:30:12+32", "DONE 1 2")
        self.assertEqual(
            first, inbound_key("+639171234567", "26/11/20,14:30:12+32", "DONE 1 2")
        )
        self.assertNotEqual(
            first, inbound_key("+639171234567", "26/11/20,14:30:13+32", "DONE 1 2")
        )
        self.assertEqual(len(first), 64)

    def test_text_is_flattened_to_ascii_on_one_line(self):
        self.assertEqual(
            clean_text("QB PICKUP\r\nCode 4821 ₱"), "QB PICKUP  Code 4821 "
        )


class ChannelTests(unittest.TestCase):
    def test_read_until_returns_the_pattern_index_and_consumes_it(self):
        fake = FakeSerial(b"AT\r\r\nOK\r\n+CSQ: 21,99\r\n")
        channel = SerialChannel("COM5", factory=lambda p, b: fake, clock=FakeClock())
        channel.open()
        index, seen = channel.read_until(["\r\nOK\r\n"], 1.0)
        self.assertEqual(index, 0)
        self.assertIn("OK", seen)
        index, seen = channel.read_until(["+CSQ:"], 1.0)
        self.assertEqual(index, 0)

    def test_a_silent_modem_times_out_instead_of_hanging(self):
        clock = FakeClock()
        fake = FakeSerial(b"", clock=clock)
        channel = SerialChannel("COM5", factory=lambda p, b: fake, clock=clock)
        channel.open()
        with self.assertRaises(AtTimeout):
            channel.read_until([">"], 1.0)

    def test_closing_the_channel_closes_the_port(self):
        fake = FakeSerial(b"")
        channel = SerialChannel("COM5", factory=lambda p, b: fake)
        channel.open()
        channel.close()
        self.assertTrue(fake.closed)


class SendTests(unittest.TestCase):
    def test_a_send_writes_cmgs_then_the_body_and_ctrl_z(self):
        driver, fake, _clock = driver_with(b"\r\n> ")
        driver.channel.open()
        # A second scripted reply for the +CMGS result, appended as the test advances.
        fake.incoming.extend(b"\r\n+CMGS: 12\r\n\r\nOK\r\n")
        driver.send("+639171234567", "DONE 000123 4821")
        self.assertEqual(
            bytes(fake.written),
            b'AT+CMGS="+639171234567"\rDONE 000123 4821\x1a',
        )

    def test_the_prompt_must_arrive_before_the_body_is_typed(self):
        driver, fake, _clock = driver_with(b"")
        driver.channel.open()
        with self.assertRaises(AtTimeout):
            driver.send("+639171234567", "DONE 000123 4821")
        self.assertEqual(bytes(fake.written), b'AT+CMGS="+639171234567"\r')

    def test_an_error_after_the_prompt_is_reported(self):
        driver, _fake, _clock = driver_with(b"\r\n> \r\nERROR\r\n")
        driver.channel.open()
        with self.assertRaises(AtError):
            driver.send("+639171234567", "DONE 000123 4821")

    def test_an_immediate_error_on_the_prompt_is_reported(self):
        driver, _fake, _clock = driver_with(b"\r\nERROR\r\n")
        driver.channel.open()
        with self.assertRaises(AtError):
            driver.send("+639171234567", "DONE 000123 4821")

    def test_an_empty_message_is_refused_without_touching_the_port(self):
        driver, fake, _clock = driver_with(b"")
        driver.channel.open()
        with self.assertRaises(AtError):
            driver.send("+639171234567", "   ")
        self.assertEqual(bytes(fake.written), b"")


class CommandTests(unittest.TestCase):
    def test_ok_returns_the_response_and_error_raises(self):
        driver, _fake, _clock = driver_with(b"\r\n+CPIN: READY\r\n\r\nOK\r\n")
        driver.channel.open()
        self.assertIn("READY", driver.command("AT+CPIN?"))

    def test_error_raises_with_the_modem_text(self):
        driver, _fake, _clock = driver_with(b"\r\n+CME ERROR: 10\r\n")
        driver.channel.open()
        with self.assertRaises(AtError):
            driver.command("AT+CPMS?")


class PollTests(unittest.TestCase):
    def test_polling_parses_and_keys_each_message(self):
        raw = (
            b'+CMGL: 5,"REC UNREAD","+639171234567",,"26/11/20,14:30:12+32"\r\n'
            b"DONE 000123 4821\r\n\r\nOK\r\n"
        )
        driver, fake, _clock = driver_with(b"")
        driver.channel.open()
        fake.incoming.extend(raw)
        (message,) = driver.poll()
        self.assertEqual(message.phone, "+639171234567")
        self.assertEqual(message.text, "DONE 000123 4821")
        self.assertEqual(message.index, 5)
        self.assertEqual(
            message.key,
            inbound_key("+639171234567", "26/11/20,14:30:12+32", "DONE 000123 4821"),
        )

    def test_ack_deletes_that_sim_slot(self):
        driver, fake, _clock = driver_with(b"\r\nOK\r\n")
        driver.channel.open()
        message = type("M", (), {"index": 5})()
        driver.ack(message)
        self.assertEqual(bytes(fake.written), b"AT+CMGD=5\r")


class RunLoopTests(unittest.TestCase):
    """The loop must survive a driver that raises, and stop when asked."""

    class ExplodingDriver:
        name = "boom"

        def __init__(self):
            self.opens = 0
            self.closed = 0

        def open(self):
            self.opens += 1
            if self.opens > 2:
                raise KeyboardInterrupt  # the user pressed Ctrl-C
            raise OSError("the USB adapter was unplugged")

        def close(self):
            self.closed += 1

        def send(self, phone, text):
            raise AssertionError("no message should ever be sent")

        def poll(self):
            return []

        def ack(self, message):
            pass

        def info(self):
            return {}

    class QuietBackend:
        def outbox(self):
            return []

        def result(self, message_id, ok, error=""):
            return {}

        def inbound(self, message):
            return {}

        def heartbeat(self, info):
            return {}

    def test_a_broken_driver_is_retried_rather_than_crashing_the_process(self):
        driver = self.ExplodingDriver()
        sleeps = []
        run(driver, self.QuietBackend(), interval=0, sleep=sleeps.append)
        self.assertGreaterEqual(driver.opens, 1)
        self.assertTrue(sleeps, "the reconnect backoff should have waited")


if __name__ == "__main__":
    unittest.main()


class InboundRetentionTests(unittest.TestCase):
    """Issue 3, bridge side: a refused inbound stays on the SIM (no ack, no delete)."""

    class RecordingDriver:
        def __init__(self, messages):
            self.messages = messages
            self.acked = []

        def poll(self):
            return list(self.messages)

        def ack(self, message):
            self.acked.append(message)

    class FailingBackend:
        def inbound(self, message):
            raise RuntimeError("503 SMS_DISABLED")

    class GoodBackend:
        def __init__(self):
            self.seen = []

        def inbound(self, message):
            self.seen.append(message)
            return {"status": "PROCESSED", "reply": "OK"}

    def _message(self):
        return InboundMessage(
            phone="+639171234567",
            text="DONE 000123 4821",
            received_at="26/11/20,14:30:12+32",
            key="k1",
            index=4,
        )

    def test_a_refused_inbound_is_kept_on_the_sim(self):
        driver = self.RecordingDriver([self._message()])
        drain_inbox(driver, self.FailingBackend())
        self.assertEqual(driver.acked, [])

    def test_an_accepted_inbound_is_deleted_from_the_sim(self):
        driver = self.RecordingDriver([self._message()])
        drain_inbox(driver, self.GoodBackend())
        self.assertEqual(len(driver.acked), 1)
