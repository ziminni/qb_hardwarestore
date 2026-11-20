# SMS bridge — the Bodega checker's phone without the store's Wi-Fi

The Bodega is outside the store's Wi-Fi, so the checker's phone cannot reach the POS
server. This bridge gives the POS a second channel to him: a **bare GSM modem board** on
the shop's own computer sends him the pick-up details, and he replies from his own phone's
SMS app. The backend records the release; nothing else in the shop changes.

```
                shop computer (host)                       Docker Desktop
  ┌────────────────────────────────────────────┐   ┌──────────────────────────────┐
  │  sms_bridge.py   ←──USB/serial──→  modem    │   │  Django backend              │
  │      │            (SIM800/SIM7600/...)      │   │  /api/v1/sms/gateway/*       │
  │      └────── HTTP (X-SMS-Gateway-Key) ──────┼──→│  queue, parser, release,     │
  └────────────────────────────────────────────┘   │  audit                       │
                                                    └──────────────────────────────┘
```

The bridge **only moves messages**. Every decision — what the text says, whose phone may
release, whether the code is right, what is still uncollected — is made by the backend,
inside one database transaction. A compromised bridge can waste load; it cannot move
goods.

---

## 1. What the checker receives and replies

The POS texts him when a sale takes goods from a Bodega shelf:

```
QB PICKUP TRX-20261120-0001: 10 BAG Portland Cement 40kg; 2 SHEET GI Sheet.
Code 4821. Reply: DONE TRX-20261120-0001 4821
```

`DELIVERY` replaces `PICKUP` when the sale has a delivery slip. A long list is cut with
`+3 more` — the code and the reply instruction are never dropped, and the reply releases
**everything** still uncollected on that receipt.

He replies from his own SMS app (his own load):

```
DONE 000123 4821                 (or the OR number / transaction number on the slip)
DONE 000123 4821 Juan Cruz       (with the receiver's name)
```

`OK`, `ACCOMPLISHED`, `RELEASED`, `COMPLETE` and lowercase work too, as do quotes and
colons: `'000123':'accomplished' 4821` parses. `HELP` answers with the format.

The POS replies `OK BR-20261120-0001 000123 released`, or says what went wrong (wrong
code with the tries left, receipt already released, no such receipt, locked after five
wrong codes — then the app or a phone call to the store).

## 2. Backend settings

Both settings are read from the environment by `backend_django/config/settings.py` with
safe defaults (`os.environ.get("SMS_ENABLED", "false")`, `SMS_GATEWAY_KEY` empty), and the
backend container gets them the same way every other setting arrives — **from
`backend_django/.env`**, mounted by `docker-compose.yml`'s `env_file:`:

```dotenv
# backend_django/.env  (NOT committed — it holds a secret)
SMS_ENABLED=true
SMS_GATEWAY_KEY=<paste the generated key>
```

```bash
python -c "import secrets; print(secrets.token_urlsafe(32))"   # generate the key
```

`docker-compose.yml` deliberately sets **no** `environment:` keys for SMS. A hardcoded
`SMS_ENABLED: "false"` in that block would win over `.env` and quietly pin the feature
off no matter what the file says — that trap is why the keys live only in `.env` (or in a
shell export for a one-off run).

| Variable | Default | Meaning |
| --- | --- | --- |
| `SMS_ENABLED` | `false` | `true` starts queueing a text per Bodega sale **and** lets inbound replies release goods. While it is `false` the gateway answers inbound with **503 `SMS_DISABLED`**, so the bridge keeps the SMS on the SIM instead of deleting it. |
| `SMS_GATEWAY_KEY` | *(empty)* | The bridge's key, **at least 24 characters**. Empty or short = every gateway call is refused (403). |

**Keep the key out of the command line.** `--key <secret>` is visible in `ps`, in the
process list of Task Manager, and in the shell history (`~/.bash_history`,
`ConsoleHost_history.txt`). Prefer the environment:

```bash
export SMS_GATEWAY_KEY=...          # POSIX
$env:SMS_GATEWAY_KEY = "..."        # PowerShell
python sms_bridge.py --api http://localhost:8000 --port COM5
```

**Transport.** `http://localhost:8000` (or `127.0.0.1`) never leaves the machine, which is
the normal install. If the backend is on **another computer**, use **HTTPS** — the key
travels in a request header and plain HTTP over a LAN or the internet is readable by
anyone on the path. Put the API behind TLS (the repo's `tunnel/` profile, or any reverse
proxy) and point `--api` at the `https://` URL.

The same key goes to the bridge. A staff page shows the live state at
`GET /api/v1/sms/status/` (Admin / Store Manager): enabled, last heartbeat, queued and
failed counts.

## 3. Register the checker's number (once)

Only numbers on the contact list are answered — an unknown sender gets **no reply**, so
spam costs the shop nothing. The number must belong to an account that holds the **Bodega
Checker** role (Stock Manager / Store Manager / Admin works too).

**Admin page:** `/admin/sms/smscontact/` → Add.

**API** (Admin only):

```bash
curl -X POST http://localhost:8000/api/v1/sms/contacts/ \
  -H "Authorization: Bearer <admin access token>" \
  -H "Content-Type: application/json" \
  -d '{"phone": "09171234567", "user": 7, "label": "Bodega checker"}'
```

`09171234567`, `9171234567`, `+639171234567` and `639171234567` all normalize to
`+639171234567`; a number that is not a Philippine mobile is refused.

## 4. Install and run the bridge

Python 3.10+ on the computer that has the modem plugged in (Windows or Linux):

```bash
cd scripts/sms_bridge
python -m pip install -r requirements.txt
python sms_bridge.py --api http://localhost:8000 --key <SMS_GATEWAY_KEY> \
    --driver at --port COM5 --baud 115200
```

Every flag has an environment fallback: `SMS_API`, `SMS_GATEWAY_KEY`, `SMS_DRIVER`,
`SMS_PORT`, `SMS_BAUD`, `SMS_INTERVAL`. Logs go to stdout with timestamps:

```
[2026-11-20 10:41:02] bridge starting: http://localhost:8000 driver=at port=COM5
[2026-11-20 10:41:04] modem ready
[2026-11-20 10:41:10] sent 12 to +639171234567
[2026-11-20 10:44:31] inbound from +639171234567: PROCESSED OK BR-20261120-0001 000123 released
```

Try it without hardware first (`--driver console`): outgoing texts are printed, and
anything you type as `+639171234567 DONE 000123 4821` is treated as an incoming SMS.

`--once` runs a single cycle and exits (useful for a cron/Task Scheduler smoke test).

## 5. Wiring a bare board (read this before buying)

* **No universal-modem promise.** These boards implement 3GPP TS 27.005/27.007 AT
  commands, which is why one driver is enough — but firmware differs per board and
  vendor: `AT+CMGL="ALL"` quoting, `AT+CPMS` storage names and the trailing `OK` are the
  usual places a clone surprises you. The bridge tolerates the common shapes (see
  `parse_cmgl`) and reports what it cannot parse. **Verify your exact board once** with a
  real SIM and a real incoming SMS before the shop relies on it; nothing here was tested
  against every model, only against the command set those boards document.
* **USB-to-TTL adapter:** CH340 or CP2102. Wire **TX↔RX crossed** (adapter TX → board RX,
  adapter RX → board TX) and **GND↔GND**. Common ground is not optional.
* **Power:** SIM800-class boards take **3.7–4.2 V and up to ~2 A peaks** while
  transmitting. **Do not** power the board from the adapter's 3.3 V/5 V pin — it browns out
  mid-transmission and you get mysterious resets and unanswered `AT`. Use a dedicated
  supply (a good 5 V/2 A supply through the board's own regulator, or a Li-ion cell) with
  the grounds tied together. SIM7600/A7670/EC25 boards are more forgiving but still want
  2 A.
* **Antenna:** must be attached before power-on. Without it the modem may not register at
  all, and transmitting without one can damage the module.
* **4G/LTE matters in the Philippines:** 2G-only boards (SIM800/SIM900) may fail to
  register on current networks. A SIM7600/A7670/EC25-class board with 4G is the safe buy.
* **SIM:** a normal prepaid SIM, PIN **disabled** (the bridge refuses to start on a
  PIN-locked SIM), with load/credit for replies.
* **Port name:** Windows → Device Manager → *Ports (COM & LPT)* → e.g. `COM5`. Linux →
  `/dev/ttyUSB0` (add your user to the `dialout` group). The port must NOT be open in a
  terminal program at the same time.
* The bridge checks `AT`, `AT+CPIN?` (SIM ready), `AT+CREG?`/`AT+CEREG?` (registered) and
  reports `AT+CSQ` signal strength in the heartbeat. It reconnects with backoff if the
  adapter is unplugged; unread messages stay on the SIM until the backend accepts them.

## 6. Tests

```bash
cd scripts/sms_bridge
python -m unittest          # 24 tests, no hardware, no pyserial needed
```

The suite scripts a fake serial port: `AT+CMGL` parsing (including a body that is itself
`OK`), the `>` prompt before a body is typed, `Ctrl-Z`, `+CMGS:`, `ERROR`, timeouts, key
hashing and the reconnect loop.

## 7. Known limits and what this link does NOT protect against

* **A reply releases the WHOLE remaining claim — there is no partial release by SMS.**
  Partial hand-overs still need the Bodega app. If the receipt changed after the text was
  sent (a return, or a release made at the counter), the reply is REFUSED with "receipt
  changed since the text was sent" and the app must be used: the phone holds a stale list,
  so "everything" would no longer mean what the checker is looking at.
* **This is NOT strong authentication.** The contact whitelist plus a one-time code sent
  in the same message protects against a stranger who does not hold the phone or the text.
  It does **not** protect against:
  * **SIM takeover / SIM swap** — whoever controls the number receives the code;
  * **SMS interception** (SS7, a compromised handset, a forwarding rule, a phone left
    unlocked) — the code is in the message thread, in plain text, by design;
  * a checker who photocopies the thread for someone else.
  Treat the code as a speed bump that makes blind guessing cost 5 tries per receipt, not as
  proof of identity. Money-sized trust still comes from the app's login and the audit
  trail, which records which account each SMS release was made as.
* **Concatenated (multipart) SMS are treated part by part.** A very long *incoming*
  message may be processed as several pieces (the first usually carries the command, the
  rest are rejected with the format help). Outgoing texts are composed to fit 160 GSM
  characters precisely so this does not happen.
* **Delivery is AT-LEAST-ONCE, not exactly once.** The queue claims rows with
  `SELECT … FOR UPDATE SKIP LOCKED` and a 5-minute lease, so two bridges cannot claim the
  same row at the same time — but if the modem sends a text and the bridge dies (or the
  HTTP acknowledgement is lost) before reporting, the lease expires and the message is
  sent **again**. That duplicate is harmless by design: it carries the SAME one-time code,
  and a second `DONE` finds the ticket already used and answers "already released" with no
  second release. Do not read the thread as proof that exactly one text was delivered.
* **A stale lease can also duplicate a reply path**, in the same harmless way: the code,
  not the message count, is what authorises a release.
* **Partial offline fulfilment is not implemented**, by decision: an SMS reply is
  all-or-nothing, and a shop that needs partial hand-overs uses the app.
* **Android-phone HTTP gateway:** not implemented. `Driver` in `sms_bridge.py` is the seam
  (`send`/`poll`/`ack`/`info`) if a phone-based SMS gateway is ever preferred to a board.
* Deleting the modem's copy of a message happens only after the backend answers 2xx, so a
  backend outage delays texts instead of losing them. The backend is still idempotent by
  `key` if a redelivery slips through.
