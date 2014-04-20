%% Copyright (c) 2014, Loïc Hoguin <essen@ninenines.eu>
%%
%% Permission to use, copy, modify, and/or distribute this software for any
%% purpose with or without fee is hereby granted, provided that the above
%% copyright notice and this permission notice appear in all copies.
%%
%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

-module(cowboy_test).
-compile(export_all).

%% Start and stop applications and their dependencies.

start(Apps) ->
	_ = [do_start(App) || App <- Apps],
	ok.

do_start(App) ->
	case application:start(App) of
		ok ->
			ok;
		{error, {not_started, Dep}} ->
			do_start(Dep),
			do_start(App)
	end.

stop(Apps) ->
	_ = [application:stop(App) || App <- Apps],
	ok.

%% Quick configuration value retrieval.

config(Key, Config) ->
	{_, Value} = lists:keyfind(Key, 1, Config),
	Value.

%% List of all test cases in the suite.

all(Suite) ->
	lists:usort([F || {F, 1} <- Suite:module_info(exports),
		F =/= module_info,
		F =/= test, %% This is leftover from the eunit parse_transform...
		F =/= all,
		F =/= groups,
		string:substr(atom_to_list(F), 1, 5) =/= "init_",
		string:substr(atom_to_list(F), 1, 4) =/= "end_",
		string:substr(atom_to_list(F), 1, 3) =/= "do_"
	]).

%% Support functions for testing using Gun.

gun_open(Config) ->
	gun_open(Config, []).

gun_open(Config, Opts) ->
	{ok, ConnPid} = gun:open("localhost", config(port, Config),
		[{retry, 0}, {type, config(type, Config)}|Opts]),
	ConnPid.

gun_monitor_open(Config) ->
	gun_monitor_open(Config, []).

gun_monitor_open(Config, Opts) ->
	ConnPid = gun_open(Config, Opts),
	{ConnPid, monitor(process, ConnPid)}.

gun_is_gone(ConnPid, MRef) ->
	receive {'DOWN', MRef, process, ConnPid, gone} -> ok
	after 500 -> error(timeout) end.

%% Support functions for testing using a raw socket.

raw_open(Config) ->
	Transport = case config(type, Config) of
		tcp -> gen_tcp;
		ssl -> ssl
	end,
	{_, Opts} = lists:keyfind(opts, 1, Config),
	{ok, Socket} = Transport:connect("localhost", config(port, Config),
		[binary, {active, false}, {packet, raw},
			{reuseaddr, true}, {nodelay, true}|Opts]),
	{raw_client, Socket, Transport}.

raw_send({raw_client, Socket, Transport}, Data) ->
	Transport:send(Socket, Data).

raw_recv_head({raw_client, Socket, Transport}) ->
	{ok, Data} = Transport:recv(Socket, 0, 5000),
	raw_recv_head(Socket, Transport, Data).

raw_recv_head(Socket, Transport, Buffer) ->
	case binary:match(Buffer, <<"\r\n\r\n">>) of
		nomatch ->
			{ok, Data} = Transport:recv(Socket, 0, 5000),
			raw_recv_head(Socket, Transport, << Buffer/binary, Data/binary >>);
		{_, _} ->
			Buffer
	end.

raw_expect_recv({raw_client, Socket, Transport}, Expect) ->
	{ok, Expect} = Transport:recv(Socket, iolist_size(Expect), 5000),
	ok.
