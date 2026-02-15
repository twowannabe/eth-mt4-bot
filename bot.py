"""
ETH MT4 Trading Bot
Strategy: Buy at 1980, Sell at 2100, no leverage.

Requires:
1. MT4 terminal running with DWX_ZeroMQ_Server EA attached to ETHUSD chart
2. pip install pyzmq
"""

import time
import signal
import sys
from datetime import datetime

from config import (
    ZMQ_HOST, ZMQ_PUSH_PORT, ZMQ_PULL_PORT,
    SYMBOL, LOT_SIZE, BUY_PRICE, SELL_PRICE,
    MAGIC_NUMBER, CHECK_INTERVAL,
)
from mt4_bridge import MT4Bridge


class ETHBot:
    def __init__(self):
        self.bridge = MT4Bridge(ZMQ_HOST, ZMQ_PUSH_PORT, ZMQ_PULL_PORT)
        self.has_position = False  # True if we have an open BUY
        self.position_ticket = None
        self.running = True

        # Graceful shutdown
        signal.signal(signal.SIGINT, self._stop)
        signal.signal(signal.SIGTERM, self._stop)

    def _stop(self, *args):
        print("\n[BOT] Shutting down...")
        self.running = False

    def _log(self, msg: str):
        ts = datetime.now().strftime("%H:%M:%S")
        print(f"[{ts}] {msg}")

    def _check_existing_position(self):
        """Check if we already have an open position from a previous session."""
        orders = self.bridge.get_open_orders(magic=MAGIC_NUMBER)
        for order in orders:
            if order.get("symbol") == SYMBOL and order.get("type") == 0:  # 0 = BUY
                self.has_position = True
                self.position_ticket = order.get("ticket")
                self._log(f"Found existing BUY position: ticket={self.position_ticket}")
                return
        self.has_position = False
        self.position_ticket = None

    def run(self):
        self._log(f"ETH Bot started — BUY at {BUY_PRICE}, SELL at {SELL_PRICE}")
        self._log(f"Symbol: {SYMBOL}, Lot: {LOT_SIZE}, Magic: {MAGIC_NUMBER}")

        # Check for existing positions
        self._check_existing_position()

        while self.running:
            try:
                prices = self.bridge.get_bid_ask(SYMBOL)
                if not prices:
                    self._log("Failed to get prices, retrying...")
                    time.sleep(CHECK_INTERVAL)
                    continue

                bid, ask = prices

                if not self.has_position:
                    # No position — wait for BUY signal
                    if ask <= BUY_PRICE:
                        self._log(f"BUY SIGNAL! Ask={ask} <= {BUY_PRICE}")
                        result = self.bridge.open_buy(SYMBOL, LOT_SIZE, MAGIC_NUMBER)
                        if result:
                            self._log(f"BUY order sent: {result}")
                            self.has_position = True
                            # Get ticket from open orders
                            time.sleep(1)
                            self._check_existing_position()
                        else:
                            self._log("BUY order FAILED")
                    else:
                        self._log(f"Waiting to BUY... Ask={ask} (target <= {BUY_PRICE})")

                else:
                    # Have position — wait for SELL signal
                    if bid >= SELL_PRICE:
                        self._log(f"SELL SIGNAL! Bid={bid} >= {SELL_PRICE}")
                        if self.position_ticket:
                            result = self.bridge.close_order(self.position_ticket, LOT_SIZE)
                            if result:
                                self._log(f"Position closed: {result}")
                                profit = (SELL_PRICE - BUY_PRICE) * LOT_SIZE * 100
                                self._log(f"Estimated profit: ~${profit:.2f}")
                                self.has_position = False
                                self.position_ticket = None
                            else:
                                self._log("CLOSE order FAILED")
                        else:
                            self._log("No ticket found, checking orders...")
                            self._check_existing_position()
                    else:
                        self._log(f"Holding position... Bid={bid} (target >= {SELL_PRICE})")

            except Exception as e:
                self._log(f"Error: {e}")

            time.sleep(CHECK_INTERVAL)

        self.bridge.close()
        self._log("Bot stopped.")


if __name__ == "__main__":
    bot = ETHBot()
    bot.run()
