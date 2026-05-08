-module(auth_hub_log).
-author('Mykhailo Krasniuk <miha.190901@gmail.com>').

-export([log/2, adding_handler/1, removing_handler/1, changing_config/3]).

log(#{level := _Level, msg := {Msg, _Arg}},  Config) when is_list(Msg) ->
  %  StrLog = lists:flatten(io_lib:format("[~p] " ++ Msg, [Level] ++ Arg)),
  %  BinLog = unicode:characters_to_binary(StrLog, utf8),
  %  _ = news_hub_telegram:send_log(BinLog),
    Config;
log(_Log, Config) ->
    %io:format("nLog = ~pn~n", [Log]),
    Config.

adding_handler(Config) ->
    {ok, Config}.

removing_handler(_Config) ->
    ok.

changing_config(_SetOrUpdate, _OldConfig, NewConfig) ->
    {ok, NewConfig}.