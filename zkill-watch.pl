#!/usr/bin/perl

use strict;
use warnings;

# Zkill - Use websockets via Mojo
use Mojo::UserAgent;
use Mojo::IOLoop;

# ESI calls - Simple GETs etc
use REST::Client;
use JSON;

use Data::Dumper;

# Declare prototypes
sub esi_search($$);

# Add config simple for slack bot key
use Config::Simple;

# Get config object
our $cfg = new Config::Simple('zkill-watch.config');

# Get global config options we need to assume state on if not present
our $debug = $cfg->param("DEBUG") || 1;
# Default distances - Blops range with no minimum
our $max_ly = $cfg->param("MAX_LY") || 8;
our $min_ly = $cfg->param("MIN_LY") || 0;


# Declare hashes we will use while we sit running to prevent duplicate API calls
our $systems = {};
our $constellations = {};
our $ships = {};

# Get ESI and slack client
our $esi_client = esi_get_client();
our $slack_client = slack_get_client();

our $ship_groups = {};

# Pull ship groups from config file and build ship_groups list
foreach my $ship_group ($cfg->param("SHIP_GROUPS")) {
	my @entry = split(/:/,$ship_group);
	$ship_groups->{$entry[0]} = $entry[1] if ($entry[0] =~ m/^\d*$/);
	print "Ship group entry $entry[0]:$entry[1] looks bad, skipped\n" unless ($entry[0] =~ m/^\d*$/);
}

our $system_checks = {};

# Pull system list from config, get IDs and build system_checks list
foreach my $sys_check ($cfg->param("SYSTEMS")) {
	my $sys_id = esi_search("solar_system",$sys_check);
	
	$system_checks->{$sys_id->{"solar_system"}->[0]} = $sys_check if $sys_id->{"solar_system"}->[0];
	print "$sys_check not found, skipping\n" unless $sys_id->{"solar_system"}->[0];
}

# Get system objects for distance calcs 
foreach my $id (keys %{$system_checks}) {
  esi_get_system($id);
}

# Open WebSocket to echo service
my $ua = Mojo::UserAgent->new;

# Set timers to be higher to prevent script stops
$ua->inactivity_timeout(300);
$ua->request_timeout(30);

while(42) {
  $ua->websocket('wss://zkillboard.com:2096/' => { DNT => 1 } => sub {
    my ($ua, $tx) = @_;

    # Check if WebSocket handshake was successful
    print "Error - ".$tx->error->{"message"}."\n" if $tx->error;
    print "WebSocket handshake failed!\n" and return unless $tx->is_websocket;
 
    # Send a message to the server
    $tx->send('{"action":"sub","channel":"killstream"}');

    $ua->on(error => sub {
      my ($ua, $err) = @_;
      print "UA Error: $err\n";
    });

    $tx->on(error => sub {
      my ($tx, $err) = @_;
      print "TX Error: $err\n";
    });

    # Wait for WebSocket to be closed
    $tx->on(finish => sub {
      my ($tx, $code, $reason) = @_;
      print "WebSocket closed with status $code.\n" if ($debug == 1);
    });
 
    $tx->on(message => sub {
      my ($tx, $msg) = @_;
      process_kill(decode_json($msg));
      #Stop after this message - useful for testing
      #$tx->finish;
    });
  });

  # Start event loop if not running
  print "starting new loop\n" if ($debug == 1);
  Mojo::IOLoop->start;
  Mojo::IOLoop->stop;
  sleep 1;
}

sub process_kill {
  my $kill = shift;
  my $ship_match = 0;
  my $distance_match = 0;
  my $message = "";
  my $found_ships = {};
  my $distances = "";

  print "Kill ".$kill->{"zkb"}->{"url"}."\n";
  # Get attacker ship IDs and process through ESI if we don't already know what they are
  foreach my $attacker (@{$kill->{"attackers"}}) {
    # Skip attacker entries with no ship type at all - the ? entries in zkill
    next unless defined $attacker->{"ship_type_id"};
    esi_get_ship($attacker->{"ship_type_id"}) unless $ships->{$attacker->{"ship_type_id"}};
    if ($ship_groups->{$ships->{$attacker->{"ship_type_id"}}->{"group_id"}}) {
      #Found matching ship group ID
      print "Found matching ship - ".$ships->{$attacker->{"ship_type_id"}}->{"name"}."\n" if ($debug == 1);
      #$message .= "Found ".$ships->{$attacker->{"ship_type_id"}}->{"name"}."\n";
      $found_ships->{$ships->{$attacker->{"ship_type_id"}}->{"name"}}++;
      $ship_match = 1;
    }
  }

  # Get system details for kill system if we don't already have it
  esi_get_system($kill->{"solar_system_id"}) unless $systems->{$kill->{"solar_system_id"}};

  foreach my $id (keys %{$system_checks}) {
    my $distance = calc_distance($systems->{$id},$systems->{$kill->{"solar_system_id"}}); 
    $distances .= "Distance to ".$system_checks->{$id}.": ".sprintf("%.4f", $distance)." LY\n";
    $distance_match = 1 if ($distance <= $max_ly && $distance >= $min_ly);
  }
  if ($ship_match eq "1") {
    if ($distance_match eq "1") {
      $message .= "Kill in *".$systems->{$kill->{"solar_system_id"}}->{"name"}."*\n";
      foreach my $found_ship (keys %{$found_ships}) {
        $message .= $found_ship." x".$found_ships->{$found_ship}."\n";
      }
      $message .= $distances;
      $message .= $kill->{"zkb"}->{"url"};
      slack_post_kill($message);
    } else {
      print $message if ($debug == 1);
    }
  } else {
    print " No matching ship types\n" if ($debug == 1);
  }
}

sub check_system_in_region($$) {
  my $sys_id = shift;
  my $reg_id = shift;

  esi_get_system($sys_id) unless $systems->{$sys_id};
  esi_get_constellation($systems->{$sys_id}->{"constellation_id"}) unless $constellations->{$systems->{$sys_id}->{"constellation_id"}};
  
  if ($constellations->{$systems->{$sys_id}->{"constellation_id"}} eq $reg_id) {
    #System in region
    return 1;
  } else {
    #System not in region
    return 0;
  }
}

sub esi_get_client {
  my $server = "https://esi.evetech.net";
  
  my $client = REST::Client->new();
  $client->setHost("$server");
  $client->getUseragent()->ssl_opts(verify_hostname => '0');
  $client->getUseragent()->ssl_opts(SSL_verify_mode => '0');
  return $client;
}

sub esi_get_ship {
  #Pull ID
  my $id = shift;
  
  #Collect object from ESI
  my $ship = esi_get("/v3/universe/types/".$id."/");

  #Add to ships object
  $ships->{$id} = $ship;
}

sub esi_get_system {
  #Pull ID
  my $id = shift;

  #Collect object from ESI
  my $system = esi_get("/v3/universe/systems/".$id."/");

  #Add to systems object
  $systems->{$id} = $system;
}

sub esi_get_constellation {
  #Pull ID
  my $id = shift;

  #Collect object from ESI
  my $constellation = esi_get("/v3/universe/constellations/".$id."/");

  #Add to constellations object
  $constellations->{$id} = $constellation;
}

sub esi_search($$) {
  #Pull category and name
  my $category = shift;
  my $name = shift;

  return esi_get("/v2/search/?strict=1&categories=".$category."&search=".$name);
}

sub esi_get($) {
  #Pull call
  my $call = shift;
  
  #make GET call
  $esi_client->GET($call);

  #Return after decoding the JSON
  return decode_json($esi_client->responseContent);
}

sub slack_get_client {
  my $server = "https://slack.com";
  
  my $client = REST::Client->new();
  $client->setHost("$server");
  $client->addHeader("Authorization", "Bearer ".$cfg->param("SLACK_API"));
  $client->addHeader("Content-Type", "application/json; charset=utf-8");
  $client->getUseragent()->ssl_opts(verify_hostname => '0');
  $client->getUseragent()->ssl_opts(SSL_verify_mode => '0');

  return $client;
}

sub slack_post_kill($) {
  my $message = shift;

  my $object = {
    "channel" => $cfg->param("SLACK_CHANNEL"),
    "text"    => $message,
    "unfurl_links" => "true",
    "as_user" => "true"
  };

  $slack_client->POST("/api/chat.postMessage",encode_json($object));  
}

sub calc_distance($$) {
  # Must be system objects, not names
  my $system1 = shift;
  my $system2 = shift;

  #Get distance differences between the two points for x,y,z
  my $x_diff = get_diff($system1->{"position"}->{"x"},$system2->{"position"}->{"x"});
  my $y_diff = get_diff($system1->{"position"}->{"y"},$system2->{"position"}->{"y"});
  my $z_diff = get_diff($system1->{"position"}->{"z"},$system2->{"position"}->{"z"});
  
  #Sum ^2s and square root for direct line distance
  my $xyz_diff = sqrt($x_diff**2 + $y_diff**2 + $z_diff**2);
  
  #Convert from metres to LY and return
  return ($xyz_diff/(9.461*10**15));
}

sub get_diff($$) {
  #Take two integer values and calculate the positive difference
  my $val1 = shift;
  my $val2 = shift;

  return $val1-$val2 if $val1 >= $val2;
  return $val2-$val1 if $val2 > $val1;
}
