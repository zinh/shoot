%%%-------------------------------------------------------------------
%% @doc shoot top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(shoot_sup).

-behaviour(supervisor).

%% API
-export([start_link/1]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

start_link(Port) ->
  supervisor:start_link({local, ?SERVER}, ?MODULE, [Port]).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([Port]) ->
  Child = {shoot_server, {shoot_server, start_link, [Port]}, temporary, brutal_kill, worker, [shoot_server]},
  Strategy = {one_for_one, 0, 1},
  {ok, { Strategy, [Child]} }.

%%====================================================================
%% Internal functions
%%====================================================================
