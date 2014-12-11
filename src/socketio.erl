%% @author Kirill Trofimov <sinnus@gmail.com>
%% @copyright 2012 Kirill Trofimov
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%    http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
-module(socketio).
-author('Kirill Trofimov <sinnus@gmail.com>').
-behaviour(application).
-export([start/0, start/2, stop/1, stop/0]).

start() ->
    ok = application:start(crypto),
    ok = application:start(asn1),
    ok = application:start(public_key),
    ok = application:start(ssl),
    ok = application:start(ranch),
    ok = application:start(cowlib),
    ok = application:start(cowboy),

    ok = mnesia:start(),
    ok = resource_discovery:start(),

    application:start(socketio).

start(_Type, _Args) ->
    ok = socketio_session:init(),
    socketio_sup:start_link().

stop(_State) ->
    ok.

stop() ->
    resource_discovery:stop(),
    mnesia:stop(),

    application:stop(cowboy),
    application:stop(cowlib),
    application:stop(ranch),
    application:stop(ssl),
    application:stop(public_key),
    application:stop(asn1),
    application:stop(crypto).