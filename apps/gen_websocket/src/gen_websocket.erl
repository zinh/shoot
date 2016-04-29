-module(gen_websocket).
-export([start_link/3, start_link/4]).
-export([behaviour_info/1]).

behaviour_info(callbacks) ->
  [ {init,1}, {request,2} ];

behaviour_info(_Other) ->
  undefined.

start_link(Callback, Port, UserArgs) ->
  start_link(Callback, undefined, Port, UserArgs).

start_link(Callback, IP, Port, UserArgs) ->
  gw_connection_sup:start_link(Callback, IP, Port, UserArgs).
