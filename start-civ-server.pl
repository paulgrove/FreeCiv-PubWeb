#!/usr/bin/perl

use strict;
use warnings;

use DateTime;
use Config::Simple;
use Path::Class;
use Unix::PID;
use Time::Interval;
use File::Touch;
use POSIX ":sys_wait_h";

#use Proc::ProcessTable::Process;

# find where we live
use FindBin qw($Bin);
# include our lib search path
use lib dir($Bin, "lib")->stringify;

use FreeCiv;

my $dir_base =  dir($ENV{"HOME"}, "FreeCiv-PubWeb");
my $file_auth = file($dir_base, "fc_auth.conf");
my $file_default_server_setttings = file($dir_base, "defaultserversettings.serv");

my $pid_obj = Unix::PID->new();

# Create Objects
my $cfg = new Config::Simple(file($dir_base, 'civ.cfg'));

# Create Base Directories

sub isint{
  my $val = shift;
  return ($val =~ m/^\d+$/);
}

my $restore = 0;
my $last_id;
my $id;

$last_id = $cfg->param('Last_Game_ID') + 1 or $last_id = 1;

if ($#ARGV+1 == 1) {
	$id = $ARGV[0];
	if ($id <= $last_id) {
		$restore = 1;
	}
	else {
		$id = $last_id;
	}
}
elsif ($#ARGV+1 == 0) {
	$id = $last_id;
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

	my $dir_log = dir($dir_base, "logs", $id);
	my $dir_save = dir($dir_base, "savegames", $id);
	my $file_rank_log = file($dir_log, "rank.log"); 
	my $file_game_log = file($dir_log, "game.log");
	my $file_server_output = file($dir_log, "server.output");
	my $file_script_output = file($dir_log, "script.pl");
	my $file_server_settings = file($dir_log, "settings.serv");
	$dir_log->mkpath() unless -d $dir_log;
	$dir_save->mkpath() unless -d $dir_save;

	my $fc = FreeCiv->new({debug => 1, dir_base => $dir_base, dir_log => $dir_log});

	print "Game ID: $id\n";
	print "Avaliable Ports: " . @ports  . "\n";
	if ($restore == 1) {
		print ("gunna restore data\n");
		$fc->restoredata($file_script_output);
	}
	$fc->{data}->{port} = pop(@ports);
	$cfg->param('Avaliable_Ports', "@ports");
	if ($restore == 0) {
		$cfg->param('Last_Game_ID', $id);
	}
	$cfg->save();

	my($chld_out, $chld_in);

	if (($restore == 1) && (defined($fc->{data}->{LastSave}))) {
		unlink ($file_game_log);
		$fc->start_server("-P -e -p $fc->{data}->{port} -a $file_auth -r $file_server_settings -R  $file_rank_log -s $dir_save -d 3 -l $file_game_log -f $fc->{data}->{LastSave} > $file_server_output");
	}
	else {
		$fc->start_server("-P -e -p $fc->{data}->{port} -a $file_auth -r $file_default_server_setttings -R  $file_rank_log -s $dir_save -d 3 -l $file_game_log > $file_server_output");
	}

	print "child server is running with pid = $fc->{pid}\n";
	
	$fc->loadfiles({log_file => $file_game_log, server_file => $file_server_output, lastrun_dir => $dir_log} ); # open gamelog file for tail
	$fc->{data}->{serverrunning} = 1;
	$fc->readlines;
	$fc->dumpoutput({output_filename => $file_script_output});

	print "Entering loop\n";

	my $timer = DateTime->now(); # start timer

	while (kill(0, $fc->{pid})) { # Is child (civserver) process alive?
		if (getInterval($timer, DateTime->now())->{seconds} > 5) { # wait 5 seconds
			$fc->readlines; # process all new lines
			$timer = DateTime->now(); # Reset timer
			$fc->dumpoutput({output_filename => $file_script_output});
		}
		waitpid(-1, WNOHANG);  ## This clears the zombies with hanging.
		sleep 1; ## Prevent crazy CPU usage
	}

	$fc->readlines;
			
	$fc->dumpoutput({output_filename => $file_script_output});

	# Server has stopped - Release port for new servers to use.
	@ports = split(' ', $cfg->param('Avaliable_Ports'));
	push (@ports, $fc->{data}->{port});
	$cfg->param('Avaliable_Ports', "@ports");
	$cfg->save();

}
else {
	print "All game slots are full.\n";
}

#civserver -N -P -e -p 5558 -a ~/.freeciv/fc_auth.conf -r ~/.freeciv/serversettings -R ~/.freeciv/ranklog5558 -s ~/.freeciv/savegames5558 -d 4 -l ~/.freeciv/logs/game5558.log -R ~/.freeciv/logs/rank.log 
