"""Server-side reference ledger for trusted verifyERC20Payment output.

Never expose credit() directly to customer-supplied JSON. RPC verification must
run in your trusted backend, against your allowlisted token and authenticated order.
SQLite transactions provide durable single-event consumption and an outbox, not
exactly-once delivery to external fulfillment services.
"""
import json
import re
import sqlite3
import time
import uuid
from datetime import datetime


class PaymentConflict(ValueError):
    pass


class PaymentLedger:
    def __init__(self, path):
        self.db = sqlite3.connect(path, timeout=10, isolation_level=None)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA foreign_keys=ON")
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA synchronous=FULL")
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS orders (
                order_id TEXT PRIMARY KEY, chain_id TEXT NOT NULL,
                token TEXT NOT NULL, payer TEXT NOT NULL, recipient TEXT NOT NULL,
                amount TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'unpaid'
                CHECK(state IN ('unpaid', 'paid'))
            );
            CREATE TABLE IF NOT EXISTS credits (
                event_key TEXT PRIMARY KEY, order_id TEXT NOT NULL UNIQUE REFERENCES orders(order_id),
                evidence TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS fulfillment_outbox (
                event_key TEXT PRIMARY KEY REFERENCES credits(event_key),
                order_id TEXT NOT NULL UNIQUE REFERENCES orders(order_id),
                lease_token TEXT, lease_until REAL, delivered INTEGER NOT NULL DEFAULT 0
                CHECK(delivered IN (0,1))
            );
        """)

    def close(self):
        self.db.close()

    @staticmethod
    def _address(value):
        if not isinstance(value, str) or not re.fullmatch(r"0x[0-9a-fA-F]{40}", value) or int(value, 16) == 0:
            raise ValueError("Invalid payment address")
        return value.lower()

    @staticmethod
    def _positive(value):
        if not isinstance(value, str) or not re.fullmatch(r"[1-9][0-9]{0,77}", value) or int(value) >= 2**256:
            raise ValueError("Expected canonical positive integer string")
        return value

    def create_order(self, order_id, *, chain_id, token, payer, recipient, amount):
        """Call from authenticated checkout; expectations cannot be overwritten."""
        if not isinstance(order_id, str) or not order_id.strip():
            raise ValueError("Order ID required")
        values = (order_id, self._positive(chain_id), self._address(token),
                  self._address(payer), self._address(recipient), self._positive(amount))
        if values[3] == values[4]:
            raise ValueError("Self-payment is not accepted")
        self.db.execute("INSERT INTO orders(order_id,chain_id,token,payer,recipient,amount) VALUES(?,?,?,?,?,?)", values)

    def credit(self, order_id, verified):
        """New credits require fresh trusted evidence; matching retries do not write."""
        if not isinstance(order_id, str) or not order_id.strip():
            raise ValueError("Order ID required")
        # Validate a JSON snapshot so caller mutation cannot alter stored evidence.
        try:
            evidence = json.dumps(verified, sort_keys=True, allow_nan=False)
            verified = json.loads(evidence)
        except (TypeError, ValueError, OverflowError, RecursionError) as error:
            raise ValueError("Verification must be a JSON object") from error
        required = {"status", "observation", "eventKey", "token", "payer", "recipient", "amount"}
        if not isinstance(verified, dict):
            raise ValueError("Verification must be a JSON object")
        if verified.get("status") != "verified":
            raise ValueError("Successful finalized corroborated verification required")
        if not required.issubset(verified):
            raise ValueError("Verification missing required fields")
        observation = verified["observation"]
        observation_fields = {"finality", "execution", "sources", "observedAt", "chainId",
                              "transactionHash", "blockHash", "blockNumber"}
        if not isinstance(observation, dict) or not observation_fields.issubset(observation):
            raise ValueError("Observation missing required fields")
        if (observation["finality"] != "finalized"
                or observation["execution"] != "succeeded"
                or type(observation["sources"]) is not int or observation["sources"] < 2):
            raise ValueError("Successful finalized corroborated verification required")
        timestamp = observation["observedAt"]
        if not isinstance(timestamp, str):
            raise ValueError("Observation timestamp must be a string")
        observed = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
        if observed.tzinfo is None:
            raise ValueError("Observation must contain timezone")
        age = time.time() - observed.timestamp()
        block_hash = observation["blockHash"]
        block_number = observation["blockNumber"]
        if not isinstance(block_hash, str) or not re.fullmatch(r"0x[0-9a-f]{64}", block_hash):
            raise ValueError("Invalid inclusion block hash")
        if (not isinstance(block_number, str)
                or not re.fullmatch(r"(?:0|[1-9][0-9]{0,77})", block_number)
                or int(block_number) >= 2**256):
            raise ValueError("Invalid inclusion block number")
        chain = self._positive(observation["chainId"])
        tx = observation["transactionHash"]
        key = verified["eventKey"]
        if not isinstance(tx, str) or not re.fullmatch(r"0x[0-9a-f]{64}", tx):
            raise ValueError("Invalid transaction hash")
        if (not isinstance(key, str)
                or not re.fullmatch(re.escape(f"{chain}:{tx}:") + r"(?:0|[1-9][0-9]{0,77})", key)
                or int(key.rsplit(":", 1)[1]) >= 2**256):
            raise ValueError("Event key does not match observation")
        terms = (chain, self._address(verified["token"]), self._address(verified["payer"]),
                 self._address(verified["recipient"]), self._positive(verified["amount"]))
        self.db.execute("BEGIN IMMEDIATE")
        try:
            order = self.db.execute("SELECT * FROM orders WHERE order_id=?", (order_id,)).fetchone()
            if order is None or tuple(order[field] for field in ("chain_id", "token", "payer", "recipient", "amount")) != terms:
                raise PaymentConflict("Payment does not match the stored order")
            credited = self.db.execute("SELECT order_id FROM credits WHERE event_key=?", (key,)).fetchone()
            if credited:
                if credited["order_id"] != order_id:
                    raise PaymentConflict("Payment already consumed by another order")
                self.db.execute("COMMIT")
                return "already_credited"
            if order["state"] != "unpaid":
                raise PaymentConflict("Order already paid by another event")
            # A retry of an existing credit above never rewrites or renews evidence.
            # New credits must be fresh both at entry and after lock acquisition.
            if not -5 <= age <= 60:
                raise ValueError("Observation stale or from the future; reverify")
            if not -5 <= time.time() - observed.timestamp() <= 60:
                raise ValueError("Observation expired while waiting for ledger lock; reverify")
            self.db.execute("INSERT INTO credits VALUES(?,?,?)", (key, order_id, evidence))
            self.db.execute("UPDATE orders SET state='paid' WHERE order_id=?", (order_id,))
            self.db.execute("INSERT INTO fulfillment_outbox(event_key,order_id) VALUES(?,?)", (key, order_id))
            self.db.execute("COMMIT")
            return "credited"
        except BaseException:
            self.db.execute("ROLLBACK")
            raise

    def claim_fulfillment(self, lease_seconds=30):
        """Lease one item. Delivery must use event_key as downstream idempotency key."""
        if type(lease_seconds) is not int or not 1 <= lease_seconds <= 300:
            raise ValueError("Lease must be between 1 and 300 seconds")
        self.db.execute("BEGIN IMMEDIATE")
        try:
            now = time.time()
            row = self.db.execute("""SELECT event_key,order_id FROM fulfillment_outbox
                WHERE delivered=0 AND (lease_until IS NULL OR lease_until<=?) ORDER BY rowid LIMIT 1""", (now,)).fetchone()
            result = None
            if row:
                token = str(uuid.uuid4())
                self.db.execute("UPDATE fulfillment_outbox SET lease_token=?,lease_until=? WHERE event_key=?",
                                (token, now + lease_seconds, row["event_key"]))
                result = {**dict(row), "lease_token": token}
            self.db.execute("COMMIT")
            return result
        except BaseException:
            self.db.execute("ROLLBACK")
            raise

    def acknowledge_fulfillment(self, event_key, lease_token):
        changed = self.db.execute("""UPDATE fulfillment_outbox SET delivered=1,lease_token=NULL,lease_until=NULL
            WHERE event_key=? AND lease_token=? AND delivered=0 AND lease_until>?""",
            (event_key, lease_token, time.time())).rowcount
        if changed != 1:
            raise PaymentConflict("Lease expired, superseded or already acknowledged")
