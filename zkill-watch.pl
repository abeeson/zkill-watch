#!/usr/bin/perl

use strict;
use warnings;

our $debug = 1;

# Zkill - Use websockets via Mojo
use Mojo::UserAgent;
use Mojo::IOLoop;

# ESI calls - Simple GETs etc
use REST::Client;

use JSON;

# Add config simple for slack bot key
use Config::Simple;

our $cfg = new Config::Simple('zkill-watch.config');

# Declare hashes we will use while we sit running to prevent duplicate API calls
our $systems = {};
our $constellations = {};
our $ships = {};

our $ship_groups = { 
  "30"  => {"name" => "Titan"},
  "547" => {"name" => "Carrier"},
  "485" => {"name" => "Dreadnought"},
  "659" => {"name" => "Supercarrier"},
  "1538" => {"name" => "Force Auxiliary"}
};

our $system_checks = {
  "30002718" => "Rancer",
  "30002719" => "Miroitem",
  "30002691" => "Crielere"
};

# Get ESI and slack client
our $esi_client = esi_get_client();
our $slack_client = slack_get_client();

# Get systems for distance calcs 
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
      print "WebSocket closed with status $code.\n";
    });
 
    $tx->on(message => sub {
      my ($tx, $msg) = @_;
      process_kill(decode_json($msg));
      #Stop after this message - useful for testing
      #$tx->finish;
    });
  });

  # Start event loop if not running
  print "starting new loop\n";
  Mojo::IOLoop->start;
  Mojo::IOLoop->stop;
  sleep 5;
}

sub process_kill {
  my $kill = shift;
  my $ship_match = 0;
  my $distance_match = 0;
  my $message = "";

  print "Kill ".$kill->{"zkb"}->{"url"}."\n";
  # Get attacker ship IDs and process through ESI if we don't already know what they are
  foreach my $attacker (@{$kill->{"attackers"}}) {
    # Skip attacker entries with no ship type at all - the ? entries in zkill
    next unless defined $attacker->{"ship_type_id"};
    esi_get_ship($attacker->{"ship_type_id"}) unless $ships->{$attacker->{"ship_type_id"}};
    if ($ship_groups->{$ships->{$attacker->{"ship_type_id"}}->{"group_id"}}) {
      #Found matching ship group ID
      print "Found matching ship - ".$ships->{$attacker->{"ship_type_id"}}->{"name"}."\n";
      $ship_match = 1;
    }
  }

  # Get system details for kill system if we don't already have it
  esi_get_system($kill->{"solar_system_id"}) unless $systems->{$kill->{"solar_system_id"}};

  foreach my $id (keys %{$system_checks}) {
    my $distance = calc_distance($systems->{$id},$systems->{$kill->{"solar_system_id"}}); 
    $message .= "Distance to ".$system_checks->{$id}.": ".sprintf("%.4f", $distance)." LY\n";
    $distance_match = 1 if ($distance <= 8);
  }
  if ($ship_match eq "1") {
    if ($distance_match eq "1") {
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
