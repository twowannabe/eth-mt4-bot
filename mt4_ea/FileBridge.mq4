//+------------------------------------------------------------------+
//| FileBridge.mq4 — File-based bridge for Python bot                 |
//| Place in: MT4/MQL4/Experts/                                       |
//| Attach to ETHUSD chart                                            |
//| No external DLLs needed                                           |
//+------------------------------------------------------------------+
#property strict

input int MagicNumber = 777;
input int CheckIntervalMs = 1000;  // How often to check for commands

string CMD_FILE = "bridge_cmd.txt";
string RESP_FILE = "bridge_resp.txt";
string PRICES_FILE = "bridge_prices.txt";

int OnInit()
{
    EventSetMillisecondTimer(CheckIntervalMs);
    Print("[Bridge] File bridge started, magic=", MagicNumber);
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    EventKillTimer();
    Print("[Bridge] File bridge stopped");
}

void OnTimer()
{
    // Write current prices
    WritePrices();

    // Check for commands
    ProcessCommand();
}

void OnTick()
{
    WritePrices();
}

void WritePrices()
{
    string symbol = Symbol();
    double bid = MarketInfo(symbol, MODE_BID);
    double ask = MarketInfo(symbol, MODE_ASK);

    int h = FileOpen(PRICES_FILE, FILE_WRITE | FILE_TXT | FILE_COMMON);
    if (h != INVALID_HANDLE)
    {
        FileWriteString(h, StringFormat("%.5f|%.5f\n", bid, ask));
        FileClose(h);
    }
}

void ProcessCommand()
{
    if (!FileIsExist(CMD_FILE, FILE_COMMON))
        return;

    int h = FileOpen(CMD_FILE, FILE_READ | FILE_TXT | FILE_COMMON);
    if (h == INVALID_HANDLE) return;

    string cmd = FileReadString(h);
    FileClose(h);
    FileDelete(CMD_FILE, FILE_COMMON);

    if (StringLen(cmd) == 0) return;

    Print("[Bridge] Command: ", cmd);

    string parts[];
    int count = StringSplit(cmd, '|', parts);
    if (count < 1) return;

    string action = parts[0];
    string response = "";

    // --- BUY ---
    if (action == "BUY" && count >= 2)
    {
        double lots = StringToDouble(parts[1]);
        string symbol = Symbol();
        double price = MarketInfo(symbol, MODE_ASK);

        int ticket = OrderSend(symbol, OP_BUY, lots, price, 30, 0, 0,
                               "py_bot", MagicNumber, 0, clrGreen);
        if (ticket < 0)
            response = StringFormat("ERROR|%d", GetLastError());
        else
            response = StringFormat("OK|%d|%.5f", ticket, price);
    }

    // --- SELL (close buy) ---
    else if (action == "CLOSE" && count >= 3)
    {
        int ticket = (int)StringToInteger(parts[1]);
        double lots = StringToDouble(parts[2]);

        if (!OrderSelect(ticket, SELECT_BY_TICKET))
        {
            response = "ERROR|ticket_not_found";
        }
        else
        {
            double price = MarketInfo(OrderSymbol(), MODE_BID);
            bool ok = OrderClose(ticket, lots, price, 30, clrRed);
            if (!ok)
                response = StringFormat("ERROR|%d", GetLastError());
            else
                response = StringFormat("OK|%d|%.5f", ticket, price);
        }
    }

    // --- GET ORDERS ---
    else if (action == "ORDERS")
    {
        response = "";
        for (int i = 0; i < OrdersTotal(); i++)
        {
            if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
            if (OrderMagicNumber() != MagicNumber) continue;
            if (StringLen(response) > 0) response += ";";
            response += StringFormat("%d|%d|%.2f|%.5f|%.2f",
                OrderTicket(), OrderType(), OrderLots(),
                OrderOpenPrice(), OrderProfit());
        }
        if (StringLen(response) == 0) response = "NONE";
    }
    else
    {
        response = "ERROR|unknown_command";
    }

    // Write response
    int rh = FileOpen(RESP_FILE, FILE_WRITE | FILE_TXT | FILE_COMMON);
    if (rh != INVALID_HANDLE)
    {
        FileWriteString(rh, response + "\n");
        FileClose(rh);
    }

    Print("[Bridge] Response: ", response);
}
//+------------------------------------------------------------------+
