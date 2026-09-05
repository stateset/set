"""Test-only process boundary for exercising the reference ledger on disk."""
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "examples"))
from payment_ledger import PaymentLedger


def main():
    request = json.load(sys.stdin)
    ledger = PaymentLedger(sys.argv[1])
    try:
        action = request["action"]
        if action == "create":
            ledger.create_order(request["order_id"], **request["terms"])
            result = "created"
        elif action == "credit":
            result = ledger.credit(request["order_id"], request["verification"])
        elif action == "claim":
            result = ledger.claim_fulfillment()
        elif action == "ack":
            ledger.acknowledge_fulfillment(request["event_key"], request["lease_token"])
            result = "acknowledged"
        elif action == "expire":
            # Simulate worker loss without delaying the test for a lease interval.
            ledger.db.execute("UPDATE fulfillment_outbox SET lease_until=0 WHERE delivered=0")
            result = "expired"
        elif action == "deliver":
            # Simulated external fulfillment service with durable idempotency.
            ledger.db.execute("""CREATE TABLE IF NOT EXISTS test_deliveries (
                event_key TEXT PRIMARY KEY, order_id TEXT NOT NULL)""")
            ledger.db.execute("INSERT OR IGNORE INTO test_deliveries VALUES(?,?)",
                              (request["event_key"], request["order_id"]))
            result = ledger.db.execute("SELECT count(*) FROM test_deliveries").fetchone()[0]
        elif action == "counts":
            result = {table: ledger.db.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
                      for table in ("credits", "fulfillment_outbox")}
        else:
            raise ValueError("Unknown test action")
        print(json.dumps(result))
    finally:
        ledger.close()


if __name__ == "__main__":
    main()
