-module(gw_server).
-behaviour(gen_server).

%% API
-export([start_link/4]).

%% Callback
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% Define data
%% type: connection type websocket | _other
%% sec_key: Sec-WebSocket-Key
%% phase: handshake: handshaking
%% phase: waiting: handshaked, waiting for message
%% phase: receiving: receiving messsage
-record(state, {parent, socket, callback, user_args, phase=handshake, type, sec_key, len, message}).
-define(MAGIC_STRING, "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").

%% API
start_link(Parent, Socket, Callback, UserArgs) ->
  gen_server:start_link(?MODULE, [Parent, Socket, Callback, UserArgs], []).

%% Callback
init([Parent, Socket, Callback, UserArgs]) ->
  {ok, #state{parent=Parent, socket=Socket, callback=Callback, user_args=UserArgs}, 0}.

handle_info(timeout, #state{parent=Parent, socket=Socket}=State) ->
  io:format("Waiting for new connection~p~n", [Socket]),
  {ok, LSock} = gen_tcp:accept(Socket),
  io:format("Incoming connection~n"),
  supervisor:start_child(Parent, []),
  inet:setopts(LSock, [{active, once}]),
  {noreply, State#state{socket=LSock}};

handle_info({http, _Socket, {http_header, _Length, Name, _ReservedField, Value}}, #state{socket=Socket}=State) ->
  NewState = headers(Name, Value, State),
  inet:setopts(Socket, [{active, once}]),
  {noreply, NewState};

handle_info({http, _Socket, {http_request, _Action, _Path, _Version}}, #state{socket=Socket} = State) ->
  inet:setopts(Socket, [{active, once}]),
  {noreply, State};

handle_info({http, _Socket, http_eoh}, #state{phase=handshake, type=Type, socket=Socket} = State) ->
  case Type of
    websocket -> 
      NewState = handshake_reply(State),
      inet:setopts(Socket, [{packet, raw}, {active, once}]),
      {noreply, NewState};
    _Other ->
      {stop, malformed, State}
  end;

handle_info({tcp, _Socket, RawData}, #state{phase=waiting} = State) ->
  NewState = parse_frame(RawData, State),
  io:format("Received raw: ~p~n", [RawData]),
  {noreply, NewState};

handle_info({tcp_closed, _Socket}, State) ->
  {stop, closed, State}.

terminate(_Reason, _State) ->
  ok.

handle_call(_Request, _From, State) ->
  {noreply, State}.

handle_cast(_Request, State) ->
  {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% Private
headers('Upgrade', <<"websocket">>, State) ->
  io:format("'Upgrade': websocket~n"),
  State#state{type = websocket};

headers(<<"Sec-Websocket-Key">>, Key, State) ->
  io:format("'Sec-Websocket-Key': ~p~n", [Key]),
  State#state{sec_key = binary_to_list(Key)};

headers(Key, Value, State) ->
  io:format("~p: ~p~n", [Key, Value]),
  State.

handshake_reply(#state{socket = Socket, sec_key = SecKey} = State) ->
  AcceptKey = websocket_key(SecKey),
  Reply = [<<"HTTP/1.1 101 Switching Protocols\r\n",
    "Upgrade: websocket\r\n",
    "Connection: Upgrade\r\n",
    "Sec-WebSocket-Accept: ">>,
    AcceptKey,
    <<"\r\n\r\n">>],
  gen_tcp:send(Socket, Reply),
  State#state{phase = waiting}.

websocket_key(Key) ->
  HashKey = crypto:hash(sha, Key ++ ?MAGIC_STRING),
  base64:encode(HashKey).

parse_frame(Frame, State) ->
  case Frame of
    <<Fin:1, _Reserved:3, Opcode:4, Mask:1, PayloadLen:7, MaskKey:4/binary, Payload/binary>> when PayloadLen < 126 ->
      ReceivedSize = byte_size(Payload),
      io:format("Len: ~p, Received: ~p~n", [PayloadLen, ReceivedSize]),
      if PayloadLen =:= ReceivedSize ->
          State#state{phase=waiting, message=Payload}
        true ->
          State#state{phase=receiving, message=Payload}
      end;
    <<Fin:1, _Reserved:3, Opcode:4, Mask:1, PayloadLen:7, Len:32/integer, Mask:4/binary, Payload/binary>> when PayloadLen =:= 126 ->
      ReceivedSize = byte_size(Payload);
    <<Fin:1, _Reserved:3, Opcode:4, Mask:1, PayloadLen:7, Len:64/integer, Mask:4/binary, Payload/binary>> when PayloadLen =:= 127 ->
      ReceivedSize = byte_size(Payload);
    _ ->
      io:format("Error case~n")
  end,
  State.
