"""Bot configuration."""

# MT4 ZeroMQ bridge settings
ZMQ_HOST = "localhost"
ZMQ_PUSH_PORT = 32768   # Commands to MT4
ZMQ_PULL_PORT = 32769   # Responses from MT4

# Trading parameters
SYMBOL = "ETHUSD"        # Symbol name in MT4 (check your broker)
LOT_SIZE = 0.01          # Lot size (no leverage — keep small)
BUY_PRICE = 1980.0       # Buy when price drops to this level
SELL_PRICE = 2100.0      # Sell when price rises to this level
MAGIC_NUMBER = 777       # Unique ID for bot's orders

# Polling interval (seconds)
CHECK_INTERVAL = 5
