-module(shoot_server).

-behaviour(gen_websocket).

-export([start_link/1]).
%% Callback
-export([init/1, handle_message/2]).

start_link(Port) ->
  gen_websocket:start_link(shoot_server, Port, []).

init([]) ->
  ok.

handle_message(Message, State) ->
  {reply, Message, State}.
