-module(gw_server).
-behaviour(gen_server).

%% API
-export([start_link/4]).

%% Callback
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% Define data
%% type: connection type websocket | _other
%% sec_key: Sec-WebSocket-Key
-record(state, {parent, socket, callback, user_args, type, sec_key, len, message = <<>>}).
-define(MAGIC_STRING, "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").

%% API
start_link(Parent, Socket, Callback, UserArgs) ->
  gen_server:start_link(?MODULE, [Parent, Socket, Callback, UserArgs], []).

%% Callback
init([Parent, Socket, Callback, UserArgs]) ->
  {ok, #state{parent=Parent, socket=Socket, callback=Callback, user_args=UserArgs}, 0}.

handle_info(timeout, #state{parent=Parent, socket=Socket}=State) ->
  {ok, LSock} = gen_tcp:accept(Socket),
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

handle_info({http, _Socket, http_eoh}, #state{type=Type, socket=Socket} = State) ->
  case Type of
    websocket -> 
      NewState = handshake_reply(State),
      inet:setopts(Socket, [{packet, raw}, {active, once}]),
      {noreply, NewState};
    _Other ->
      {stop, malformed, State}
  end;

handle_info({tcp, _Socket, RawData}, #state{socket = Socket}=State) ->
  NewState = parse_frame(RawData, State),
  inet:setopts(Socket, [{packet, raw}, {active, once}]),
  {noreply, NewState};

handle_info({tcp_closed, _Socket}, State) ->
  {stop, closed, State}.

terminate(_Reason, _State) ->
  ok.

handle_call(_Request, _From, State) ->
  {noreply, State}.

handle_cast({reply, Message}, #state{socket = Socket} = State) ->
  reply(Socket, Message),
  {noreply, State};

handle_cast(_Request, State) ->
  {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% Private
headers('Upgrade', <<"websocket">>, State) ->
  State#state{type = websocket};

headers(<<"Sec-Websocket-Key">>, Key, State) ->
  State#state{sec_key = binary_to_list(Key)};

headers(_Key, _Value, State) ->
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
  State.

websocket_key(Key) ->
  HashKey = crypto:hash(sha, Key ++ ?MAGIC_STRING),
  base64:encode(HashKey).

parse_frame(Frame, State) ->
  {FFin, _LLength, MMaskKey, PPayload} = case Frame of
    <<Fin:1, _Reserved:3, _Opcode:4, _Mask:1, PayloadLen:7, MaskKey:4/binary, Payload/binary>> when PayloadLen < 126 ->
      {Fin, PayloadLen, MaskKey, Payload};
    <<Fin:1, _Reserved:3, _Opcode:4, _Mask:1, PayloadLen:7, _Len:32/integer, MaskKey:4/binary, Payload/binary>> when PayloadLen =:= 126 ->
      {Fin, PayloadLen, MaskKey, Payload};
    <<Fin:1, _Reserved:3, _Opcode:4, _Mask:1, PayloadLen:7, _Len:64/integer, MaskKey:4/binary, Payload/binary>> when PayloadLen =:= 127 ->
      {Fin, PayloadLen, MaskKey, Payload};
    _ ->
      io:format("Error case~n")
  end,
  CurrentMessage = State#state.message,
  NewState = if FFin =:= 1 ->
      handle(State#state{
          message = unmask(MMaskKey, erlang:iolist_to_binary([CurrentMessage, PPayload]))
        });
    true ->
      State#state{
        message = [CurrentMessage, unmask(MMaskKey, PPayload)]
      }
  end,
  NewState.

unmask(MaskKey, Message) ->
  unmask_tail(MaskKey, [], Message).

unmask_tail(_MaskKey, UnmaskMessage, <<>>) ->
  erlang:iolist_to_binary(UnmaskMessage);

unmask_tail(MaskKey, UnmaskMessage, <<H:4/binary,T/binary>>) ->
  unmask_tail(MaskKey, [UnmaskMessage, crypto:exor(MaskKey, H)], T);

unmask_tail(MaskKey, UnmaskMessage, <<T/binary>>) ->
  Key = binary:part(MaskKey, 0, byte_size(T)),
  unmask_tail(MaskKey, [UnmaskMessage, crypto:exor(Key, T)], <<>>).

handle(#state{message = Message, callback = Callback, user_args = UserArgs, socket = Socket} = State) ->
  Args = case Callback:handle_message(Message, UserArgs) of
    {reply, Reply, NewUserArgs} ->
      reply(Socket, Reply),
      NewUserArgs;
    {noreply, NewUserArgs} ->
      NewUserArgs
  end,
  State#state{user_args = Args, message = <<>>}.

reply_packet_gen(Message) ->
  Size = byte_size(Message),
  [<<129, Size>>, Message].
  %% [<<2#100000010, Size:7/integer>>, Message].

reply(Socket, Message) ->
  gen_tcp:send(Socket, reply_packet_gen(Message)).
