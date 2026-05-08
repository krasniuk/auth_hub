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
            Reply = gen_server:call(WorkerPid, {select, Statement, Args}),
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
        connection => undefined}}.

terminate(_, _State) ->
    ok.

handle_call(_, _, #{connection := undefined} = State) ->
    ?LOG_ERROR("auth_hub_pg: no connect to db", []),
    {reply, {error, no_connect}, State};
handle_call({insert, Statement, Args}, _From, State) ->
    #{connection := Conn} = State,
    Reply = sql_req_prepared(Conn, Statement, Args),
    {reply, Reply, State};
handle_call({select, Statement, Args}, _From, State) ->
    #{connection := Conn} = State,
    Reply = sql_req_prepared(Conn, Statement, Args),
    {reply, Reply, State};
handle_call({delete, Statement, Args}, _From, State) ->
    #{connection := Conn} = State,
    Reply = sql_req_prepared(Conn, Statement, Args),
    {reply, Reply, State};
handle_call({sql_req_not_prepared, Sql, Args}, _From, State) ->
    #{connection := Conn} = State,
    Resp = case epgsql:equery(Conn, Sql, Args) of
               {error, Reason} ->
                   ?LOG_ERROR("PostgreSQL sql_req_not_prepared error, ~tp, ~tp", [Sql, Reason]),
                   {error, Reason};
               RespOk -> RespOk
           end,
    {reply, Resp, State};
handle_call(Other, _From, State) ->
    ?LOG_CRITICAL("Invalid call to gen_server(auth_hub_pg) ~tp", [Other]),
    {reply, <<"Invalid req">>, State}.

handle_cast(Data, State) ->
    ?LOG_CRITICAL("handle_cast invalid req ~tp", [Data]),
    {noreply, State}.

handle_info(connect, #{connect_arg := Arg, timer_connect := TConn} = State) ->
    _ = erlang:cancel_timer(TConn),
    case epgsql:connect(Arg ++ [{timeout, 5000}]) of
        {ok, Pid} ->
            parse(Pid),
            ?LOG_INFO("Successful connect to db. Parse OK", []),
            {noreply, State#{connection := Pid}};
        {error, Reason} ->
            ?LOG_ERROR("Db connect error, ~tp", [Reason]),
            TConn1 = erlang:send_after(1000, self(), connect),
            {noreply, State#{connection := undefined, timer_connect := TConn1}}
    end;
handle_info(Data, State) ->
    ?LOG_CRITICAL("handle_info invalid req ~tp", [Data]),
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


% ====================================================
% Help-functions for inverse functions
% ====================================================

-spec parse(pid()) -> ok.
parse(Conn) ->
    {ok, _} = epgsql:parse(Conn, "get_passhash", "SELECT passhash FROM auth_hub.users WHERE login=$1", [varchar]),
    {ok, _} = epgsql:parse(Conn, "insert_sid", "INSERT INTO auth_hub.sids (login, sid, ts_end) VALUES ($1, $2, $3)", [varchar, varchar, timestamp]),
    {ok, _} = epgsql:parse(Conn, "get_roles", "SELECT subsystem, role, space FROM auth_hub.roles WHERE login=$1", [varchar]),
    {ok, _} = epgsql:parse(Conn, "update_sid", "UPDATE auth_hub.sids SET sid=$2, ts_end=$3 WHERE login=$1", [varchar, varchar, timestamp]),
    {ok, _} = epgsql:parse(Conn, "delete_user", "SELECT * FROM auth_hub.delete_user($1)", [varchar]),

    {ok, _} = epgsql:parse(Conn, "create_user", "INSERT INTO auth_hub.users (login, passhash) VALUES ($1, $2)", [varchar, varchar]),
    {ok, _} = epgsql:parse(Conn, "get_users_all_info", "SELECT u.login, r.subsystem, r.role, r.space FROM auth_hub.roles r RIGHT OUTER JOIN auth_hub.users u ON r.login = u.login", []),
    {ok, _} = epgsql:parse(Conn, "get_allow_roles", "SELECT s.subsystem, r.role, r.description FROM auth_hub.allow_roles r RIGHT OUTER JOIN auth_hub.allow_subsystems s ON r.subsystem = s.subsystem", []),
    {ok, _} = epgsql:parse(Conn, "get_allow_subsystem", "SELECT subsystem, description FROM auth_hub.allow_subsystems", []),
    {ok, _} = epgsql:parse(Conn, "insert_allow_role", "insert into auth_hub.allow_roles (subsystem, role, description) values ($1, $2, $3)", [varchar, varchar, varchar]),
    {ok, _} = epgsql:parse(Conn, "delete_allow_role", "select * from auth_hub.delete_allow_role($1, $2)", [varchar, varchar]),
    {ok, _} = epgsql:parse(Conn, "insert_allow_subsystem", "SELECT * FROM auth_hub.create_subsystem($1, $2)", [varchar, varchar]),
    {ok, _} = epgsql:parse(Conn, "delete_subsystem", "select * from auth_hub.delete_subsystem($1)", [varchar]),

    ok.

-spec sql_req_prepared(pid(), list(), list()) -> {error, term()} | {ok, Colon::list(), Val::list()} | {ok, integer()}.
sql_req_prepared(Conn, Statement, Args) ->
    case epgsql:prepared_query(Conn, Statement, Args) of
        {error, Error} ->
            ?LOG_ERROR("PostgreSQL prepared_query error(~tp): ~tp~n", [Statement, Error]),
            {error, Error};
        Other -> Other
    end.
