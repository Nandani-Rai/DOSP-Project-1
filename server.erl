#!/usr/bin/env escript
%%! -smp enable

%% SERVER:  ./server <K>
%% Mines locally on all cores and accepts remote workers.
%% All coins found (local or remote) are printed here and logged to
%% coins.log, tagged with the node that found them. Every 20s it also
%% prints a summary of how many chunks each node has been given, so you
%% can directly see whether remote workers are contributing.

-define(GATORLINK, "d.surana").
-define(CHUNK, 100).
-define(COOKIE, cop5615).
-define(LOGFILE, "coins.log").
-define(STATS_INTERVAL, 20000).  %% ms between per-node stats prints

main([Arg]) ->
    application:start(crypto),
    application:start(timer),
    {K, []} = string:to_integer(Arg),

    Ip = my_ip(),
    os:cmd("epmd -daemon"),
    timer:sleep(200),
    net_kernel:start([list_to_atom("server@" ++ Ip), longnames]),
    erlang:set_cookie(node(), ?COOKIE),

    io:format("Server running at ~s, K = ~p~n", [Ip, K]),
    io:format("Logging every coin to ~s~n", [?LOGFILE]),

    BossPid = spawn(fun() -> boss(K, 0, #{}) end),
    register(boss, BossPid),
    timer:send_interval(?STATS_INTERVAL, BossPid, print_stats),

    N = erlang:system_info(schedulers_online),
    [spawn(fun() -> worker(boss) end) || _ <- lists:seq(1, N)],
    io:format("~p local workers started~n~n", [N]),

    timer:sleep(infinity).

%% Boss actor: hands out nonce ranges, prints/logs coins tagged by the
%% node that found them, and periodically reports chunks served per node.
boss(K, Next, Counts) ->
    receive
        {work, From} ->
            Node = node(From),
            NewCounts = maps:update_with(Node, fun(C) -> C + 1 end, 1, Counts),
            From ! {range, K, Next, Next + ?CHUNK},
            boss(K, Next + ?CHUNK, NewCounts);

        {coin, From, Str, Hash} ->
            Line = io_lib:format("[~p] ~s\t~s~n", [node(From), Str, Hash]),
            io:format("~s", [Line]),
            file:write_file(?LOGFILE, Line, [append]),
            boss(K, Next, Counts);

        print_stats ->
            io:format("--- chunks served per node (chunk = ~p nonces) ---~n", [?CHUNK]),
            maps:fold(fun(Node, Count, _) ->
                io:format("  ~p : ~p chunks (~p nonces)~n", [Node, Count, Count * ?CHUNK])
            end, ok, Counts),
            io:format("----------------------------------------------------~n"),
            boss(K, Next, Counts)
    end.

%% Worker actor: ask for a range, mine it, repeat.
worker(Boss) ->
    Boss ! {work, self()},
    receive
        {range, K, Start, End} -> mine(Boss, K, Start, End)
    after 5000 -> ok
    end,
    worker(Boss).

mine(_Boss, _K, N, End) when N >= End -> ok;
mine(Boss, K, N, End) ->
    Str = ?GATORLINK ++ ";" ++ integer_to_list(N),
    Hash = sha256(Str),
    case lists:prefix(lists:duplicate(K, $0), Hash) of
        true  -> Boss ! {coin, self(), Str, Hash};
        false -> ok
    end,
    mine(Boss, K, N + 1, End).

sha256(Str) ->
    lists:flatten([io_lib:format("~2.16.0b", [B])
                   || <<B>> <= crypto:hash(sha256, Str)]).

my_ip() ->
    {ok, Addrs} = inet:getif(),
    [Ip | _] = [I || {I = {A,_,_,_}, _, _} <- Addrs, A =/= 127],
    inet:ntoa(Ip).
