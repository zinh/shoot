%%%-------------------------------------------------------------------
%% @doc shoot public API
%% @end
%%%-------------------------------------------------------------------

-module(shoot_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).
-define(DEFAULT_PORT, 8080).

%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
  Port = os:getenv("port", ?DEFAULT_PORT),
  shoot_sup:start_link(Port).

%%--------------------------------------------------------------------
stop(_State) ->
  ok.

%%====================================================================
%% Internal functions
%%====================================================================
