-module(auth_hub_api_handler).
-author('Mykhailo Krasniuk <miha.190901@gmail.com>').

-export([init/2]).

-include("auth_hub.hrl").

-spec init(tuple(), list()) -> term().
init(Req, Opts) ->
    {HttpCode, RespMap} = handle_http_method(Req, Opts),
    RespBody = jsone:encode(RespMap),
    Resp = cowboy_req:reply(HttpCode, #{<<"content-type">> => <<"application/json; charset=UTF-8">>}, RespBody, Req),
    {ok, Resp, Opts}.

-spec handle_http_method(tuple(), list()) -> {integer(), map()}.
handle_http_method(Req, Opts) ->
    case {cowboy_req:method(Req), Opts} of
        {<<"POST">>, [<<"/users">>]} ->
            {HttpCode, RespMap} = handle_sid(null, Req),
            ?LOG_DEBUG("Post reply ~p", [HttpCode]),
            {HttpCode, RespMap};
        {<<"GET">>, [<<"/users/info">>]} ->
            {HttpCode, RespMap} = handle_sid(get_users_all_info, Req),
            ?LOG_DEBUG("Get reply ~p", [HttpCode]),
            {HttpCode, RespMap};
        {<<"POST">>, [<<"/roles/change">>]} ->
            {HttpCode, RespMap} = handle_sid(null, Req),
            ?LOG_DEBUG("Post reply ~p", [HttpCode]),
            {HttpCode, RespMap};
        {Method, _} ->
            ?LOG_ERROR("Method ~p not allowed ~p~n", [Method, Req]),
            {405, ?RESP_FAIL(<<"method not allowed">>)}
    end.

-spec handle_sid(atom(), tuple()) -> {integer(), map()}.
handle_sid(UrlCase, Req) ->
    Sid = cowboy_req:header(<<"sid">>, Req, undefined),
    case auth_hub_helper:check_sid(Sid) of
        {Sid, Login, null, TsEnd} ->
            case auth_hub_pg:get_roles(Login) of
                null ->
                    {502, ?RESP_FAIL(<<"invalid db resp">>)};
                RolesMap ->
                    true = ets:insert(sids_cache, {Sid, Login, RolesMap, TsEnd}),
                    handle_body(UrlCase, RolesMap, Req)
            end;
        {Sid, _Login, RolesMap, _TsEnd} ->
            handle_body(UrlCase, RolesMap, Req);
        _Error ->
            ?LOG_ERROR("sid is invalid or legacy", []),
            {403, ?RESP_FAIL(<<"sid is invalid or legacy">>)}
    end.

-spec handle_body(atom(), map(), tuple()) -> {integer(), map()}.
handle_body(get_users_all_info, RolesMap, _Req) ->
    handle_auth(<<"get_users_all_info">>, RolesMap, #{});
handle_body(UrlCase, RolesMap, Req) ->
    case cowboy_req:has_body(Req) of
        true ->
            {ok, Body, _Req} = cowboy_req:read_body(Req),
            case {jsone:try_decode(Body), UrlCase} of
                {{error, Reason}, _} ->
                    ?LOG_ERROR("Decode error, ~p", [Reason]),
                    {400, ?RESP_FAIL(<<"invalid request format">>)};
                {{ok, #{<<"method">> := Method} = BodyMap, _}, _} ->
                    handle_auth(Method, RolesMap, BodyMap);
                {{ok, OtherMap, _}, _} ->
                    ?LOG_ERROR("Absent needed params ~p", [OtherMap]),
                    {422, ?RESP_FAIL(<<"absent needed params">>)}
            end;
        false ->
            ?LOG_ERROR("Missing body ~p~n", [Req]),
            {400, ?RESP_FAIL(<<"missing body">>)}
    end.

-spec handle_auth(binary(), map(), map()) -> {integer(), map()}.
handle_auth(Method, RolesMap, BodyMap) ->
    Roles = maps:get(?SERVICE_SUBSYSTEM, RolesMap, []),
    case maps:get(Method, ?SERVICE_ROLES, undefined) of
        undefined ->
            ?LOG_ERROR("Invalid method", []),
            {422, ?RESP_FAIL(<<"invalid method">>)};
        PermitRoles ->
            case auth_hub_helper:check_roles(Roles, PermitRoles) of
                false ->
                    ?LOG_ERROR("Absent roles ~p in ~p", [PermitRoles, Roles]),
                    {401, ?RESP_FAIL(<<"absent role">>)};
                true ->
                    handle_method(Method, BodyMap)
            end
    end.

-spec handle_method(binary(), map()) -> {integer(), binary()}.
handle_method(<<"create_users">>, #{<<"users">> := ListMap}) when is_list(ListMap) ->
    try poolboy:checkout(pg_pool, 1000) of
        full ->
            ?LOG_ERROR("No workers in pg_pool", []),
            {429, ?RESP_FAIL(<<"too many requests">>)};
        WorkerPid ->
            Reply = create_users(ListMap, WorkerPid),
            ok = poolboy:checkin(pg_pool, WorkerPid),
            {200, #{<<"results">> => Reply}}
    catch
        exit:{timeout, Reason} ->
            ?LOG_ERROR("No workers in pg_pool ~p", [Reason]),
            {429, ?RESP_FAIL(<<"too many requests">>)}
    end;
handle_method(<<"delete_users">>, #{<<"logins">> := ListMap}) when is_list(ListMap) ->
    try poolboy:checkout(pg_pool, 1000) of
        full ->
            ?LOG_ERROR("No workers in pg_pool", []),
            {429, ?RESP_FAIL(<<"too many requests">>)};
        WorkerPid ->
            Reply = delete_users(ListMap, WorkerPid),
            ok = poolboy:checkin(pg_pool, WorkerPid),
            {200, #{<<"results">> => Reply}}
    catch
        exit:{timeout, Reason} ->
            ?LOG_ERROR("No workers in pg_pool ~p", [Reason]),
            {429, ?RESP_FAIL(<<"too many requests">>)}
    end;
handle_method(<<"get_users_all_info">>, _Map) ->
    case auth_hub_pg:select("get_users_all_info", []) of
        {error, Reason} ->
            ?LOG_ERROR("Invalid db response, ~p", [Reason]),
            {502, ?RESP_FAIL(<<"invalid db response">>)};
        {ok, _Colons, DbResp} ->
            UsersMap = parse_users_info(DbResp, #{}),
            Logins = maps:keys(UsersMap),
            ListResp = construct_response(Logins, UsersMap),
            {200, ?RESP_SUCCESS(ListResp)}
    end;

handle_method(Method, #{<<"changes">> := ListOperations}) when (Method =:= <<"add_roles">>) or (Method =:= <<"delete_roles">>) ->
    try poolboy:checkout(pg_pool, 1000) of
        full ->
            ?LOG_ERROR("No workers in pg_pool", []),
            {429, ?RESP_FAIL(<<"too many requests">>)};
        WorkerPid ->
            Reply = handler_change_roles(Method, ListOperations),
            ok = poolboy:checkin(pg_pool, WorkerPid),
            {200, #{<<"results">> => Reply}}
    catch
        exit:{timeout, Reason} ->
            ?LOG_ERROR("No workers in pg_pool ~p", [Reason]),
            {429, ?RESP_FAIL(<<"too many requests">>)}
    end;

handle_method(<<"show_allow_roles">>, _Map) ->
    [{_, Pid}] = ets:lookup(auth_hub, auth_hub_server),
    Reply = gen_server:call(Pid, {show_allow_roles}),
    {200, jsone:encode(Reply)};
handle_method(<<"add_allow_roles">>, Map) ->
    [{_, Pid}] = ets:lookup(auth_hub, auth_hub_server),
    #{<<"roles">> := ListRoles} = Map,
    Reply = gen_server:call(Pid, {add_allow_roles, ListRoles}),
    {200, jsone:encode(Reply)};
handle_method(<<"delete_allow_roles">>, Map) ->
    [{_, Pid}] = ets:lookup(auth_hub, auth_hub_server),
    #{<<"roles">> := ListRoles} = Map,
    Reply = gen_server:call(Pid, {delete_allow_roles, ListRoles}),
    {200, jsone:encode(Reply)};
handle_method(_Method, _OtherBody) ->
    ?LOG_ERROR("Incorrect body or method", []),
    {422, ?RESP_FAIL(<<"invalid request format">>)}.


%% ========= change_roles =========

-spec handler_change_roles(binary(), list()) -> list().
handler_change_roles(_Method, []) -> [];
handler_change_roles(<<"add_roles">>, [#{<<"login">> := Login, <<"subsystem">> := SubSys, <<"roles">> := Roles} = MapReq | T]) ->
    case validation_param(Login, SubSys, Roles) of
        false ->
            ?LOG_ERROR("handler_change_roles invalid params value", []),
            MapResp = MapReq#{<<"success">> => false, <<"reason">> => <<"invalid params value">>},
            [MapResp | handler_change_roles(<<"add_roles">>, T)];
        true ->
            case generate_insert_sql(first, Roles, Login, SubSys, ?SQL_INSERT_ROLES) of
                null ->
                    MapResp = MapReq#{<<"success">> => true},
                    [MapResp | handler_change_roles(<<"add_roles">>, T)];
                Sql ->
                    case auth_hub_pg:sql_req_not_prepared(Sql, []) of
                        {error, {_, _, _, unique_violation, _, _} = Reason} ->
                            ?LOG_ERROR("handler_change_roles user have one of this roles, ~p", [Reason]),
                            MapResp = MapReq#{<<"success">> => false, <<"reason">> => <<"user have one of this roles">>},
                            [MapResp | handler_change_roles(<<"add_roles">>, T)];
                        {error, {_, _, _, foreign_key_violation, _, _} = Reason} ->
                            ?LOG_ERROR("handler_change_roles invalid login, ~p", [Reason]),
                            MapResp = MapReq#{<<"success">> => false, <<"reason">> => <<"invalid login">>},
                            [MapResp | handler_change_roles(<<"add_roles">>, T)];
                        {error, Reason} ->
                            ?LOG_ERROR("handler_change_roles db error ~p", [Reason]),
                            MapResp = MapReq#{<<"success">> => false, <<"reason">> => <<"invalid db resp">>},
                            [MapResp | handler_change_roles(<<"add_roles">>, T)];
                        {ok, _Count} ->
                            MapResp = MapReq#{<<"success">> => true},
                            [MapResp | handler_change_roles(<<"add_roles">>, T)]
                    end
            end
    end;
handler_change_roles(<<"delete_roles">>, [#{<<"login">> := Login, <<"subsystem">> := SubSys, <<"roles">> := Roles} = MapReq | T]) ->
    case validation_param(Login, SubSys, Roles) of
        false ->
            ?LOG_ERROR("handler_change_roles invalid params value", []),
            MapResp = MapReq#{<<"success">> => false, <<"reason">> => <<"invalid params value">>},
            [MapResp | handler_change_roles(<<"delete_roles">>, T)];
        true ->
            LoginStr = binary_to_list(Login),
            SubSysStr = binary_to_list(SubSys),
            case generate_delete_sql(first, Roles, ?SQL_DELETE_ROLES(LoginStr, SubSysStr)) of
                null ->
                    MapResp = MapReq#{<<"success">> => true},
                    [MapResp | handler_change_roles(<<"delete_roles">>, T)];
                Sql ->
                    case auth_hub_pg:sql_req_not_prepared(Sql, []) of
                        {error, Reason} ->
                            ?LOG_ERROR("handler_change_roles db error ~p", [Reason]),
                            MapResp = MapReq#{<<"success">> => false, <<"reason">> => <<"invalid db resp">>},
                            [MapResp | handler_change_roles(<<"delete_roles">>, T)];
                        {ok, _Count} ->
                            MapResp = MapReq#{<<"success">> => true},
                            [MapResp | handler_change_roles(<<"delete_roles">>, T)]
                    end
            end
    end;
handler_change_roles(Method, [MapReq | T]) ->
    ?LOG_ERROR("handler_change_roles absent needed params, ~p", [MapReq]),
    MapResp = MapReq#{<<"success">> => false, <<"reason">> => <<"absent needed params">>},
    [MapResp | handler_change_roles(Method, T)].

-spec validation_param(term(), term(), term()) -> boolean().
validation_param(Login, SubSys, Roles) when is_binary(Login) and is_binary(SubSys) and is_list(Roles) ->
    ValidSubSys = ets:member(subsys_cache, SubSys),
    ValidRoles = valid_roles(Roles),
    ValidLogin = valid_login(Login),
    ValidSubSys and ValidLogin and ValidRoles;
validation_param(_Login, _SubSys, _Roles) ->
    false.

-spec valid_roles(list()) -> boolean().
valid_roles([]) -> true;
valid_roles([Role | T]) when is_binary(Role) ->
    case {match, [{0, byte_size(Role)}]} =:= re:run(Role, "[a-z]{2}", []) of
        true ->
            valid_roles(T);
        false ->
            false
    end;
valid_roles(_) ->
    false.

-spec generate_delete_sql(first | second, list(), string()) -> string() | null.
generate_delete_sql(first, [], _Sql) -> null;
generate_delete_sql(second, [], Sql) ->
    ?LOG_DEBUG("Delete roles sql ~p", [Sql ++ ")"]),
    Sql ++ ")";
generate_delete_sql(first, [Role | T], Sql) ->
    Sql1 = Sql ++ "role='" ++ binary_to_list(Role) ++ "'",
    generate_delete_sql(second, T, Sql1);
generate_delete_sql(second, [Role | T], Sql) ->
    Sql1 = Sql ++ " or role='" ++ binary_to_list(Role) ++ "'",
    generate_delete_sql(second, T, Sql1).

-spec generate_insert_sql(first | second, list(), binary(), binary(), string()) -> string() | null.
generate_insert_sql(first, [], _Login, _Subsys, _Sql) -> null;
generate_insert_sql(second, [], _Login, _Subsys, Sql) ->
    ?LOG_DEBUG("Insert roles sql ~p", [Sql ++ ")"]),
    Sql;
generate_insert_sql(first, [Role | T], Login, Subsys, Sql) ->
    Sql1 = Sql ++ "('" ++ binary_to_list(Login) ++ "', '" ++ binary_to_list(Subsys) ++ "', '" ++ binary_to_list(Role) ++ "')",
    generate_insert_sql(second, T, Login, Subsys, Sql1);
generate_insert_sql(second, [Role | T], Login, Subsys, Sql) ->
    Sql1 = Sql ++ ", ('" ++ binary_to_list(Login) ++ "', '" ++ binary_to_list(Subsys) ++ "', '" ++ binary_to_list(Role) ++ "')",
    generate_insert_sql(second, T, Login, Subsys, Sql1).


%% ========= get_all_users_info =========

-spec parse_users_info(DbResp :: list(), map()) -> map().
parse_users_info([], Result) -> Result;
parse_users_info([{Login, null, null} | T], Result) ->
    ListTab = ets:tab2list(subsys_cache),
    SubSystems = add_subsyses(ListTab, #{}),
    Result1 = Result#{Login => SubSystems},
    parse_users_info(T, Result1);
parse_users_info([{Login, SubSys, Role} | T], Result) ->
    Result1 = case maps:get(Login, Result, null) of
                  null ->
                      ListTab = ets:tab2list(subsys_cache),
                      SubSystems = add_subsyses(ListTab, #{}),
                      Result#{Login => SubSystems#{SubSys => [Role]}};
                  #{SubSys := Roles} = SubSyses ->
                      Result#{Login := SubSyses#{SubSys := [Role | Roles]}}
              end,
    parse_users_info(T, Result1).

-spec add_subsyses(list(), map()) -> map().
add_subsyses([], Result) -> Result;
add_subsyses([{SubSys} | T], Result) ->
    Result1 = Result#{SubSys => []},
    add_subsyses(T, Result1).

-spec construct_response(list(), map()) -> list().
construct_response([], _UsersMap) -> [];
construct_response([Login | T], UsersMap) ->
    #{Login := SubSystems} = UsersMap,
    SidList = ets:select(sids_cache, [{
        {'$1', '$2', '_', '_'},
        [{'=:=', '$2', Login}],
        ['$1']
    }]),
    ActiveSid = case SidList of
                    [] -> null;
                    [Sid] -> Sid
                end,
    MapResp = #{<<"login">> => Login, <<"subsystem_roles">> => SubSystems, <<"active_sid">> => ActiveSid},
    [MapResp | construct_response(T, UsersMap)].


%% ========= create_users =========

-spec create_users(list(), pid()) -> list().
create_users([], _PgPid) -> [];
create_users([#{<<"login">> := Login, <<"pass">> := Pass} | T], PgPid) when is_binary(Login) and is_binary(Pass) ->
    ValidLogin = valid_login(Login),
    ValidPass = valid_pass(Pass),
    case not(lists:member(false, [ValidLogin, ValidPass])) of
        true ->
            [{salt, Salt}] = ets:lookup(opts, salt),
            SaltBin = list_to_binary(Salt),
            PassHash = io_lib:format("~64.16.0b", [binary:decode_unsigned(crypto:hash(sha256, <<Pass/binary, SaltBin/binary>>))]),
            case auth_hub_pg:insert(PgPid, "create_user", [Login, PassHash]) of
                {error, {_, _, _, unique_violation, _, [{constraint_name, <<"unique_pass">>} | _]} = Reason} ->
                    ?LOG_ERROR("create_users incorrect pass ~p", [Reason]),
                    [?RESP_FAIL_USERS(Login, <<"this pass is using now">>) | create_users(T, PgPid)];
                {error, {_, _, _, unique_violation, _, [{constraint_name, <<"login_pk">>} | _]} = Reason} ->
                    ?LOG_ERROR("create_users incorrect pass ~p", [Reason]),
                    [?RESP_FAIL_USERS(Login, <<"this login is using now">>) | create_users(T, PgPid)];
                {error, Reason} ->
                    ?LOG_ERROR("create_users db error ~p", [Reason]),
                    [?RESP_FAIL_USERS(Login, <<"invalid db response">>) | create_users(T, PgPid)];
                {ok, 1} ->
                    [#{<<"login">> => Login, <<"success">> => true} | create_users(T, PgPid)]
            end;
        false ->
            ?LOG_ERROR("create_users invalid params, login ~p", [Login]),
            [?RESP_FAIL_USERS(Login, <<"invalid params">>) | create_users(T, PgPid)]
    end;
create_users([_OtherMap | T], PgPid) -> create_users(T, PgPid).

-spec valid_login(binary()) -> boolean().
valid_login(Login) when (byte_size(Login) > 2) and (byte_size(Login) < 50) ->
    Len = byte_size(Login),
    {match, [{0, Len}]} =:= re:run(Login, "[a-zA-Z][a-zA-Z_\\d]*", []);
valid_login(_Login) -> false.

-spec valid_pass(binary()) -> boolean().
valid_pass(Pass) when (byte_size(Pass) >= 8) and (byte_size(Pass) < 100) ->
    Len = byte_size(Pass),
    {match, [{0, Len}]} =:= re:run(Pass, "[a-zA-Z_\\d-#&$%]*", []);
valid_pass(_Other) -> false.


%% ========= delete_users =========

-spec delete_users(list(), pid()) -> list().
delete_users([], _WorkerPid) -> [];
delete_users([Login | T], PgPid) when is_binary(Login) ->
    case valid_login(Login) of
        false ->
            ?LOG_ERROR("delete_users invalid params, login ~p", [Login]),
            [?RESP_FAIL_USERS(Login, <<"invalid login">>) | delete_users(T, PgPid)];
        true ->
            case auth_hub_pg:delete(PgPid, "delete_user", [Login]) of
                {error, Reason} ->
                    ?LOG_ERROR("delete_users db error ~p", [Reason]),
                    [?RESP_FAIL_USERS(Login, <<"invalid db response">>) | delete_users(T, PgPid)];
                {ok, _Column, [{<<"ok">>}]} ->
                    ok = ets_delete_sid(Login),
                    [#{<<"login">> => Login, <<"success">> => true} | delete_users(T, PgPid)]
            end
    end;
delete_users([Login | T], PgPid) ->
    ?LOG_ERROR("delete_users invalid params, login ~p", [Login]),
    [?RESP_FAIL_USERS(Login, <<"invalid login">>) | delete_users(T, PgPid)].

-spec ets_delete_sid(binary()) -> ok.
ets_delete_sid(Login) ->
    SidList = ets:select(sids_cache, [{
        {'$1', '$2', '_', '_'},
        [{'=:=', '$2', Login}],
        ['$1']
    }]),
    case SidList of
        [Sid] ->
            true = ets:delete(sids_cache, Sid);
        [] ->
            ok
    end,
    ok.
