-module(gen_websocket).
-export([start_link/3, start_link/4, reply/2]).
-export([behaviour_info/1]).

behaviour_info(callbacks) ->
  [ {init,1}, {handle_message,2} ];

behaviour_info(_Other) ->
  undefined.

start_link(Callback, Port, UserArgs) ->
  start_link(Callback, undefined, Port, UserArgs).

start_link(Callback, IP, Port, UserArgs) ->
  gw_connection_sup:start_link(Callback, IP, Port, UserArgs).

reply(Pid, Message) ->
  gen_server:cast(Pid, {reply, Message}).
