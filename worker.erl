#!/usr/bin/env escript
%%! -smp enable

%% WORKER:  ./worker <ServerIP>
%% Connects to the server, mines for it. Prints nothing when a coin is found;
%% the server prints and logs everything, tagged with this node's name.

-define(GATORLINK, "d.surana").   %% must match the server's
-define(COOKIE, cop5615).

main([ServerIp]) ->
    application:start(crypto),

    Ip = my_ip(),
    os:cmd("epmd -daemon"),
    timer:sleep(200),
    Name = "worker" ++ integer_to_list(rand:uniform(9999)),
    net_kernel:start([list_to_atom(Name ++ "@" ++ Ip), longnames]),
    erlang:set_cookie(node(), ?COOKIE),

    Server = list_to_atom("server@" ++ ServerIp),
    case net_kernel:connect_node(Server) of
        true ->
            N = erlang:system_info(schedulers_online),
            [spawn(fun() -> worker({boss, Server}) end) || _ <- lists:seq(1, N)],
            io:format("Connected to ~p, ~p workers mining~n", [Server, N]),
            timer:sleep(infinity);
        _ ->
            io:format("Could not connect to ~p~n", [Server]),
            halt(1)
    end.

%% Identical to the server's worker actor -- sending to {boss, Node} works
%% exactly like sending to a local process.
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
