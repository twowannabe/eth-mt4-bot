"""File-based bridge to communicate with MT4 Expert Advisor."""

import os
import time

# MT4 common files directory under Wine
MT4_COMMON = os.path.expanduser("~/.wine/drive_c/users") + "/" + os.environ.get("USER", "root") + "/Application Data/MetaQuotes/Terminal/Common/Files"

CMD_FILE = os.path.join(MT4_COMMON, "bridge_cmd.txt")
RESP_FILE = os.path.join(MT4_COMMON, "bridge_resp.txt")
PRICES_FILE = os.path.join(MT4_COMMON, "bridge_prices.txt")


class MT4Bridge:
    def __init__(self):
        os.makedirs(MT4_COMMON, exist_ok=True)
        # Clean up stale files
        for f in [CMD_FILE, RESP_FILE]:
            if os.path.exists(f):
                os.remove(f)
        print(f"[MT4] File bridge ready, common dir: {MT4_COMMON}")

    def _send_command(self, cmd: str, timeout: float = 10.0) -> str | None:
        """Write command file, wait for response file."""
        # Remove old response
        if os.path.exists(RESP_FILE):
            os.remove(RESP_FILE)

        # Write command
        with open(CMD_FILE, "w") as f:
            f.write(cmd)

        # Wait for response
        start = time.time()
        while time.time() - start < timeout:
            if os.path.exists(RESP_FILE):
                time.sleep(0.1)  # Let MT4 finish writing
                with open(RESP_FILE, "r") as f:
                    resp = f.read().strip()
                os.remove(RESP_FILE)
                return resp
            time.sleep(0.2)

        print("[MT4] Response timeout")
        return None

    def get_bid_ask(self, symbol: str) -> tuple[float, float] | None:
        """Read current bid/ask from prices file."""
        if not os.path.exists(PRICES_FILE):
            return None
        try:
            with open(PRICES_FILE, "r") as f:
                line = f.read().strip()
            parts = line.split("|")
            if len(parts) == 2:
                return float(parts[0]), float(parts[1])
        except (ValueError, IOError):
            pass
        return None

    def open_buy(self, lots: float) -> dict | None:
        """Open a BUY market order."""
        resp = self._send_command(f"BUY|{lots}")
        if not resp:
            return None
        parts = resp.split("|")
        if parts[0] == "OK":
            return {"ticket": int(parts[1]), "price": float(parts[2])}
        return {"error": resp}

    def close_order(self, ticket: int, lots: float) -> dict | None:
        """Close an open order by ticket."""
        resp = self._send_command(f"CLOSE|{ticket}|{lots}")
        if not resp:
            return None
        parts = resp.split("|")
        if parts[0] == "OK":
            return {"ticket": int(parts[1]), "price": float(parts[2])}
        return {"error": resp}

    def get_open_orders(self) -> list[dict]:
        """Get all open orders with bot's magic number."""
        resp = self._send_command("ORDERS")
        if not resp or resp == "NONE":
            return []
        orders = []
        for entry in resp.split(";"):
            parts = entry.split("|")
            if len(parts) == 5:
                orders.append({
                    "ticket": int(parts[0]),
                    "type": int(parts[1]),  # 0=BUY, 1=SELL
                    "lots": float(parts[2]),
                    "open_price": float(parts[3]),
                    "profit": float(parts[4]),
                })
        return orders

    def close(self):
        print("[MT4] Bridge closed")
