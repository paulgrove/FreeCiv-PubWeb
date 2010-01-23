package FreeCiv;

use File::Tail;
use Data::Dumper;
use DateTime;
use Data::Dumper;
use Hash::Merge qw(merge);

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

	$self->{turns} = { count => 0 };
	$self->{players} = {};
#	$self->{port} = 0;

}

sub loadfile {
	my ($self, $args) = @_;
	$self->{file}=File::Tail->new(name=>$args->{log_file}, nowait=>1, ignore_nonexistant=>1);
}

sub dumpoutput {
	my ($self, $args) = @_;
	open FILE, ">", $args->{output_filename} or warn "Cant open file";
	print FILE Dumper($self);
	close FILE;
}

sub readlines {
	my ($self, $args) = @_;
	my $line;
	$line=$self->{file}->read;
	print $line; ## FIXME ## Can the asignment and the check all go in the while condition. would save some processing.
	while ($line > "") { ## if there is no lines remaining read will return ""
		print DateTime->now() . $line;
		_parse_log($self, $line);
		$line=$self->{file}->read;
	}
}

=c
		$fc = {
			turns => {
				count => 4,
				0 => { start_time }
 				1 => {},
				2 => {},
			},
			players => {
				count => 102;
				0 => {
					name => "blah",
					stuff => "more stuff",
				}
				1 => {}
			},
		}
=cut

sub _parse_log{
	my ($self, $line) = @_;
	my $current_turn = $self->current_turn;
	my $turns = $self->turns();
	my $players = $self->players;

	## End of turn
	if ($line =~ /End\/start-turn/) {
		if ($turns->{count} > 0) {
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
		};

		$self->debug("adding player :". Dumper($player));
		$self->set_player($player);
}	

	##	Players assigned at game start
	if ($line =~ /assigning\splayer\s(\d+)\s\((.*)\)\sto\spos\s(\d+)/) {
		my $player = {
			number => $1,
			nation => $2,
			start_pos => $3,
		};
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

	# FIXME: broken assumptions we never want to do this
	# we should only have one game per log, or we start needing to track line numbers :-(
#	if ($line =~ /log started/) {
#		$self->debug("log started: " . Dumper($self));
#		$self->_init();
#	}
}

sub debug {
	my ($self, $msg) = @_;
	if($self->{debug} || $ENV{DEBUG}) {
		print "$msg\n";
	}
}

sub turns {
	my ($self) = @_;
	
	return $self->{turns};
}

sub players {
	my ($self) = @_;
	
	return $self->{players};
}

sub find_player {
	my ($self, $player) = @_;
	my $players = $self->players();
	return $players->{$player};
}

sub set_player {
	my ($self, $player) = @_;
	my $player_found;
	my $players = $self->players();

#	if (defined($player->{name}) {	
		$player_found = $self->find_player($player->{name});
#	else {
#		$player_found = $self->find_player($player->{number});
#	}

	if (defined $player_found) {
		$player = merge($player, $player_found);
	}
	else {
		$players->{count}++;
	}

#	if (defined($player->{name})) {
	$players->{$player->{name}} = $player;
#	}
	
#	$players->{$player->{number}} = $player;
	
	return $player;
}

sub current_turn {
	my ($self) = @_;
	my $turns = $self->turns();
	$turns->{$turns->{count}} ||= {};
	my $current_turn = $turns->{$turns->{count}};

	return $current_turn;
}

sub next_turn {
	my ($self) =@_;
	my $turns = $self->turns();
	$turns->{count}++;
	my $current_turn = $self->current_turn();
	$self->debug("new turn $turns->{count}");
	return $current_turn;
}

1;
