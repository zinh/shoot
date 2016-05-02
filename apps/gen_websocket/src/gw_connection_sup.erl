%%%-------------------------------------------------------------------
%% @doc gen_websocket top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(gw_connection_sup).

-behaviour(supervisor).

%% API
-export([start_link/4]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

start_link(Callback, IP, Port, UserArgs) ->
  supervisor:start_link({local, ?SERVER}, ?MODULE, [Callback, IP, Port, UserArgs]).

start_child(Pid) ->
  supervisor:start_child(Pid, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([Callback, IP, Port, UserArgs]) ->
  DefaultOps = [binary,
                {ip, IP},
                {active, false}],
  SockOps = case IP of
              undefined -> DefaultOps;
              _ -> [{ip, IP} | DefaultOps]
            end,
  Socket = gen_tcp:listen(Port, SockOps),
  RestartStrategy = {simple_one_for_one, 0, 1},
  Server = {gw_server, {gw_server, start_link, [self(), Socket, Callback, UserArgs]}, temporary, brutal_kill, worker, [gw_server]},
  {ok, { {one_for_all, 0, 1}, [Server]} }.

%%====================================================================
%% Internal functions
%%====================================================================
