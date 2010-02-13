package FreeCiv;

use File::Tail::Multi;
use Data::Dumper;
use DateTime;
use Data::Dumper;
use Hash::Merge qw(merge);
use Config::Simple;
use Path::Class;
use IPC::Open2;

Hash::Merge::set_behavior( 'RIGHT_PRECEDENT' );

use UNIVERSAL qw(isa);

sub new {

	my ($class, $args) = @_;
	# allow things to be overriden
	$args ||= {};
	
	my $self = bless $args, $class;
	$self->_init;
	return $self;

}

sub _init {

	my ($self) = @_;
	
	$self->{data}->{turn_count} = -1;
	$self->{data}->{turns} = {};
	$self->{data}->{turns}->{-1}->{start_time}  = "" . DateTime->now();
	$self->{data}->{players} = {};
	$self->{players} = {};
#	$self->{port} = 0;

}

sub loadfiles {
	my ($self, $args) = @_;
	$self->{tail}=File::Tail::Multi->new (  
#		Debug => 1,
		OutputPrefix => "f", 
		RemoveDuplicate => 0,
		ScanForFiles => 1,
		Files => [$args->{log_file}, $args->{server_file}],
#		Function => \&_gotlines,
		Function => sub { $self->_gotlines( @_); }
#		LastRun_File => $args->{lastrun_dir} . "/",
	);

}

sub dumpoutput {
	my ($self, $args) = @_;
	open FILE, ">", $args->{output_filename} or warn "Cant open file";
	$Data::Dumper::Purity = 1;
	print FILE Dumper($self->{data});
	$Data::Dumper::Purity = 0;
	close FILE;
}
#sub dumpoutputall

sub readlines {
	my ($self, $args) = @_;
	#print "Readlines!\n";
	$self->{tail}->read;
}

sub _gotlines {
	my ($self, $lines_ref) = @_;
	my $line;
	#print "Got Lines!\n";
	foreach ( @{$lines_ref} ) {
#		print "TEST $_";
		$line = $_;
		if ($line =~ /game.log : (.*)/) {
			$self->_parse_log($1);
		}
		if ($line =~ /server.output : (.*)/) {
			$self->_parse_server($1);
		}
		
	}

}
sub _parse_savegame {
	my ($self, $filename) = @_;
	my $current_turn = $self->current_turn;
	my $decomp_file = file($self->{dir_log}, "lastsave.out");
	my $player_number = -2;
	my $players = {};
	$self->debug("****************** STARTING THE NEW FANGLED SAVEGAME SCRAPER ****");

	if (-f $filename) {
		$self->debug("Decompressing File.....");
		system ("gzip -cd $filename > $decomp_file");
		open (SAVEGAME, "< $decomp_file");
        	while ( <SAVEGAME> ) {
			if (/\[game\]/) {
				$player_number = -2;
				$self->debug("Looking at GAME data");
			}
			if (/\[map\]/) {
				$player_number = -1;
				$self->debug("Looking at MAP data");
			}
			if (/\[player(\d+)\]/) {
				$player_number = $1;	
				$self->debug("Were onto plater $1 now");
				$players->{$1} = {};
				$players->{$1}->{ip} = $self->{data}->{players}->{$1}->{ip};
				$players->{$1}->{connected} = $self->{players}->{$1}->{connected};
				$self->debug("*** UPDATE Backup Dump: ". Dumper ($self->{players}->{$1}));
				$self->debug("*** UPDATE Main Dump: ". Dumper ($players->{$1}));
				$players->{$1}->{number} = $1;
			}
			if ($player_number == -2) {
				if (/nplayers=(\d+)/) {	
					$self->{data}->{player_count} = $1;
					$self->debug("Player count updated");
				}
				if (/^year=(-?\d+)/) {
					$self->{data}->{year} = $1;	
					$self->debug("Year Updated");
				}
				if (/end_year=(-?\d+)/) {
					$self->{data}->{end_year} = $1;
				}
				if (/fogofwar=(\d+)/) {
					$self->{data}->{fogofwar} = $1;
					$self->debug("Fog of war updated");
				}
				if (/spacerace=(\d+)/) {
					$self->{data}->{spacerace} = $1;
					$self->debug("Space Race updated");
				}
				if (/rulesetdir=(\d+)/) {
					$self->{data}->{ruleset} = $1;
					$self->debug("Ruleset Updated");
				}
			}
			if ($player_number >= 0) {
				if (/^name=\"(.*)\"/) {
					$players->{$player_number}->{leader} = $1;
					$self->debug("Player Leader $1 Updated");	
				}
				if (/^username=\"(.*)\"/) {
					$players->{$player_number}->{name} = $1;
					$self->debug("Player Name $1 Updated");
				}
				if (/team_no=(\d+)/) {
					$players->{$player_number}->{team} = $1;
					$self->debug("Team $1 set");
				}
				if (/city_style=(\d+)/) {
					$players->{$player_number}->{city_style} = $1;
					$self->debug("City Style set to $1");
				}
				if (/city_style_by_name=\"(.*)\"/) {
					$players->{$player_number}->{city_style_by_name} = $1;
					$self->debug("City Style name set to $1");
				}
				if (/nation=\"(.*)\"/) {
					$players->{$player_number}->{nation} = $1;
					$self->debug("Nation set to $1");
					$player->{$player_number} = $self->extractflagfromnationruleset($players->{$player_number});
					$self->debug("Flag also set");
				}
				if (/is_male=(\d+)/) {
					$players->{$player_number}->{is_male} = $1;
					$self->debug("Player is male: $1");
				}
				if (/is_alive=(\d+)/) {
					$players->{$player_number}->{is_alive} = $1;
					$self->debug("Player alive = $1");
					$current_turn->{players}->{$player_number}->{is_alive} = $1;
					$self->debug("Player alive = $1 this turn");
				}
				if (/government_name=\"(.*)\"/) {
					$players->{$player_number}->{government} = $1;
					$self->debug("Government set to $1");
					$current_turn->{players}->{$player_number}->{government} = $1;
					$self->debug("Government set to $1 for this turn");
				}
				if (/ai\.control=(\d+)/) {
					if ($1 == 1) {
						$players->{$player_number}->{type} = "AI";
					}
					else {
						$players->{$player_number}->{type} = "HUMAN";
					}
				}
				if (/ai\.skill_level=(\d+)/) {
					$players->{$player_number}->{aiskill} = "$1 - FIXME look up index";
				}
				if (/gold=(\d+)/) {
					$players->{$player_number}->{gold} = $1;
					$current_turn->{players}->{$player_number}->{gold} = $1;
				}
				if (/bulbs_last_turn=(\d+)/) {
					$players->{$player_number}->{research} = $1;
					$current_turn->{players}->{$player_number}->{research} = $1;
				}
				if (/nunits=(\d+)/) {
					$players->{$player_number}->{units} = $1;
					$current_turn->{players}->{$player_number}->{units} = $1;
				}
				if (/ncities=(\d+)/) {
					$players->{$player_number}->{cities} = $1;
					$current_turn->{players}->{$player_number}->{cities} = $1;
				}
			}
		}
        	close (SAVEGAME);
		$self->debug("Copying over players");
		$self->{data}->{players} = $players;
	}

	
}

sub _parse_server {
	my ($self, $line) = @_;
	my $current_turn = $self->current_turn;

	## AI difficalty
	#if ($line =~ /\'\/(novice|easy|normal|hard) \"(.*)\"\'/) {
	#	my $player = {
	#		name => $2,
	#		type => "AI",
	#		difficulty => $1,
	#		connected => 1,
	#	};
	#	$self->debug("player $2 has become $player->{difficulty} ai");
	#	$self->set_player($player);
	#}

	#if ($line =~ /\'\/aitoggle \"(.*)\"\'/) {	
	#	my $name = $1;
	#	my $found_player = $self->find_player($name);
	#	my $type;
	#	my $diff;
	#	if ($found_player->{type} =~ /AI/) {
	#		$type = "HUMAN";
	#	}
	#	else {
	#		$type = "AI";
	#	}
	#	if (defined($found_player->{difficulty})) {
	#		$diff = $found_player->{difficulty};
	#	}
	#	else {
	#		$diff = "easy";
	#	}
	#	my $player = {
	#		name => $name,
	#		type => $type,
	#		difficulty => $diff,
	#	};
	#	$self->debug("player $name has become $type");
	#	$self->set_player($player);
	#}


	## Player Removed (altogether pregame only)
	#if ($line =~ /Removing player (.+)\./) {
	#	$self->remove_player($1);
	#}
	
	if ($line =~ /Game saved as (.*)/) {
		$self->{data}->{LastSave} = $1;
		$self->_parse_savegame($self, $1);
	}

	## Human takes AI
	#if ($line =~ /(.*): \'\/take \"(.*)\"\'/) {
	#	print ("$1 is taking over $2\n");
	#
	#	my $left_player = $self->{data}->{players}->{$1};
	#	my $right_player = $self->{data}->{players}->{$2};
	#
	#	$self->debug("Left output: ". Dumper($left_player));
	#	$self->debug("Right output: ". Dumper($right_player));
#
#		my $merged_player = merge($left_player, $right_player);
#		$merged_player->{name} = $left_player->{name};
#
#		$self->debug("Merged output: ". Dumper($merged_player));
#
#		$self->set_player($merged_player);
#
#		$self->debug("PLAYERS! AFTER! MERGE!: ". Dumper($self->{data}->{players}));
#		$self->remove_player($2);
#	}
##	
	## debug info results
	if ($line =~ /players=(\d+) cities=(\d+) citizens=(\d+) units=(\d+)/) {
		my $players = $1;
		$current_turn->{cities} = $2;
		$current_turn->{citizens} = $3;
		$current_turn->{units} = $4; 
	}
	
	if ($line =~ /\/force (.*)\'/) {
		$self->send_server ("\/$1");
	}
}

sub _parse_log {
	my ($self, $line) = @_;
	my $current_turn = $self->current_turn;

	## End of turn
	if ($line =~ /End\/start-turn/) {
		if ($self->{game_restoring} == 1) {
			$self->debug ("**************SKIPPING TURN AS RESTORING********************");
			$current_turn->{restart_time} = "". DateTime->now();
			$self->{game_restoring} = 0;
		}
		else {
			$current_turn->{end_time} = "". DateTime->now();
			$self->debug("\t". Dumper $current_turn);
			$current_turn = $self->next_turn();
			$current_turn->{start_time} = "". DateTime->now();
		}
		$self->send_server ("/debug info");
		$self->send_server ("/write ". file($self->{dir_log}, "settings.serv"));
	}
		

	##	Player Connects
	if ($line =~ /2:\s+\((\d+)\)\s+(.*):\s+connected\s\[(.*)\]/) {
#			name => $2,
#			ip => [ $3 ],
#			connected => 1,
#			type => "HUMAN",
		my $id = $self->get_player_id($2);
		$self->debug("*** CON Player $id");
		if ($id >= 0) {
			$self->{data}->{players}->{$id}->{connected} = 1;
			$self->debug("*** CON Live Update Dump: ". Dumper ($self->{data}->{players}->{$id}));
		}
		$self->{players}->{$id}->{connected} = 1;
		$self->debug("*** CON Backup Update Dump: ". Dumper ($self->{players}->{$id}));
	}


	##	Players assigned at game start
	#if ($line =~ /assigning\splayer\s(\d+)\s\((.*)\)\sto\spos\s(\d+)/) {
#		my $player = {
#			number => $1 + 1,
#			nation => $2,
#			start_pos => $3,
#		};
#		$player = $self->extractnationruleset($player);
#		$self->debug("assigning player :". Dumper($player));
#		$self->set_player($player);
#	}
	
	## Connection lost
	if ($line =~ /Lost connection: (.*) from (.*) \(player (.*)\)/) {

		my $id = $self->get_player_id($1);
		if ($id >= 0) {
			$self->{data}->{players}->{$id}->{connected} = 0;
		}
		$self->{players}->{$id}->{connected} = 0;
#			name => $1,
#			ip => [$2],
#			leader => $3,
#			connected => 0,
	}


	## AI Added
#	if ($self->{data}->{turn_count} == -1) {
#		if ($line =~ /2: (.+) has been added as (.+) level AI-controlled player\./) {
#			my $player = {
#				name => $1,
#				type => "AI",
#				difficulty => $2,
#				connected => 1,
#			};
#			$self->debug("AI created: " . Dumper($player));
#			$self->set_player($player);
#		}
#	}

	## Grab Ruler names	
#	if ($line =~ /2: (.*) rules the (.*)\./) {
#		$self->{ruler_count}++;
#		my $player = {
#			number => $self->{ruler_count},
#			leader => $1,
#			nation => $2,
#		};
#		$self->set_player($player);
#	}


	# FIXME: broken assumptions we never want to do this
	# we should only have one game per log, or we start needing to track line numbers :-(
#	if ($line =~ /log started/) {
#		$self->debug("log started: " . Dumper($self));
#		$self->_init();
#	}
}

sub get_player_id {
	my ($self, $name) = @_;
	
	for( values %{$self->{data}->{players}} ) {
		if ($name == $_->{name}) {
			return $_->{number};
		}
	}
	return -1;
}

sub evalfile {
	my ($self, $file) = @_;
	my $str;
	my $VAR1;
	if ( -f $file ) {
		open (HD, $file) || die "unable to open script: $file";
		my @lines = <HD>;
		close (HD);
		foreach my $line (@lines) {
			$str .= $line;   # Accumulate the entire file.
		}
		eval $str;
	}
	$self->debug("EVALED OUTPUT: " . Dumper($VAR1));
	return $VAR1;
}

sub restoredata {
	my ($self, $file) = @_;
#	debug("restoring data!\n");
	$self->{data} = $self->evalfile($file);
	$self->{game_restoring} = 1;
#	debug("repairing data!\n");
#	$self->repair_players;
}

sub extractflagfromnationruleset { #($player)
	my ($self, $player) = @_;
	my $nation_dir = dir($self->{dir_base}, "nation");
	my $nation_file = dir($nation_dir, lc($player->{nation}) . ".ruleset");
	my $flags_file = file($self->{dir_base}, "flags.spec");
	my $nation_flag = "unknown";
	open( NATIONFILE, "< $nation_file" );
	while( <NATIONFILE> ) {
		if (/flag\s*=\s*\"(.*)\"/) {
			$nation_flag = $1;
		}
	}
	open 
	close (NATIONFILE);

	open( FLAGSFILE, "< $flags_file" );
	while( <FLAGSFILE> ) {
		if (/\"f\.$nation_flag\", \"flags\/(.+)\"/) {
			$player->{flag} = $1;
		}
	}
	open 
	close (FLAGSFILE);

	return $player;
}

sub debug {
	my ($self, $msg) = @_;
	if($self->{debug} || $ENV{DEBUG}) {
		print "$msg\n";
	}
}

sub turns {
	my ($self) = @_;
	
	return $self->{data}->{turns};
}

sub players {
	my ($self) = @_;
	
	return $self->{data}->{players};
}

#sub find_player {
#	my ($self, $player) = @_;
#	my $players = $self->players();
#	$self->debug("Finding: $player");
#	$self->debug("Found: " . Dumper($self->{data}->{players}));
#	return $players->{$player};
#}

#sub repair_players {
#	my ($self, $args) = @_;
#	my $players;
#	$self->debug ("ENTERING PLAYER LOOP");
#	for( values %{$self->{data}->{players}} ) {
#		$self->debug ("DUMPING PLAYER: " . Dumper($_));
#		if ($_->{number} > 0) {
#			$self->debug ("number is : " . $_->{number});
	#		$players->{$_->{name}} = #$self->{data}->{players}->{$_->{number}};
	#		$players->{$_->{number}} = #$self->{data}->{players}->{$_->{name}};
#		}
#	}
#	$self->debug ("FIXED PLAYERS: ". Dumper($players));
#	return $players;
#}

#sub remove_player {
#	my ($self, $playername) = @_;
#	my $removednumber = scalar $self->{data}->{players}->{$playername}->{number};
	#$self->debug ("Removing player: $playername\n");
#	$self->debug (Dumper($self->{data}->{players}->{$playername}));
	
#	for (my $i= 1; $i <= $self->{data}->{player_count}; $i++) {
#		delete $self->{data}->{players}->{$i};
#	}

#	$self->{deletedplayer} = $self->{data}->{players}->{$playername};
#	delete $self->{data}->{players}->{$playername};
	
#	$self->debug ("Players Left: ". Dumper ($self->{data}->{players}));
#	for( values %{$self->{data}->{players}} ) {
#		if ($_->{number} > $removednumber) {
#			print $_->{number} . "\n";
#			$_->{number}--;
#		}
#		$self->{data}->{players}->{$_->{number}} = $self->{data}->{players}->{$_->{name}};
#
		####### It seems that players get removed in server.output before aitoggle happens in game.log not sure why... need to check this asumtion is always right if its not we might have to implement something like below:
		## This next little bit makes sence i promise - it re-associates the correct key name to the connection name. should only happen when a player takes over another.
#		if ($self->{data}->{players}->{$_->{name}}->{name} ne $_->{name}) {
#			$self->{data}->{players}->{$_->{name}} = $self->{data}->{players}->{$_->{number}};
#			delete $self->{data}->{players}->{$_->{name}};
#		}
#	}
#
#	$self->{data}->{player_count}--;	
#
#}

#sub set_player {
#	my ($self, $input_player) = @_;
#	my $players = $self->players();
#	my $player_found;
#
#	if ($input_player->{number} > 0) {
#		$self->debug("Searching for exisitng player by: $input_player->{number}");
#		$player_found = $self->find_player($input_player->{number});
#	}
#	else {  # if (defined($input_player->{number})) {
#		$self->debug("Searching for exisitng player by: $input_player->{name}");
#		$player_found = $self->find_player($input_player->{name});
#	}
#	
#	$self->debug("Player Found: " . Dumper($player_found));	
#
#	if (defined $player_found) {
#		$self->debug("Existing player found: " . Dumper($player_found));	
#		$input_player = merge($player_found, $input_player);
#	}
#	else {
#		$self->debug("Creating new player");
#		$self->{data}->{player_count}++;
#		$input_player->{number} = $self->{data}->{player_count};
#	}
#
#	$players->{$input_player->{name}} = $input_player;
#	$players->{$input_player->{number}} = $input_player;
#
#	return $input_player;
#
#}

sub start_server {
	my ($self, $args) = @_;
	$self->{pid} = open2(\*CHLD_OUT, \*CHLD_IN, "civserver " . $args);
	$self->{SERVER} = *CHLD_IN;
#	return {$self-{pid}};
}

sub send_server {
	my ($self, $command) = @_;
	print { $self->{SERVER} } "$command\n";
}

sub current_turn {
	my ($self) = @_;
	my $turns = $self->turns();
	$turns->{$self->{data}->{turn_count}} ||= {};
	my $current_turn = $turns->{$self->{data}->{turn_count}};
	return $current_turn;
}

sub next_turn {
	my ($self) =@_;
	my $turns = $self->turns();
	$self->{data}->{turn_count}++;
	my $current_turn = $self->current_turn();
	$self->debug("new turn $turns->{count}");
	return $current_turn;
}

1;
