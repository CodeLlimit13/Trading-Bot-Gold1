//+------------------------------------------------------------------+
//|                                                XAUUSD_Multi_TF_EA.mq5 |
//|                                  Copyright 2025, Your Name       |
//|                                             https://www.mql5.com  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Name"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

// Input parameters
input double LotSize = 0.01;           // Lot size for each trade
input int StopLoss = 200;              // Stop Loss in pips
input int TakeProfit = 3000;           // Take Profit in pips
input int BreakEvenPips = 500;         // Move SL to BE after this profit
input int TrailingStep = 100;          // Trailing step in pips
input int TrailingStart = 300;         // Start trailing after this profit
input int LimitOrderDistance = 300;    // Distance for limit orders in pips

// --- New minimal input: how many M5 bars to accept MACD after RSI trigger
input int MaxRsiWaitBars = 6;          // default: 6 M5 bars (~30 minutes)

// Global variables
CTrade trade;
int ema_handle_30m;
int rsi_handle_5m;
int macd_handle_5m;
double ema_buffer[];
double rsi_buffer[];
double macd_main_buffer[];
double macd_signal_buffer[];
datetime last_bar_time = 0;

// --- RSI-first state (minimal globals)
int bars_since_rsi_long = -1;   // -1 = not primed, 0 = just primed
int bars_since_rsi_short = -1;  // -1 = not primed, 0 = just primed

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Remove symbol restriction - now works with any pair
    Print("Multi-Timeframe EA initializing for symbol: ", _Symbol);
    
    ema_handle_30m = iMA(_Symbol, PERIOD_M30, 200, 0, MODE_EMA, PRICE_CLOSE);
    if(ema_handle_30m == INVALID_HANDLE)
    {
        Print("Failed to create 30min EMA handle");
        return(INIT_FAILED);
    }
    
    rsi_handle_5m = iRSI(_Symbol, PERIOD_M5, 14, PRICE_CLOSE);
    if(rsi_handle_5m == INVALID_HANDLE)
    {
        Print("Failed to create 5min RSI handle");
        return(INIT_FAILED);
    }
    
    macd_handle_5m = iMACD(_Symbol, PERIOD_M5, 15, 26, 9, PRICE_CLOSE);
    if(macd_handle_5m == INVALID_HANDLE)
    {
        Print("Failed to create 5min MACD handle");
        return(INIT_FAILED);
    }
    
    ArraySetAsSeries(ema_buffer, true);
    ArraySetAsSeries(rsi_buffer, true);
    ArraySetAsSeries(macd_main_buffer, true);
    ArraySetAsSeries(macd_signal_buffer, true);
    
    Print("Multi-Timeframe EA initialized successfully for ", _Symbol);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(ema_handle_30m != INVALID_HANDLE) IndicatorRelease(ema_handle_30m);
    if(rsi_handle_5m != INVALID_HANDLE) IndicatorRelease(rsi_handle_5m);
    if(macd_handle_5m != INVALID_HANDLE) IndicatorRelease(macd_handle_5m);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    datetime current_time = iTime(_Symbol, PERIOD_M5, 0);
    if(current_time == last_bar_time) return;
    last_bar_time = current_time;
    
    if(!UpdateIndicators()) return;
    
    // --- Minimal new logic: maintain RSI-first primed state (per your requested flow)
    // increment existing primed counters
    if(bars_since_rsi_long >= 0) bars_since_rsi_long++;
    if(bars_since_rsi_short >= 0) bars_since_rsi_short++;
    // timeouts
    if(bars_since_rsi_long > MaxRsiWaitBars) bars_since_rsi_long = -1;
    if(bars_since_rsi_short > MaxRsiWaitBars) bars_since_rsi_short = -1;
    
    // check for RSI priming events (only prime if 30m trend agrees)
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ema30 = ema_buffer[0];
    double rsi5 = rsi_buffer[0];
    
    // prime long: 30m trend up (price > EMA) and RSI <=30 on M5
    if(current_price > ema30 && rsi5 <= 30.0)
    {
        bars_since_rsi_long = 0;
        Print("Primed LONG (M5 RSI <=30 while M30 trend up).");
    }
    // prime short: 30m trend down (price < EMA) and RSI >=70 on M5
    if(current_price < ema30 && rsi5 >= 70.0)
    {
        bars_since_rsi_short = 0;
        Print("Primed SHORT (M5 RSI >=70 while M30 trend down).");
    }
    
    CheckLongConditions();
    CheckShortConditions();
    ManageOpenTrades();
}

//+------------------------------------------------------------------+
//| Update all indicator values                                      |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
    if(CopyBuffer(ema_handle_30m, 0, 0, 2, ema_buffer) < 2)
    {
        Print("Failed to copy EMA buffer");
        return false;
    }
    
    if(CopyBuffer(rsi_handle_5m, 0, 0, 2, rsi_buffer) < 2)
    {
        Print("Failed to copy RSI buffer");
        return false;
    }
    
    if(CopyBuffer(macd_handle_5m, 0, 0, 2, macd_main_buffer) < 2)
    {
        Print("Failed to copy MACD main buffer");
        return false;
    }
    
    if(CopyBuffer(macd_handle_5m, 1, 0, 2, macd_signal_buffer) < 2)
    {
        Print("Failed to copy MACD signal buffer");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| helper: bullish MACD crossover (5m)                              |
//+------------------------------------------------------------------+
bool IsBullishMACDCrossover()
{
    // prev main <= prev signal  AND  curr main > curr signal
    return (macd_main_buffer[1] <= macd_signal_buffer[1]) && (macd_main_buffer[0] > macd_signal_buffer[0]);
}

//+------------------------------------------------------------------+
//| helper: bearish MACD crossover (5m)                              |
//+------------------------------------------------------------------+
bool IsBearishMACDCrossover()
{
    // prev main >= prev signal  AND  curr main < curr signal
    return (macd_main_buffer[1] >= macd_signal_buffer[1]) && (macd_main_buffer[0] < macd_signal_buffer[0]);
}

//+------------------------------------------------------------------+
//| Check long trading conditions                                    |
//+------------------------------------------------------------------+
void CheckLongConditions()
{
    if(HasOpenTrades(POSITION_TYPE_BUY)) return;
    
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // require 30m trend above EMA
    if(current_price <= ema_buffer[0]) 
    {
        // if trend lost, discard primed state
        bars_since_rsi_long = -1;
        return;
    }
    
    // require that RSI event already happened (RSI-first)
    if(bars_since_rsi_long == -1) return; // not primed
    
    // now wait for bullish MACD crossover
    if(!IsBullishMACDCrossover()) return;
    
    // If we got here -> MACD crossover occurred within the RSI window, place long trades
    Print("All long conditions met (RSI primed + MACD bullish crossover). Placing long trades...");
    PlaceLongTrades();
    
    // reset primed state
    bars_since_rsi_long = -1;
}

//+------------------------------------------------------------------+
//| Check short trading conditions                                   |
//+------------------------------------------------------------------+
void CheckShortConditions()
{
    if(HasOpenTrades(POSITION_TYPE_SELL)) return;
    
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // require 30m trend below EMA
    if(current_price >= ema_buffer[0]) 
    {
        // if trend lost, discard primed state
        bars_since_rsi_short = -1;
        return;
    }
    
    // require that RSI event already happened (RSI-first)
    if(bars_since_rsi_short == -1) return; // not primed
    
    // now wait for bearish MACD crossover
    if(!IsBearishMACDCrossover()) return;
    
    // If we got here -> MACD crossover occurred within the RSI window, place short trades
    Print("All short conditions met (RSI primed + MACD bearish crossover). Placing short trades...");
    PlaceShortTrades();
    
    // reset primed state
    bars_since_rsi_short = -1;
}

//+------------------------------------------------------------------+
//| Place long trades                                                |
//+------------------------------------------------------------------+
void PlaceLongTrades()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    double sl = ask - StopLoss * point * 10;
    double tp = ask + TakeProfit * point * 10;
    
    for(int m = 0; m < 2; m++)
    {
        if(!trade.Buy(LotSize, _Symbol, ask, sl, tp, "Long Trade " + IntegerToString(m+1)))
        {
            Print("Failed to place long trade ", m+1, ". Error: ", GetLastError());
        }
        else
        {
            Print("Long trade ", m+1, " placed successfully at ", ask);
        }
    }
    
    double limit_price = ask - LimitOrderDistance * point * 10;
    double limit_sl = limit_price - StopLoss * point * 10;
    double limit_tp = limit_price + TakeProfit * point * 10;
    
    for(int n = 0; n < 2; n++)
    {
        if(!trade.BuyLimit(LotSize, limit_price, _Symbol, limit_sl, limit_tp, 
                          ORDER_TIME_GTC, 0, "Buy Limit " + IntegerToString(n+1)))
        {
            Print("Failed to place buy limit ", n+1, ". Error: ", GetLastError());
        }
        else
        {
            Print("Buy limit ", n+1, " placed at ", limit_price);
        }
    }
}

//+------------------------------------------------------------------+
//| Place short trades                                               |
//+------------------------------------------------------------------+
void PlaceShortTrades()
{
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    double sl = bid + StopLoss * point * 10;
    double tp = bid - TakeProfit * point * 10;
    
    for(int p = 0; p < 2; p++)
    {
        if(!trade.Sell(LotSize, _Symbol, bid, sl, tp, "Short Trade " + IntegerToString(p+1)))
        {
            Print("Failed to place short trade ", p+1, ". Error: ", GetLastError());
        }
        else
        {
            Print("Short trade ", p+1, " placed successfully at ", bid);
        }
    }
    
    double limit_price = bid + LimitOrderDistance * point * 10;
    double limit_sl = limit_price + StopLoss * point * 10;
    double limit_tp = limit_price - TakeProfit * point * 10;
    
    for(int q = 0; q < 2; q++)
    {
        if(!trade.SellLimit(LotSize, limit_price, _Symbol, limit_sl, limit_tp,
                           ORDER_TIME_GTC, 0, "Sell Limit " + IntegerToString(q+1)))
        {
            Print("Failed to place sell limit ", q+1, ". Error: ", GetLastError());
        }
        else
        {
            Print("Sell limit ", q+1, " placed at ", limit_price);
        }
    }
}

//+------------------------------------------------------------------+
//| Manage open trades                                               |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double current_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double current_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    for(int r = PositionsTotal() - 1; r >= 0; r--)
    {
        ulong ticket = PositionGetTicket(r);
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        
        double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
        double current_sl = PositionGetDouble(POSITION_SL);
        double current_tp = PositionGetDouble(POSITION_TP);
        ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        
        double profit_pips = 0;
        double new_sl = current_sl;
        bool modify_position = false;
        
        if(pos_type == POSITION_TYPE_BUY)
        {
            profit_pips = (current_bid - open_price) / (point * 10);
            
            if(profit_pips >= BreakEvenPips && current_sl < open_price)
            {
                new_sl = open_price;
                modify_position = true;
                Print("Moving long position ", ticket, " to break-even. Profit: ", profit_pips, " pips");
            }
            else if(profit_pips >= TrailingStart)
            {
                int trailing_levels = (int)((profit_pips - TrailingStart) / TrailingStep);
                double target_sl = open_price + (trailing_levels * TrailingStep * point * 10);
                
                if(target_sl > current_sl)
                {
                    new_sl = target_sl;
                    modify_position = true;
                    Print("Trailing long position ", ticket, ". New SL: ", new_sl, " Profit: ", profit_pips, " pips");
                }
            }
        }
        else if(pos_type == POSITION_TYPE_SELL)
        {
            profit_pips = (open_price - current_ask) / (point * 10);
            
            if(profit_pips >= BreakEvenPips && current_sl > open_price)
            {
                new_sl = open_price;
                modify_position = true;
                Print("Moving short position ", ticket, " to break-even. Profit: ", profit_pips, " pips");
            }
            else if(profit_pips >= TrailingStart)
            {
                int trailing_levels = (int)((profit_pips - TrailingStart) / TrailingStep);
                double target_sl = open_price - (trailing_levels * TrailingStep * point * 10);
                
                if(target_sl < current_sl)
                {
                    new_sl = target_sl;
                    modify_position = true;
                    Print("Trailing short position ", ticket, ". New SL: ", new_sl, " Profit: ", profit_pips, " pips");
                }
            }
        }
        
        if(modify_position)
        {
            if(!trade.PositionModify(ticket, new_sl, current_tp))
            {
                Print("Failed to modify position ", ticket, ". Error: ", GetLastError());
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check if we already have trades in the specified direction       |
//+------------------------------------------------------------------+
bool HasOpenTrades(ENUM_POSITION_TYPE position_type)
{
    return false; // Simplified - remove position checking for now
}

//+------------------------------------------------------------------+
//| Trade transaction function                                       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                       const MqlTradeRequest& request,
                       const MqlTradeResult& result)
{
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        Print("New deal added. Ticket: ", trans.deal, 
              " Type: ", EnumToString((ENUM_DEAL_TYPE)trans.deal_type),
              " Volume: ", trans.volume,
              " Price: ", trans.price);
    }
}
