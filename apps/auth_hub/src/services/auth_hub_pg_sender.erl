-module(auth_hub_pg_sender).
-author('Mykhailo Krasniuk <miha.190901@gmail.com>').

-behaviour(gen_server).

-include("auth_hub.hrl").

-export([start_link/1, sql_request/3]).


%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3, atomic_transaction/3, sql_prepared_query/3]).


%% ------------------------------------------------------------------
%% API Main Functions
%% ------------------------------------------------------------------

start_link(Args) ->
    gen_server:start_link(?MODULE, Args, []).

-spec sql_request(pid(), list(), list()) -> {ok, list()} | {error, term()}.
sql_request(WorkerPid, Query, Args) ->
    gen_server:call(WorkerPid, {sql_request, Query, Args}, 3000).

sql_prepared_query(WorkerPid, Query, Args) ->
    gen_server:call(WorkerPid, {sql_prepared_query, Query, Args}, 3000).


-spec atomic_transaction(pid(), number(), list()) -> {ok, list()} | {error, term()}.
atomic_transaction(WorkerPid, 2, [{Sql1, Args1}, {Sql2, Args2}]) ->
    FunRef = fun(Conn) ->
                 Reply1 = epgsql:equery(Conn, Sql1, Args1),
                 Reply2 = epgsql:equery(Conn, Sql2, Args2),
                 [Reply1, Reply2]
             end,
    gen_server:call(WorkerPid, {atomic_transaction, FunRef}, 3000);
atomic_transaction(WorkerPid, 3, [{Sql1, Args1}, {Sql2, Args2}, {Sql3, Args3}]) ->
    FunRef = fun(Conn) ->
                 Reply1 = epgsql:equery(Conn, Sql1, Args1),
                 Reply2 = epgsql:equery(Conn, Sql2, Args2),
                 Reply3 = epgsql:equery(Conn, Sql3, Args3),
                 [Reply1, Reply2, Reply3]
             end,
    gen_server:call(WorkerPid, {atomic_transaction, FunRef}, 3000).


%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(Conn) ->
    parse(Conn),
    ?LOG_INFO("Successful connect to db. Parse OK", []),
    {ok, #{connection => Conn}}.

handle_call({sql_prepared_query, Statement, Args}, _From, #{connection := Conn} = State) ->
    Reply = epgsql:prepared_query(Conn, Statement, Args),
    {reply, Reply, State};
handle_call({sql_request, Statement, Args}, _From, #{connection := Conn} = State) ->
    Reply = epgsql:equery(Conn, Statement, Args),
    {reply, Reply, State};
handle_call({atomic_transaction, FunRef}, _From, #{connection := Conn} = State) ->
    Reply = epgsql:with_transaction(Conn, FunRef, [{rollback_on_error, true}]),
    {reply, Reply, State};
handle_call(Request, _From, State) ->
    ?LOG_ERROR("Unknown call msg in pg ~p~n", [Request]),
    {reply, ok, State}.

handle_cast(Msg, State) ->
    ?LOG_ERROR("Unknown cast msg in pg ~p~n", [Msg]),
    {noreply, State}.

handle_info(Info, State) ->
    ?LOG_ERROR("Unknown info msg in pg ~p~n", [Info]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


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