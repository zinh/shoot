-module(gw_server).
-behaviour(gen_server).

%% API
-export([start_link/4, reply/2, reply/3]).

%% Callback
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% Define data
-record(state, {parent, socket, callback, user_args, phase=handshake}).
-define(MAGIC_STRING, "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").

%% API
start_link(Parent, Socket, Callback, UserArgs) ->
  gen_server:start_link(gw_server, [Parent, Socket, Callback, UserArgs], []).

reply(Pid, Message) ->
  gen_server:cast(Pid, {reply, Message}).

reply(Pid, Message, UserArgs) ->
  gen_server:cast(Pid, {reply, Message, UserArgs}).

%% Callback
init([Parent, Socket, Callback, UserArgs]) ->
  case Callback:init(UserArgs) of
    {ok, UserState} ->
      State = #state{parent=Parent, socket=Socket, callback=Callback, user_args=UserState},
      {ok, State, 0};
    _ ->
      {stop, invalid}
  end.

handle_info(timeout, #state{parent=Parent, socket=Socket} = State) ->
  LSock = gen_tcp:accept(Socket),
  gw_connection_sup:start_child(Parent),
  inet:setopts(LSock, [{active, once}]),
  {noreply, State#state{socket=LSock}};

%% Handshake
handle_info({tcp, LSock, Data}, #state{phase=handshake} = State) ->
  {_Path, Headers} = get_path(Data),
  Key = proplists:get_value("Sec-Websocket-Key", Headers),
  AcceptKey = websocket_key(Key),
  Data = [<<"HTTP/1.1 101 Switching Protocols\r\n",
            "Upgrade: websocket\r\n",
            "Connection: Upgrade\r\n",
            "Sec-WebSocket-Accept: ">>,
          AcceptKey,
          <<"\r\n\r\n">>],
  gen_tcp:send(LSock, Data),
  inet:setopts(LSock, [{active, once}]),
  {noreply, State#state{phase=handshaked}};

handle_info({tcp, LSock, Frame}, #state{phase=handshaked, callback=Callback, user_args=UserArgs} = State) ->
  Message = parse_frame(Frame),
  case Callback:request(Message, UserArgs) of
    {reply, Reply, NewUserArgs} ->
      gen_tcp:send(State#state.socket, Reply),
      inet:setopts(LSock, [{active, once}]),
      {noreply, State#state{user_args=NewUserArgs}};
    {reply, Reply} ->
      gen_tcp:send(State#state.socket, Reply),
      inet:setopts(LSock, [{active, once}]),
      {noreply, State};
    _ ->
      inet:setopts(LSock, [{active, once}]),
      {noreply, State}
  end.

handle_call(_Req, _From, State) ->
  {noreply, State}.

handle_cast({reply, Message}, #state{socket = Socket} = State) ->
  send(Socket, Message),
  {noreply, State};

handle_cast({reply, Message, UserArgs}, #state{socket=Socket}=State) ->
  send(Socket, Message),
  {noreply, State#state{user_args=UserArgs}}.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

terminate(_Reason, _State) ->
  ok.

%% Private
get_path(Packet) ->
  {ok, {http_request, _, {abs_path, Path}, _}, Rest} = erlang:decode_packet(http, Packet, []),
  Headers = parse_header(Rest),
  {Path, Headers}.

parse_header(Packet) ->
  parse_header(Packet, []).

parse_header(Packet, Headers) ->
  case erlang:decode_packet(httph, Packet, []) of 
    {ok, {http_header, _, Key, _, Value}, Rest} ->
      parse_header(Rest, [{Key, Value} | Headers]);
    {ok, http_eoh, _} ->
      Headers;
    {error, _Reason} ->
      Headers
  end.

websocket_key(Key) ->
  HashKey = crypto:hash(sha, Key ++ ?MAGIC_STRING),
  base64:encode(HashKey).

parse_frame(Frame) ->
  case Frame of
    <<_Fin:1, _:3, _Opcode:4, _Mask:1, PayloadLen:7, Key:4/binary, Payload/binary>> when PayloadLen < 126 ->
      decode(Key, Payload);
    <<_Fin:1, _:3, _Opcode:4, _Mask:1, PayloadLen:7, _Len:32/integer, Key:4/binary, Payload/binary>> when PayloadLen =:= 126 ->
      decode(Key, Payload);
    <<_Fin:1, _:3, _Opcode:4, _Mask:1, PayloadLen:7, _Len:64/integer, Key:4/binary, Payload/binary>> when PayloadLen =:= 127 ->
      decode(Key, Payload);
    _Other ->
      {error, bad_format}
  end.

decode(Key, Data) when is_binary(Key) ->
  Keys = bin_to_list(Key, 1),
  decode(Keys, Data);

decode(Keys, Data) when is_list(Keys) ->
  decode(Keys, Data, []).

decode([H | T], Data, DecodedData) ->
  case Data of
    <<D:1/binary, Rest/binary>> -> 
      decode(T ++ [H], Rest, DecodedData ++ [crypto:exor(H, D)]);
    _ ->
      binary:list_to_bin(DecodedData)
  end.


bin_to_list(Data, Bitlen) ->
  bin_to_list(Data, Bitlen, []).

bin_to_list(Data, Bitlen, List) ->
  case Data of
    <<T:Bitlen/binary, Rest/binary>> ->
      bin_to_list(Rest, Bitlen, List ++ [T]);
    _ ->
      List
  end.

send(Socket, Msg) ->
  Len = byte_size(Msg),
  Frame = [<<129, Len>>, Msg],
  gen_tcp:send(Socket, Frame).
