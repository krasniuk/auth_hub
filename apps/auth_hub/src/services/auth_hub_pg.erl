-module(auth_hub_pg).
-author('Mykhailo Krasniuk <miha.190901@gmail.com>').
-behavior(gen_server).

-include("auth_hub.hrl").

-export([start_link/1]). % Export for poolboy
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]). % Export for gen_server
-export([select/2, select/3, insert/2, insert/3, delete/2, delete/3, sql_req_not_prepared/2, sql_req_not_prepared/3, get_roles/1]).

% ====================================================
% Clients functions
% ====================================================

start_link(Args) ->
    gen_server:start_link(?MODULE, Args, []).

-spec get_roles(binary()) -> null | map().
get_roles(Login) ->
    case auth_hub_pg:select("get_roles", [Login]) of
        {error, Reason} ->
            ?LOG_ERROR("Get roles from db error, ~tp", [Reason]),
            null;
        {ok, _Colon, RespDb} ->
            convert_roles_from_db(RespDb, #{})
    end.

-spec convert_roles_from_db(list(), map()) -> map().
convert_roles_from_db([], Result) -> Result;
convert_roles_from_db([{<<"authHub">>, Role, Space}|T], Result) ->
    case maps:get(<<"authHub">>, Result, undefined) of
        undefined ->
            convert_roles_from_db(T, Result#{<<"authHub">> => #{Space => [Role]}});
        Spaces ->
            case maps:get(Space, Spaces, undefined) of
                undefined ->
                    convert_roles_from_db(T, Result#{<<"authHub">> := Spaces#{Space => [Role]}});
                Roles ->
                    Roles1 = Roles ++ [Role],
                    convert_roles_from_db(T, Result#{<<"authHub">> := Spaces#{Space := Roles1}})
            end
    end;
convert_roles_from_db([{SubSys, Role, _Space}|T], Result) ->
    case maps:get(SubSys, Result, undefined) of
        undefined ->
            convert_roles_from_db(T, Result#{SubSys => [Role]});
        Roles ->
            Roles1 = Roles ++ [Role],
            convert_roles_from_db(T, Result#{SubSys := Roles1})
    end.

-spec select(pid(), string(), list()) -> {ok, Colon::list(), Values::list()} | {error, Reason::term()|no_connect}.
select(WorkerPid, Statement, Args) ->
    gen_server:call(WorkerPid, {select, Statement, Args}).

-spec select(list(), list()) -> {ok, PropListAtr :: list(), PropListResp :: list()} | {error, Reason :: tuple()|no_connect}.
select(Statement, Args) ->
    try poolboy:checkout(pg_pool, 1000) of
        full ->
            ?LOG_ERROR("No workers in pg_pool", []),
            {error, {timeout_pull, <<"too many requests">>}};
        WorkerPid ->
            Reply = gen_server:call(WorkerPid, {select, Statement, Args}, 5000),
            ok = poolboy:checkin(pg_pool, WorkerPid),
            Reply
    catch
        exit:{timeout, Reason} ->
            ?LOG_ERROR("Error, no workers in pg_pool ~tp", [Reason]),
            {error, {timeout_pull, <<"too many requests">>}}
    end.

-spec insert(list(), list()) -> {ok, integer()} | {error, Reason :: tuple()|no_connect}.
insert(Statement, Args) ->
    try poolboy:checkout(pg_pool, 1000) of
        full ->
            ?LOG_ERROR("No workers in pg_pool", []),
            {error, {timeout_pull, <<"too many requests">>}};
        WorkerPid ->
            Reply = gen_server:call(WorkerPid, {insert, Statement, Args}),
            ok = poolboy:checkin(pg_pool, WorkerPid),
            Reply
    catch
        exit:{timeout, Reason} ->
            ?LOG_ERROR("Error, no workers in pg_pool ~tp", [Reason]),
            {error, {timeout_pull, <<"too many requests">>}}
    end.

-spec insert(pid(), list(), list()) -> {ok, integer()} | {error, Reason :: tuple()|no_connect}.
insert(WorkerPid, Statement, Args) ->
    gen_server:call(WorkerPid, {insert, Statement, Args}).

delete(Statement, Args) ->
    try poolboy:checkout(pg_pool, 1000) of
        full ->
            ?LOG_ERROR("No workers in pg_pool", []),
            {error, {timeout_pull, <<"too many requests">>}};
        WorkerPid ->
            Reply = gen_server:call(WorkerPid, {delete, Statement, Args}),
            ok = poolboy:checkin(pg_pool, WorkerPid),
            Reply
    catch
        exit:{timeout, Reason} ->
            ?LOG_ERROR("Error, no workers in pg_pool ~tp", [Reason]),
            {error, {timeout_pull, <<"too many requests">>}}
    end.

-spec delete(pid(), list(), list()) -> {ok, integer()} | {error, Reason :: tuple()|no_connect}.
delete(WorkerPid, Statement, Args) ->
    gen_server:call(WorkerPid, {delete, Statement, Args}).

-spec sql_req_not_prepared(list(), list()) -> {ok, Colomn::list(), list()}| {ok, list()} | {error, term()} | {error, {timeout_pull, binary()}}.
sql_req_not_prepared(Sql, Args) ->
    try poolboy:checkout(pg_pool, true, 1000) of
        full ->
            ?LOG_ERROR("No workers in pg_pool", []),
            {error, {timeout_pull, <<"too many requests">>}};
        WorkerPid ->
            DbResp = sql_req_not_prepared(WorkerPid, Sql, Args),
            ok = poolboy:checkin(pg_pool, WorkerPid),
            DbResp
    catch
        exit:{timeout, Reason} ->
            ?LOG_ERROR("Error, no workers in pg_pool ~tp", [Reason]),
            {error, {timeout_pull, <<"too many requests">>}}
    end.

-spec sql_req_not_prepared(pid(), list(), list()) -> {ok, Colomn::list(), list()} | {ok, list()} | {error, term()}.
sql_req_not_prepared(WorkerPid, Sql, Args) ->
    gen_server:call(WorkerPid, {sql_req_not_prepared, Sql, Args}).








% ====================================================
% Inverse functions
% ====================================================

init(Args) ->
    %?LOG_DEBUG("=========================== START db driver ============================", []),
    TConn = erlang:send_after(10, self(), connect),
    {ok, #{connect_arg => Args,
        timer_connect => TConn,
        timer_check_connect => undefined,
        db_sender_pid => undefined}}.

terminate(_, _State) ->
    ok.

handle_call(_, _, #{connection := undefined} = State) ->
    ?LOG_ERROR("auth_hub_pg: no connect to db", []),
    {reply, {error, no_connect}, State};
handle_call({insert, Statement, Args}, _From, #{db_sender_pid := DbSenderPid, timer_check_connect := TCheck} = State) ->
    _ = erlang:cancel_timer(TCheck),
    Reply = send_pg_req({sql_prepared_query, Statement, Args}, DbSenderPid),
    TCheck1 = erlang:send_after(60000, self(), check_connection),
    {reply, Reply, State#{timer_check_connect := TCheck1}};
handle_call({select, Statement, Args}, _From, #{db_sender_pid := DbSenderPid, timer_check_connect := TCheck} = State) ->
    _ = erlang:cancel_timer(TCheck),
    Reply = send_pg_req({sql_prepared_query, Statement, Args}, DbSenderPid),
    TCheck1 = erlang:send_after(60000, self(), check_connection),
    {reply, Reply, State#{timer_check_connect := TCheck1}};
handle_call({delete, Statement, Args}, _From, #{db_sender_pid := DbSenderPid, timer_check_connect := TCheck} = State) ->
    _ = erlang:cancel_timer(TCheck),
    Reply = send_pg_req({sql_prepared_query, Statement, Args}, DbSenderPid),
    TCheck1 = erlang:send_after(60000, self(), check_connection),
    {reply, Reply, State#{timer_check_connect := TCheck1}};
handle_call({sql_req_not_prepared, Sql, Args}, _From, #{db_sender_pid := DbSenderPid, timer_check_connect := TCheck} = State) ->
    _ = erlang:cancel_timer(TCheck),
    Resp = send_pg_req({sql_request, Sql, Args}, DbSenderPid),
    TCheck1 = erlang:send_after(60000, self(), check_connection),
    {reply, Resp, State#{timer_check_connect := TCheck1}};
handle_call(Other, _From, State) ->
    ?LOG_CRITICAL("Invalid call to gen_server(auth_hub_pg) ~tp", [Other]),
    {reply, <<"Invalid req">>, State}.

handle_cast(Data, State) ->
    ?LOG_CRITICAL("handle_cast invalid req ~tp", [Data]),
    {noreply, State}.

handle_info(connect, #{connect_arg := Arg, timer_connect := TConn} = State) ->
    _ = erlang:cancel_timer(TConn),
    case epgsql:connect(Arg ++ [{timeout, 1000}]) of
        {ok, Pid} ->
            {ok, PidDbSender} = auth_hub_pg_sender:start_link(Pid),
            TCheck = erlang:send_after(60000, self(), check_connection),
            {noreply, State#{db_sender_pid := PidDbSender, timer_check_connect := TCheck}};
        {error, Reason} ->
            ?LOG_ERROR("Db connect error, ~tp", [Reason]),
            TConn1 = erlang:send_after(1000, self(), connect),
            {noreply, State#{db_sender_pid := undefined, timer_connect := TConn1}}
    end;
handle_info(check_connection, #{timer_check_connect := TCheck, db_sender_pid := DbSenderPid} = State) ->
    _ = erlang:cancel_timer(TCheck),
    case auth_hub_pg_sender:sql_request(DbSenderPid, "select 0", []) of
        {ok, _Column, [{0}]} ->
            ?LOG_DEBUG("db check_connection ok", []),
            ok;
        {error, Reason} ->
            ?LOG_ERROR("Pg timer check_connection, invalid db response ~p", [Reason])
    end,
    TCheck1 = erlang:send_after(60000, self(), check_connection),
    {noreply, State#{timer_check_connect := TCheck1}};
handle_info(Data, State) ->
    ?LOG_CRITICAL("handle_info invalid req ~tp", [Data]),
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


% ====================================================
% Help-functions for inverse functions
% ====================================================

-spec send_pg_req(tuple(), pid()) -> tuple() | ok.
send_pg_req({sql_prepared_query, Query, Args}, DbSenderPid) ->
    auth_hub_pg_sender:sql_prepared_query(DbSenderPid, Query, Args);
send_pg_req({sql_request, Query, Args}, DbSenderPid) ->
    auth_hub_pg_sender:sql_request(DbSenderPid, Query, Args);
send_pg_req({atomic_transaction, ListReq}, DbSenderPid) ->
    auth_hub_pg_sender:atomic_transaction(DbSenderPid, length(ListReq), ListReq);
send_pg_req(Msg, _DbSenderPid) ->
    ?LOG_ERROR("Unknown cast msg pg ~p", [Msg]),
    ok.

