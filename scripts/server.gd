#Network code from https://github.com/khairul169/fps-test
#Edited by Nik "Windastella" Mirza
extends Node

var packet = null;
var hosted = false;

var time = 0.0;
var server;
var maxplayer = 32;

var update_time = 0.0;
var netfps = 30.0;

const MODE_FFA = 0
const MODE_SP = 1
const MODE_MSP = 2
const MODE_DM = 3

var mapname = "test"
var gamemode = MODE_FFA

class CClient:
	var connected = false;
	var peer = null;
	var address = GDNetAddress.new();
	
	# Player Variable
	var name = "Player"
	var pos = Vector3()
	var rot = Vector3()
	var camrot = Vector3()
	var lv = Vector3()

var client = [];

const NET_PLAYER_VAR = 0;
const NET_CHAT = 1;
const NET_ACCEPTED = 2;
const NET_CMD = 3;
const NET_CLIENT_CONNECTED = 4;
const NET_CLIENT_DISCONNECTED = 5;
const NET_SRV_INIT = 6;
const NET_UPDATE = 7
const NET_MAPCHANGE = 8

const CMD_SET_POS = 0
const CMD_SET_NAME = 1

const SRV_DATA_PLAYER = 0

func _ready():
	var args = OS.get_cmdline_args();
	for i in args:
		if i == "-server":
			host();
			continue;

func _process(delta):
	if !hosted:
		return;
	
	time += delta;
	check_events();
	update_server();

func host(host = "localhost" ,port = 3000):
	if hosted:
		return;
	
	var address = GDNetAddress.new();
	address.set_host(host);
	address.set_port(port);

	packet = GDNetHost.new();
	var err = packet.bind(address);
	
	print(err);
	
	if !err:
		hosted = true;
		on_server_start();
		set_process(true);

func check_events():
	while packet.is_event_available():
		var event = packet.get_event();
		on_event_received(event);

func update_server():
	if time < update_time:
		return;
	update_time = time + (1.0/netfps);
	
	if gamemode == MODE_FFA:
		get_node("/root/mode_ffa").ffa_update()
		
	for i in range(0, client.size()):
		if !check_player(i):
			continue;
		
		var srv_data = [];
		
		for b in range(0, client.size()):
			if !check_player(b) || i == b:
				continue;
			srv_data.push_back([SRV_DATA_PLAYER, b, client[b].pos, client[b].rot, client[b].camrot, client[b].lv]);
		
		send2c(i, [], [NET_UPDATE, srv_data]);

func on_server_start():
	time = 0.0;
	
	mapname = get_node("/root/main/gui/menu/net/maplist").get_item_text(get_node("/root/main/gui/menu/net/maplist").get_selected())
	maxplayer = get_node("/root/main/gui/menu/net/label5").get_text().to_int()
	
	client.clear();
	client.resize(maxplayer);
	for i in range(0, client.size()):
		client[i] = CClient.new();
	
	set_process(true);
	print("Server started!")
	
func on_event_received(event):
	var peer = packet.get_peer(event.get_peer_id());
	
	if event.get_event_type() == GDNetEvent.CONNECT:
		var pid = get_empty_id();
			
		if pid != -1:
			client[pid].connected = true;
			client[pid].peer = peer
			client[pid].address = peer.get_address()
			
			send2c(pid, [], [NET_ACCEPTED, pid], true)
			send2c(pid, [], [NET_MAPCHANGE, mapname, gamemode], true)
			
			player_connected(pid);
		else:
			peer.disconnect()
			
		return
	
	elif event.get_event_type() == GDNetEvent.DISCONNECT:
		var pid = get_pid_from_peer(peer)
		if pid != -1:
			player_disconnected(pid)
			client[pid] = CClient.new()
		
		peer = null;
	
	elif event.get_event_type() == GDNetEvent.RECEIVE:
		var data = event.get_var();
		if data[0] == NET_PLAYER_VAR:
			var pid = data[1];
			if check_player(pid, peer.get_address()):
				client[pid].pos = data[2]
				client[pid].rot = data[3]
				client[pid].camrot = data[4]
				client[pid].lv = data[5]
		
		if data[0] == NET_CHAT:
			var pid = data[1];
			var text = data[2];
			if check_player(pid, peer.get_address()) && text.length() > 0:
				if text.begins_with("/"):
					var array = text.split(" ", false);
					parse_command(pid, array);
				else:
					send2c(-1, [], [NET_CHAT, "[Global] " + client[pid].name + ": "+text], true);
		
		return;

func check_player(pid, address = null):
	if pid != -1 && client[pid].connected:
		if address != null:
			if client[pid].address.get_host() != address.get_host() || client[pid].address.get_port() != address.get_port():
				return false;
		return true;
	return false;

func get_empty_id():
	for i in range(0, client.size()):
		if !check_player(i):
			return i;
	return -1;

func get_pid_from_peer(peer):
	for i in range(0, client.size()):
		if client[i].peer.get_peer_id() == peer.get_peer_id():
			return i;
	return -1;

func send2c(pid, excl, data, rel = false):
	var msg_type = GDNetMessage.UNSEQUENCED;
	if rel:
		msg_type = GDNetMessage.RELIABLE;
	
	if pid >= 0:
		if check_player(pid) && client[pid].peer != null:
			client[pid].peer.send_var(data, 0, msg_type);
	else:
		for i in range(0, client.size()):
			if !check_player(i) || i in excl || client[i].peer == null:
				continue;
			client[i].peer.send_var(data, 0, msg_type);

func player_connected(pid):
	var srv_data = [];
	
	# PLayer Data
	for id in range(0, client.size()):
		if check_player(id) && id != pid:
			srv_data.push_back([SRV_DATA_PLAYER, id]);
	
	send2c(pid, [], [NET_SRV_INIT, srv_data], true);
	
	send2c(-1, [pid], [NET_CLIENT_CONNECTED, pid], true);
	
	print(client[pid].name + " connected.");
	send2c(-1, [], [NET_CHAT, client[pid].name + " connected."], true);

func player_disconnected(pid):
	send2c(-1, [pid], [NET_CLIENT_DISCONNECTED, pid], true);
	
	print(client[pid].name + " disconnected.");
	send2c(-1, [pid], [NET_CHAT, client[pid].name + " disconnected."], true);

func parse_command(parser, cmd):
	if cmd[0] == "/unstuck":
		send2c(parser, [], [NET_CMD, CMD_SET_POS, Vector3()], true);
	if cmd[0] == "/setname" && cmd.size() > 1 && cmd[1] != "":
		send2c(-1, [], [NET_CMD, CMD_SET_NAME, parser, cmd[1]], true);
