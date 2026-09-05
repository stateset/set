"""Real SQLite integration tests for the server-side reference payment ledger."""
import copy
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone, timedelta
import importlib.util
from pathlib import Path
import sqlite3
import tempfile
import threading
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("payment_ledger", ROOT / "sdk/examples/payment_ledger.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PaymentLedgerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="set-payment-ledger-")
        self.path = Path(self.temp.name) / "ledger.sqlite"
        self.ledger = MODULE.PaymentLedger(self.path)
        self.terms = dict(chain_id="10", token="0x" + "11" * 20,
                          payer="0x" + "22" * 20, recipient="0x" + "33" * 20, amount="1000000")
        self.ledger.create_order("order-1", **self.terms)
        self.ledger.create_order("order-2", **self.terms)
        tx = "0x" + "ab" * 32
        self.evidence = dict(status="verified", eventKey=f"10:{tx}:0",
            token=self.terms["token"], payer=self.terms["payer"], recipient=self.terms["recipient"], amount="1000000",
            observation=dict(chainId="10", transactionHash=tx, finality="finalized", execution="succeeded",
                             blockHash="0x" + "cd" * 32, blockNumber="10",
                             sources=2, observedAt=datetime.now(timezone.utc).isoformat()))

    def tearDown(self):
        self.ledger.close()
        self.temp.cleanup()

    def counts(self):
        return tuple(self.ledger.db.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
                     for table in ("credits", "fulfillment_outbox"))

    def test_atomic_credit_and_retry_survive_reopen(self):
        self.assertEqual(self.ledger.credit("order-1", self.evidence), "credited")
        self.ledger.close()
        self.ledger = MODULE.PaymentLedger(self.path)
        self.assertEqual(self.ledger.credit("order-1", self.evidence), "already_credited")
        self.assertEqual(self.counts(), (1, 1))

    def test_expired_retry_returns_existing_credit_without_rewriting_evidence(self):
        self.ledger.credit("order-1", self.evidence)
        original = self.ledger.db.execute("SELECT evidence FROM credits").fetchone()[0]
        observed = datetime.fromisoformat(self.evidence["observation"]["observedAt"]).timestamp()
        self.ledger.close()
        self.ledger = MODULE.PaymentLedger(self.path)
        with patch.object(MODULE.time, "time", return_value=observed + 3600):
            self.assertEqual(self.ledger.credit("order-1", self.evidence), "already_credited")
            with self.assertRaises(MODULE.PaymentConflict):
                self.ledger.credit("order-2", self.evidence)
        self.assertEqual(self.ledger.db.execute("SELECT evidence FROM credits").fetchone()[0], original)
        self.assertEqual(self.counts(), (1, 1))

    def test_expired_retry_does_not_requeue_completed_fulfillment(self):
        self.ledger.credit("order-1", self.evidence)
        lease = self.ledger.claim_fulfillment()
        self.ledger.acknowledge_fulfillment(lease["event_key"], lease["lease_token"])
        with patch.object(MODULE.time, "time", return_value=datetime.now(timezone.utc).timestamp() + 3600):
            self.assertEqual(self.ledger.credit("order-1", self.evidence), "already_credited")
            self.assertIsNone(self.ledger.claim_fulfillment())
        self.assertEqual(self.counts(), (1, 1))

    def test_malformed_evidence_is_rejected_without_writes(self):
        values = [None, [], "verified", 42, {}, {"status": "verified"}]
        for field in self.evidence:
            value = copy.deepcopy(self.evidence)
            del value[field]
            values.append(value)
        for field in self.evidence["observation"]:
            value = copy.deepcopy(self.evidence)
            del value["observation"][field]
            values.append(value)
        for value in values:
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.ledger.credit("order-1", value)
        self.assertEqual(self.counts(), (0, 0))

    def test_invalid_inclusion_and_timestamp_types_are_rejected(self):
        for field, values in {
            "blockHash": [None, 1, "0x123", "0x" + "GG" * 32],
            "blockNumber": [None, 10, True, "-1", "01", "0xa", str(2**256)],
            "observedAt": [None, 1, True, [], "not-a-date"],
        }.items():
            for value in values:
                evidence = copy.deepcopy(self.evidence)
                evidence["observation"][field] = value
                with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                    self.ledger.credit("order-1", evidence)
        self.assertEqual(self.counts(), (0, 0))

    def test_non_json_evidence_is_rejected(self):
        for value in [float("nan"), float("inf"), object(), {1, 2}]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.ledger.credit("order-1", {**self.evidence, "extra": value})
        self.assertEqual(self.counts(), (0, 0))

    def test_bounded_canonical_event_ordinals(self):
        prefix = self.evidence["eventKey"].rsplit(":", 1)[0]
        for ordinal in ["-1", "01", "1.0", "9" * 100, str(2**256)]:
            with self.subTest(ordinal=ordinal), self.assertRaises(ValueError):
                self.ledger.credit("order-1", {**self.evidence, "eventKey": f"{prefix}:{ordinal}"})
        self.assertEqual(self.counts(), (0, 0))

    def test_same_event_cannot_pay_another_order(self):
        self.ledger.credit("order-1", self.evidence)
        with self.assertRaises(MODULE.PaymentConflict):
            self.ledger.credit("order-2", self.evidence)
        self.assertEqual(self.counts(), (1, 1))

    def test_paid_order_cannot_consume_another_event(self):
        self.ledger.credit("order-1", self.evidence)
        evidence = {**self.evidence, "eventKey": self.evidence["eventKey"][:-1] + "1"}
        with self.assertRaises(MODULE.PaymentConflict):
            self.ledger.credit("order-1", evidence)

    def test_order_terms_must_match(self):
        for key, value in (("token", self.terms["payer"]), ("payer", self.terms["token"]),
                           ("recipient", self.terms["token"]), ("amount", "1000001")):
            with self.subTest(key=key), self.assertRaises(MODULE.PaymentConflict):
                self.ledger.credit("order-1", {**self.evidence, key: value})
        self.assertEqual(self.counts(), (0, 0))

    def test_invalid_or_stale_observations_are_rejected(self):
        for key, value in (("finality", "safe"), ("execution", "reverted"), ("sources", 1),
                           ("sources", True), ("observedAt", datetime.now().isoformat()),
                           ("observedAt", (datetime.now(timezone.utc) - timedelta(minutes=2)).isoformat()),
                           ("observedAt", (datetime.now(timezone.utc) + timedelta(minutes=2)).isoformat())):
            evidence = copy.deepcopy(self.evidence)
            evidence["observation"][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                self.ledger.credit("order-1", evidence)
        self.assertEqual(self.counts(), (0, 0))

    def test_event_key_binding(self):
        with self.assertRaises(ValueError):
            self.ledger.credit("order-1", {**self.evidence, "eventKey": "another-order:0"})

    def test_outbox_failure_rolls_back_credit_and_order(self):
        self.ledger.db.execute("""CREATE TRIGGER fail_outbox BEFORE INSERT ON fulfillment_outbox
            BEGIN SELECT RAISE(ABORT, 'simulated disk/application failure'); END""")
        with self.assertRaises(sqlite3.IntegrityError):
            self.ledger.credit("order-1", self.evidence)
        self.assertEqual(self.counts(), (0, 0))
        self.assertEqual(self.ledger.db.execute("SELECT state FROM orders WHERE order_id='order-1'").fetchone()[0], "unpaid")
        self.ledger.db.execute("DROP TRIGGER fail_outbox")
        self.assertEqual(self.ledger.credit("order-1", self.evidence), "credited")

    def test_concurrent_credit_has_one_winner(self):
        barrier = threading.Barrier(2)
        def attempt(order):
            ledger = MODULE.PaymentLedger(self.path)
            try:
                barrier.wait(timeout=5)
                try:
                    return ledger.credit(order, self.evidence)
                except MODULE.PaymentConflict:
                    return "conflict"
            finally:
                ledger.close()
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(attempt, ["order-1", "order-2"]))
        self.assertCountEqual(results, ["credited", "conflict"])
        self.assertEqual(self.counts(), (1, 1))

    def test_evidence_expiring_during_lock_wait_is_not_credited(self):
        observed = datetime.fromisoformat(self.evidence["observation"]["observedAt"]).timestamp()
        with patch.object(MODULE.time, "time", side_effect=[observed, observed + 61]):
            with self.assertRaisesRegex(ValueError, "ledger lock"):
                self.ledger.credit("order-1", self.evidence)
        self.assertEqual(self.counts(), (0, 0))

    def test_concurrent_workers_cannot_hold_the_same_lease(self):
        self.ledger.credit("order-1", self.evidence)
        barrier = threading.Barrier(2)
        def claim(_):
            ledger = MODULE.PaymentLedger(self.path)
            try:
                barrier.wait(timeout=5)
                return ledger.claim_fulfillment()
            finally:
                ledger.close()
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(claim, range(2)))
        self.assertEqual(sum(item is not None for item in results), 1)

    def test_worker_restart_and_stale_lease_cannot_acknowledge(self):
        self.ledger.credit("order-1", self.evidence)
        first = self.ledger.claim_fulfillment()
        self.assertIsNone(self.ledger.claim_fulfillment())
        self.ledger.db.execute("UPDATE fulfillment_outbox SET lease_until=0")
        self.ledger.close()
        self.ledger = MODULE.PaymentLedger(self.path)
        second = self.ledger.claim_fulfillment()
        self.assertEqual(first["event_key"], second["event_key"])
        self.assertNotEqual(first["lease_token"], second["lease_token"])
        with self.assertRaises(MODULE.PaymentConflict):
            self.ledger.acknowledge_fulfillment(first["event_key"], first["lease_token"])
        self.ledger.acknowledge_fulfillment(second["event_key"], second["lease_token"])
        self.assertIsNone(self.ledger.claim_fulfillment())


if __name__ == "__main__":
    unittest.main()
