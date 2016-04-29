-module(shoot_server).

-behaviour(gen_websocket).

-export([start_link/1]).
%% Callback
-export([init/1, request/2]).

-record(state, {message}).

start_link(Port) ->
  gen_websocket:start_link(shoot_server, Port, []).

init([]) ->
  {ok, #state{message="Hello world"}}.

request(_Message, State) ->
  {noreply, State}.
