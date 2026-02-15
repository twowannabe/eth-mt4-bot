//+------------------------------------------------------------------+
//| ZMQ_Bridge.mq4 — ZeroMQ bridge for Python bot                    |
//| Place in: MT4/MQL4/Experts/                                       |
//| Attach to ETHUSD chart                                            |
//+------------------------------------------------------------------+
#property strict

#include <Zmq/Zmq.mqh>

input int PushPort = 32769;   // Port to PUSH responses to Python
input int PullPort = 32768;   // Port to PULL commands from Python

Context context("ZMQ_Bridge");
Socket pushSocket(context, ZMQ_PUSH);
Socket pullSocket(context, ZMQ_PULL);

int OnInit()
{
    pushSocket.bind(StringFormat("tcp://*:%d", PushPort));
    pullSocket.bind(StringFormat("tcp://*:%d", PullPort));
    pullSocket.setReceiveTimeout(1000); // 1s timeout

    Print("[ZMQ] Bridge started on ports ", PullPort, "/", PushPort);
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    pushSocket.unbind(StringFormat("tcp://*:%d", PushPort));
    pullSocket.unbind(StringFormat("tcp://*:%d", PullPort));
    Print("[ZMQ] Bridge stopped");
}

void OnTick()
{
    ZmqMsg request;

    if (pullSocket.recv(request, true) == 1)
    {
        string msg = request.getData();
        if (StringLen(msg) == 0) return;

        Print("[ZMQ] Received: ", msg);
        string response = ProcessCommand(msg);
        Print("[ZMQ] Response: ", response);

        ZmqMsg reply(response);
        pushSocket.send(reply);
    }
}

string ProcessCommand(string cmd)
{
    string parts[];
    int count = StringSplit(cmd, '|', parts);
    if (count < 1) return "{\"error\":\"empty command\"}";

    string action = parts[0];

    // --- RATES ---
    if (action == "RATES" && count >= 2)
    {
        string symbol = parts[1];
        double bid = MarketInfo(symbol, MODE_BID);
        double ask = MarketInfo(symbol, MODE_ASK);
        if (bid == 0 && ask == 0)
            return "{\"error\":\"symbol not found\"}";
        return StringFormat("{\"bid\":%.5f,\"ask\":%.5f}", bid, ask);
    }

    // --- TRADE ---
    if (action == "TRADE" && count >= 2)
    {
        string tradeAction = parts[1];

        // OPEN order
        if (tradeAction == "OPEN" && count >= 10)
        {
            int type      = (int)StringToInteger(parts[2]);  // 0=BUY, 1=SELL
            string symbol = parts[3];
            double lots   = StringToDouble(parts[4]);
            double sl     = StringToDouble(parts[5]);
            double tp     = StringToDouble(parts[6]);
            int slippage  = (int)StringToInteger(parts[7]);
            int magic     = (int)StringToInteger(parts[8]);
            string comment= parts[9];

            double price = (type == 0) ? MarketInfo(symbol, MODE_ASK) : MarketInfo(symbol, MODE_BID);
            if (slippage == 0) slippage = 30;

            int ticket = OrderSend(symbol, type, lots, price, slippage, sl, tp, comment, magic, 0, clrGreen);
            if (ticket < 0)
                return StringFormat("{\"error\":\"OrderSend failed\",\"code\":%d}", GetLastError());
            return StringFormat("{\"ticket\":%d,\"price\":%.5f}", ticket, price);
        }

        // CLOSE order
        if (tradeAction == "CLOSE" && count >= 4)
        {
            int ticket  = (int)StringToInteger(parts[2]);
            double lots = StringToDouble(parts[3]);

            if (!OrderSelect(ticket, SELECT_BY_TICKET))
                return "{\"error\":\"ticket not found\"}";

            double price = (OrderType() == OP_BUY) ? MarketInfo(OrderSymbol(), MODE_BID)
                                                    : MarketInfo(OrderSymbol(), MODE_ASK);

            bool ok = OrderClose(ticket, lots, price, 30, clrRed);
            if (!ok)
                return StringFormat("{\"error\":\"OrderClose failed\",\"code\":%d}", GetLastError());
            return StringFormat("{\"closed\":%d,\"price\":%.5f}", ticket, price);
        }

        // GET_OPEN_ORDERS
        if (tradeAction == "GET_OPEN_ORDERS")
        {
            string result = "{\"orders\":[";
            bool first = true;
            for (int i = 0; i < OrdersTotal(); i++)
            {
                if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
                if (!first) result += ",";
                result += StringFormat(
                    "{\"ticket\":%d,\"symbol\":\"%s\",\"type\":%d,\"lots\":%.2f,\"open_price\":%.5f,\"magic\":%d,\"profit\":%.2f}",
                    OrderTicket(), OrderSymbol(), OrderType(), OrderLots(),
                    OrderOpenPrice(), OrderMagicNumber(), OrderProfit()
                );
                first = false;
            }
            result += "]}";
            return result;
        }
    }

    return "{\"error\":\"unknown command\"}";
}
//+------------------------------------------------------------------+
