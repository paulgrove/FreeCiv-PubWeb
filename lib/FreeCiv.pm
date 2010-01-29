package FreeCiv;

use File::Tail;
use Data::Dumper;
use DateTime;
use Data::Dumper;
use Hash::Merge qw(merge);
use Config::Simple;
use Path::Class;

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

	$self->{data}->{turns} = {};
	$self->{data}->{players} = {};
#	$self->{port} = 0;

}

sub loadfile {
	my ($self, $args) = @_;
	$self->{file}=File::Tail->new(name=>$args->{log_file}, nowait=>1, ignore_nonexistant=>1);
}

sub dumpoutput {
	my ($self, $args) = @_;
	open FILE, ">", $args->{output_filename} or warn "Cant open file";
	print FILE Dumper($self->{data});
	close FILE;
}

sub readlines {
	my ($self, $args) = @_;
	my $line;
	$line=$self->{file}->read;
	print $line; ## FIXME ## Can the asignment and the check all go in the while condition. would save some processing.
	while ($line > "") { ## if there is no lines remaining read will return ""
	#	print DateTime->now() . $line;
		_parse_log($self, $line);
		$line=$self->{file}->read;
	}
}

sub _parse_log{
	my ($self, $line) = @_;
	my $current_turn = $self->current_turn;
#	my $turns = $self->turns();
#	my $players = $self->players;

	## End of turn
	if ($line =~ /End\/start-turn/) {
		if ($self->{data}->{turn_count} > 0) {
			$current_turn->{end_time} = "". DateTime->now();
			$self->debug("\t". Dumper $current_turn);
		}
		$current_turn = $self->next_turn();
		$current_turn->{start_time} = "". DateTime->now();
		
	}

	##	Player Connects
	if ($line =~ /2:\s+\((\d+)\)\s+(.*):\s+connected\s\[(.*)\]/) {
		my $player = { 
		#	number => $1 - 1,  #  (not tied to player)
			name => $2,
			ip => [ $3 ],
			connected => 1,
			type => "HUMAN",
		};

		$self->debug("adding player :". Dumper($player));
		$self->set_player($player);
}	

	##	Players assigned at game start
	if ($line =~ /assigning\splayer\s(\d+)\s\((.*)\)\sto\spos\s(\d+)/) {
		my $player = {
			number => $1 + 1,
			nation => $2,
			start_pos => $3,
		};
		$player = $self->extractnationruleset($player);
		$self->debug("assigning player :". Dumper($player));
		$self->set_player($player);
	}
	
	## Connection lost
	if ($line =~ /Lost connection: (.*) from (.*) \(player (.*)\)/) {
		my $player = {
			name => $1,
			ip => [$2],
			leader => $3,
			connected => 0,
		};
		$self->debug("player disconnect:". Dumper($player));
		$self->set_player($player);
	}

	if ($line =~ /Removing player (.+)\./) {
		my $playername = $1;
		$self->remove_player($playername);
	}

	if ($line =~ /2: (.+) has been added as (.+) level AI-controlled player\./) {
		my $player = {
			name => $1,
			type => "AI",
			difficulty => $2,
		};
		$self->debug("AI created: " . Dumper($player));
		$self->set_player($player);
	}

	# FIXME: broken assumptions we never want to do this
	# we should only have one game per log, or we start needing to track line numbers :-(
#	if ($line =~ /log started/) {
#		$self->debug("log started: " . Dumper($self));
#		$self->_init();
#	}
}

sub extractnationruleset { #($player)
	my ($self, $player) = @_;
	my $nation_dir = dir($self->{dir_base}, "nation");
	my $nation_file = dir($nation_dir, lc($player->{nation}) . ".ruleset");
	open( FILE, "< $nation_file" );
	while( <FILE> ) {
		if (/flag\s*=\s*\"(.*)\"/) {
			$player->{flag} = $1;
		}
	}
	close (FILE);
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

sub find_player {
	my ($self, $player) = @_;
	my $players = $self->players();
#	$self->debug("Finding: $player");
#	$self->debug("Found: " . Dumper($self->{data}->{players}));
	return $players->{$player};
}

sub remove_player {
	my ($self, $playername) = @_;
	my $removednumber = scalar $self->{data}->{players}->{$playername}->{number};
	$self->debug ("Removing player: $playername\n");
	$self->debug (Dumper($self->{data}->{players}->{$playername}));
	
#	undef $self->{players}->{$playername};
	delete $self->{data}->{players}->{$playername}->{ip};
#	delete $self->{data}->{players}->{$playername};
#	delete $self->{data}->{players}->{$playername};
	delete $self->{data}->{players}->{$removednumber};

	foreach ($self->{data}->{players}) {
		if ($self->{data}->{players}->{$_}->{number} > $removednumber) { # $removednumber (willbe)
			$self->{data}->{players}->{$_}->{number}--;
		}
	}
	$self->{data}->{player_count}--;
}

sub set_player {
	my ($self, $input_player) = @_;
	my $players = $self->players();
	my $player_found;
#	$self->debug("Set player: " . Dumper($input_player)); 
#	if (defined($input_player->{number})) {	
	if ($input_player->{number} > 0) {
		$self->debug("Searching for exisitng player by: $input_player->{number}");
		$player_found = $self->find_player($input_player->{number});
	}
	else {  # if (defined($input_player->{number})) {
		$self->debug("Searching for exisitng player by: $input_player->{name}");
		$player_found = $self->find_player($input_player->{name});
	}
	
	$self->debug("Player Found: " . Dumper($player_found));	

#	$self->debug("Player Found Example 1: " . Dumper($self->{data}->{players}->{1}));	

#	$self->debug("Player Found Example og: " . Dumper($self->{data}->{players}->{og}));	

#	$self->debug("Player Found Example byref: " . Dumper($self->{data}->{players}->{"" .$input_player->{number}}));	

	if (defined $player_found) {
		$self->debug("Existing player found: " . Dumper($player_found));	
		$input_player = merge($player_found, $input_player);
	}
	else {
		$self->debug("Creating new player");
		$self->{data}->{player_count}++;
		$input_player->{number} = $self->{data}->{player_count};
	}

#	if (defined($player->{name})) {
	$players->{$input_player->{name}} = $input_player;
#	}
#	if (defined($player->{number})) {
	$players->{$input_player->{number}} = $input_player;
#	}

	return $input_player;

}

sub current_turn {
	my ($self) = @_;
#	my $turns = $self->turns();
#	$turns->{$self->{data}->{turn_count}} ||= {};
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
