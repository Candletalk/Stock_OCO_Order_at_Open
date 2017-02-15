// -------------------------------------------------------------------
// Stock_OCO_Order_at_Open.mq5
// -------------------------------------------------------------------


#property copyright "Copyright 2015 - 2017, candletalk.de"
#property link      "http://www.candletalk.de/"
#property version   "1.01"


enum ENUM_DIRECTION
{ TRADE_LONG  =  1
, TRADE_SHORT = -1
};


input double         minCRV      =    2;   // Minimum CRV, if Opening Gap
input double         TakeProfit  =    0;
input double         StopLoss    =    0;
input double         StopBuySell =    0;
input ENUM_DIRECTION Direction   = TRADE_LONG;
input int            Anzahl      =   10;
input int            MagicNumber = 1234;


int OnInit()
{ string message = "";

  if ( (TakeProfit  - StopBuySell) * Direction <= 0 )
     message = "Entry and TP do not match direction of trade.";
  if ( (StopBuySell - StopLoss   ) * Direction <= 0 )
     message = "Entry and SL do not match direction of trade.";
  if ( message != "" )
  { MessageBox(message, "Operation failed", MB_ICONERROR);
     ExpertRemove();
     Comment("Check Parameters!");   // zeigt Hinweis in Ecke des Charts
  } else
    Comment(" ");                    // löscht Hinweis in Ecke des Charts

  return(INIT_SUCCEEDED);
}


void OnTick()
{ MqlTradeRequest request;
  MqlTradeResult  result;
  MqlDateTime     dt;
  bool            HeuteKeineOrderMehr;
  int
    offeneOrders
  , pendingOrders
  , spread
  ;
  ulong
    ticket
  , thisticket
  , tickethistory
  ;

  ZeroMemory(request);

  // Allgemeine request Bezeichnungen zuordnen

  request.symbol       = Symbol();
  request.volume       = Anzahl;
  request.tp           = TakeProfit;
  request.sl           = StopLoss;
  request.deviation    = 100;
  request.magic        = MagicNumber;
  request.type_filling = ORDER_FILLING_FOK;
  request.type_time    = ORDER_TIME_DAY;

  // Spezielle request Bezeichnungen zuordnen

  if ( Direction == TRADE_LONG )
   request.type = ORDER_TYPE_BUY_STOP;
  else
   request.type = ORDER_TYPE_SELL_STOP;

  TimeCurrent(dt);
  spread = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);

  // nur eine Order öffnen!
  // zählt Pending Orders

  offeneOrders  = 0;
  pendingOrders = 0;
  for ( int i = 0; i < OrdersTotal(); i ++ )
  { ticket = OrderGetTicket(i);
    if ( OrderGetString(ORDER_SYMBOL) == Symbol() )
    { thisticket    = OrderGetTicket(i);
      offeneOrders  ++;
      pendingOrders ++;
    }
  }

  // zählt offene Orders

  for( int i = 0; i < PositionsTotal(); i ++ )
    if
    (  Symbol() == PositionGetSymbol(i)
    && PositionGetInteger(POSITION_MAGIC) == MagicNumber
    )
      offeneOrders ++;

  // Order wird nur eröffnet wenn der Ask unterhalb von (Target+StopBuySell) / 2 ist.
  // Das soll ein zu großes Risiko verhindern.
  // Eine Marketorder wird ausgeführt wenn der Preis über dem StopbuySell liegt (Gap)
  // ansonsten wird eine PendingOrder ausgeführt
  // Order zu einer bestimmten Zeit öffnen (zur Markteröffnung in den ersten 10 Minuten

  // Order wird nur erstellt, wenn heute noch keine Order auf diesem Wert offen war

  HeuteKeineOrderMehr = false;
  HistorySelect(0, TimeCurrent());

  for ( int i = 0; i < HistoryDealsTotal(); i ++ )
  { tickethistory = HistoryDealGetTicket(i);

    if
    (  Symbol() == HistoryDealGetString(tickethistory, DEAL_SYMBOL)
    &&    TimeToString(TimeCurrent(dt)                                , TIME_DATE)
       == TimeToString(HistoryDealGetInteger(tickethistory, DEAL_TIME), TIME_DATE)
    )
      HeuteKeineOrderMehr = true;
  }

  if
  (  ! HeuteKeineOrderMehr
  && dt.hour      ==  9
  && dt.min       <= 10
  && offeneOrders ==  0
  )
  { if ( Direction == TRADE_LONG )
    { if
      (  SymbolInfoDouble(Symbol(), SYMBOL_ASK)            >= StopBuySell
      && ((TakeProfit + StopLoss * minCRV) / (1 + minCRV)) >  SymbolInfoDouble(Symbol(), SYMBOL_ASK)
      )
      { request.action  = TRADE_ACTION_DEAL;
        request.price   = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        request.type    = ORDER_TYPE_BUY;
        request.comment = "RSI Long Market " + spread;
        OrderSend(request, result);
      }
    else if ( SymbolInfoDouble(Symbol(), SYMBOL_ASK) < StopBuySell )
      { request.action  = TRADE_ACTION_PENDING;
        request.price   = StopBuySell;
        request.type    = ORDER_TYPE_BUY_STOP;
        request.comment = "RSI Long Stop " + spread;
        OrderSend(request, result);
    } }
    else if ( Direction == TRADE_SHORT )
    { if
      (  SymbolInfoDouble(Symbol(), SYMBOL_BID) <= StopBuySell
      && SymbolInfoDouble(Symbol(), SYMBOL_BID) > ((TakeProfit + StopLoss * minCRV) / (1 + minCRV))
      )
      { request.action  = TRADE_ACTION_DEAL;
        request.price   = SymbolInfoDouble(Symbol(), SYMBOL_BID);
        request.type    = ORDER_TYPE_SELL;
        request.comment = "RSI Short Market " + spread;
        OrderSend(request, result);
      }
      else if ( SymbolInfoDouble(Symbol(), SYMBOL_BID) > StopBuySell )
      { request.action  = TRADE_ACTION_PENDING;
        request.price   = StopBuySell;
        request.type    = ORDER_TYPE_SELL_STOP;
        request.comment = "RSI Short Stop " + spread;
        OrderSend(request, result);
  } } }

  // Pendingorder zu einer bestimmten Zeit wiederum löschen
  // (zu Marktschluss ab den letzen 10 Minuten)

  if
  (  pendingOrders >   0
  && dt.hour       == 17
  && dt.min        >= 20
  )
  { request.action = TRADE_ACTION_REMOVE;
    request.order  = thisticket;
    OrderSend(request, result);
  }

  /******************************************************************************

  // Maximaler Verlust:

  // Wenn maximaler Verlust und Stoploss nahezu gleich liegen und gleichzeitig triggern,
  // wird statt die Position zu schließen, diese gleich wieder neu eröffnet,
  // und zwar in die Gegenrichtung und ohne StopLoss!
  // Ohne zusätzliche Prüfung sollte diese Funktion nicht verwendet werden.

  // Wenn ich mit dieser Position um einen gewissen Geldbetrag im Minus bin,
  // dann sofort Order schließen

  for ( int i = 0; i < PositionsTotal(); i ++ )
  { if
    (  Symbol() == PositionGetSymbol(i)
    && PositionGetInteger(POSITION_MAGIC) == MagicNumber
    && PositionGetDouble(POSITION_PROFIT) <  - MaximalerVerlust
    )
    { if ( PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY )
      { request.sl      = 0;
        request.tp      = 0;
        request.volume  = PositionGetDouble(POSITION_VOLUME);
        request.action  = TRADE_ACTION_DEAL;
        request.price   = SymbolInfoDouble(Symbol(), SYMBOL_BID);
        request.type    = ORDER_TYPE_SELL;
        request.comment = "Maximalverlust erreicht " + spread;
        OrderSend(request, result);
      }
      else if ( PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL )
      { request.sl      = 0;
        request.tp      = 0;
        request.volume  = PositionGetDouble(POSITION_VOLUME);
        request.action  = TRADE_ACTION_DEAL;
        request.price   = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        request.type    = ORDER_TYPE_BUY;
        request.comment = "Maximalverlust erreicht " + spread;
        OrderSend(request, result);
  } } }
  *******************************************************************************/
}
