# zkill-watch
A script to automatically monitor zkillboard (via websocket) and report kills that match specific criteria

##Requirements
###Perl modules
Can be installed from CPAN if unavailable in your OS packages
* Config::Simple
* Mojo::UserAgent
* IO::Socket::SSL (v2.0.99+)

##Configuration
###Slack
Set up a slack bot via your slack settings. You want a generic slack bot that is capable of posting to your channel. You can invite it into the channel once you have created it.

##To-Do
Move system and ship group IDs to config file
Move slack channel name to config file
Test slack post without being in channel, expect failure. Write channel join if that is the case
