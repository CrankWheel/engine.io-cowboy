-module(demo).

-export([start/0, open/2, recv/3, close/2]).

start() ->
    ok = application:start(sasl),
    ok = application:start(crypto),
    ok = application:start(public_key),
    ok = application:start(ssl),
    ok = application:start(ranch),
    ok = application:start(cowboy),
    ok = application:start(socketio),

    Dispatch = [
                {'_', [
                       {[<<"socket.io">>, <<"1">>, '...'], socketio_handler, [socketio_session:configure(5000,
                                                                                                         30000,
                                                                                                         30000,
                                                                                                         ?MODULE,
                                                                                                         socketio_data_protocol)]},
                       {['...'], cowboy_static, [
                                                 {directory, {priv_dir, socketio, []}},
                                                 {mimetypes, [
                                                              {<<".html">>, [<<"text/html">>]},
                                                              {<<".css">>, [<<"text/css">>]},
                                                              {<<".js">>, [<<"application/javascript">>]}]}
                                                ]}
                      ]}
               ],

    cowboy:start_http(socketio_http_listener, 100, [{port, 8080}],
                      [{dispatch, Dispatch}]
                     ).

%% ---- Handlers
open(Pid, Sid) ->
    error_logger:info_msg("open ~p ~p~n", [Pid, Sid]),
    ok.

recv(Pid, _Sid, {json, _, <<>>, Json}) ->
    error_logger:info_msg("recv json ~p~n", [Json]),
    socketio_session:send_obj(Pid, Json),
    ok;

recv(Pid, Sid, Message) ->
    error_logger:info_msg("recv ~p ~p ~p~n", [Pid, Sid, Message]),
    ok.

close(Pid, Sid) ->
    error_logger:info_msg("close ~p ~p~n", [Pid, Sid]),
    ok.
