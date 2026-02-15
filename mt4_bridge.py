"""ZeroMQ bridge to communicate with MT4 Expert Advisor."""

import json
import time
import zmq


class MT4Bridge:
    def __init__(self, host="localhost", push_port=32768, pull_port=32769):
        self.context = zmq.Context()

        # PUSH socket — send commands to MT4
        self.push_socket = self.context.socket(zmq.PUSH)
        self.push_socket.connect(f"tcp://{host}:{push_port}")

        # PULL socket — receive responses from MT4
        self.pull_socket = self.context.socket(zmq.PULL)
        self.pull_socket.connect(f"tcp://{host}:{pull_port}")
        self.pull_socket.setsockopt(zmq.RCVTIMEO, 5000)  # 5s timeout

        time.sleep(1)  # Wait for connection
        print(f"[MT4] Connected to {host}:{push_port}/{pull_port}")

    def _send(self, command: str) -> dict | None:
        """Send command and wait for response."""
        self.push_socket.send_string(command)
        try:
            response = self.pull_socket.recv_string()
            return json.loads(response) if response.startswith("{") else {"raw": response}
        except zmq.Again:
            print("[MT4] Response timeout")
            return None

    def get_bid_ask(self, symbol: str) -> tuple[float, float] | None:
        """Get current bid/ask price for symbol."""
        resp = self._send(f"RATES|{symbol}")
        if resp and "bid" in resp and "ask" in resp:
            return float(resp["bid"]), float(resp["ask"])
        return None

    def open_buy(self, symbol: str, lots: float, magic: int) -> dict | None:
        """Open a BUY market order."""
        cmd = f"TRADE|OPEN|0|{symbol}|{lots}|0|0|0|{magic}|bot_buy"
        return self._send(cmd)

    def open_sell(self, symbol: str, lots: float, magic: int) -> dict | None:
        """Open a SELL market order."""
        cmd = f"TRADE|OPEN|1|{symbol}|{lots}|0|0|0|{magic}|bot_sell"
        return self._send(cmd)

    def close_order(self, ticket: int, lots: float) -> dict | None:
        """Close an open order by ticket."""
        cmd = f"TRADE|CLOSE|{ticket}|{lots}"
        return self._send(cmd)

    def get_open_orders(self, magic: int = 0) -> list[dict]:
        """Get all open orders (optionally filter by magic number)."""
        resp = self._send("TRADE|GET_OPEN_ORDERS")
        if not resp or "orders" not in resp:
            return []
        orders = resp["orders"]
        if magic:
            orders = [o for o in orders if o.get("magic") == magic]
        return orders

    def close(self):
        self.push_socket.close()
        self.pull_socket.close()
        self.context.term()
        print("[MT4] Connection closed")
