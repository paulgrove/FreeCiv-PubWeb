#!/usr/bin/perl

use strict;
use warnings;

use Config::Simple;
use Path::Class;
use Unix::PID;


# find where we live
use FindBin qw($Bin);
# include our lib search path
use lib dir($Bin, "lib")->stringify;

my $pid = Unix::PID->new();


# Constants
use constant DIR_BASE => "/home/freeciv/";
use constant DIR_LOGS => DIR_BASE . "logs/";
use constant DIR_SAVEGAMES => DIR_BASE . "savegames/";

#my 


# Create Objects
my $cfg = new Config::Simple('civ.cfg');

# Create Base Directories
mkdir DIR_LOGS;
mkdir DIR_SAVEGAMES;

sub isint{
  my $val = shift;
  return ($val =~ m/^\d+$/);
}

my $id;
if ($#ARGV+1 == 1) {
	$id = $ARGV[0];
}
elsif ($#ARGV+1 == 0) {
	$id = $cfg->param('Last_Game_ID') + 1 or $id = 1;
}
else {
	print "\nUsage:\n\n";
	print "start-civ-server.pl [gameid]\n";
	print "\n";
	exit;
}


my @ports;

if (defined $cfg->param('Avaliable_Ports')) {
	@ports = split(' ', $cfg->param('Avaliable_Ports')); 
}
else {
	@ports = (5556..5565);
}

if (isint($ports[$#ports])) { # Port to be popped sanity check 
	print "Game ID: $id\n";
	print "Avaliable Ports: " . @ports  . "\n";
	my $port = pop(@ports);

	my $dir_base =  dir($ENV{"HOME"});
	my $file_auth = file($dir_base, "fc_auth.conf");
	my $file_serversetttings = file($dir_base, "serversettings.serv");
	my $dir_log = dir($dir_base, "logs", $id);
	my $dir_save = dir($dir_base, "savegames", $id);
	my $file_rank_log = file($dir_log, "rank.log"); 
	my $file_game_log = file($dir_log, "game.log");

	$dir_log->mkpath() unless -d $dir_log;
	$dir_save->mkpath() unless -d $dir_save;

#	my $file_cfg = file($dir_base, "fc_auth.conf");

	print "Selected Port: $port\n";
	print "Remaining Ports: " . "@ports" . "\n";

	mkdir DIR_LOGS . $id;
	mkdir DIR_SAVEGAMES . $id;
	
	my $pid = fork();
	if ($pid == -1 ) {
		die "could not fork $!";
	} elsif ($pid == 0 ) {
		# child 
		close STDOUT;
		close STDIN;
		close STDERR;
		
		exec ("civserver -N -P -e -p $port -a $file_auth -r $file_serversetttings -R  $file_rank_log -s $dir_save -d 3 -l $file_game_log");
#			or ";
	} else {
		# parent
		print "child server is running with pid = $pid\n";
		my $fc = FreeCiv->new({ turns => 0 }  );
		$fc->create_tail_app( {log_file => $file_game_log} );
		#$fc->{turns}
	}
	$cfg->param('Avaliable_Ports', "@ports");
	$cfg->param('Last_Game_ID', $id);
	$cfg->save();

	
}
else {
	print "All game slots are full.\n";
}

#civserver -N -P -e -p 5558 -a ~/.freeciv/fc_auth.conf -r ~/.freeciv/serversettings -R ~/.freeciv/ranklog5558 -s ~/.freeciv/savegames5558 -d 4 -l ~/.freeciv/logs/game5558.log -R ~/.freeciv/logs/rank.log 
