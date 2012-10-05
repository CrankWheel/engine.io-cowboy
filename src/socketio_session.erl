-module(socketio_session).

-behaviour(gen_server).

-include("socketio_internal.hrl").

%% API
-export([start_link/3, init/0, configure/3, create/3, find/1, pull/2, poll/1, send/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(ETS, socketio_session_table).

-record(state, {id,
                callback,
                messages,
                session_timeout,
                session_timeout_tref,
                caller,
                registered}).

%%%===================================================================
%%% API
%%%===================================================================
configure(Heartbeat, SessionTimeout, Callback) ->
    #config{heartbeat = Heartbeat,
            session_timeout = SessionTimeout,
            callback = Callback
           }.

init() ->
    _ = ets:new(?ETS, [public, named_table]),
    ok.

create(SessionId, SessionTimeout, Callback) ->
    {ok, Pid} = socketio_session_sup:start_child(SessionId, SessionTimeout, Callback),
    Pid.

find(SessionId) ->
    case ets:lookup(?ETS, SessionId) of
        [] ->
            {error, not_found};
        [{_, Pid}] ->
            {ok, Pid}
    end.

pull(Pid, Caller) ->
    gen_server:call(Pid, {pull, Caller}, infinity).

poll(Pid) ->
    gen_server:call(Pid, {poll}, infinity).

send(Pid, Message) ->
    gen_server:cast(Pid, {send, Message}).
%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(SessionId, SessionTimeout, Callback) ->
    gen_server:start_link(?MODULE, [SessionId, SessionTimeout, Callback], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([SessionId, SessionTimeout, Callback]) ->
    process_flag(trap_exit, true),
    self() ! register_in_ets,
    TRef = erlang:send_after(SessionTimeout, self(), session_timeout),
    {ok, #state{id = SessionId,
                messages = [],
                registered = false,
                callback = Callback,
                session_timeout_tref = TRef,
                session_timeout = SessionTimeout}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call({pull, Pid}, _From,  State = #state{messages = Messages, caller = undefined}) ->
    erlang:monitor(process, Pid),
    State1 = refresh_session_timeout(State),
    {reply, lists:reverse(Messages), State1#state{caller = Pid, messages = []}};

handle_call({pull, _Pid}, _From,  State)  ->
    {reply, session_in_use, State};

handle_call({poll}, _From, State = #state{messages = Messages}) ->
    State1 = refresh_session_timeout(State),
    {reply, lists:reverse(Messages), State1#state{messages = []}};

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast({send, Message}, State = #state{messages = Messages, caller = Caller}) ->
    case Caller of
        undefined ->
            ok;
        _ ->
            Caller ! {message_arrived, self()}
    end,
    {noreply, State#state{messages = [Message|Messages]}};

handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(session_timeout, State) ->
    error_logger:info_msg("Socketio session ~p timeout~n", [State#state.id]),
    {stop, normal, State};

handle_info(register_in_ets, State = #state{id = SessionId, registered = false}) ->
    case ets:insert_new(?ETS, {SessionId, self()}) of
        true ->
            {noreply, State#state{registered = true}};
        false ->
            {stop, session_id_exists, State}
    end;

handle_info({'DOWN', _Ref, process, CPid, _Reason}, State = #state{caller = CPid}) ->
    {noreply, State#state{caller = undefined}};

handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State = #state{id = SessionId}) ->
    ets:delete(?ETS, SessionId),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
refresh_session_timeout(State = #state{session_timeout = Timeout, session_timeout_tref = TRef}) ->
    erlang:cancel_timer(TRef),
    NewTRef = erlang:send_after(Timeout, self(), session_timeout),
    State#state{session_timeout_tref = NewTRef}.