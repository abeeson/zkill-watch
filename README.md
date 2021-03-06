# zkill-watch
A script to automatically monitor zkillboard (via websocket) and report kills that match specific criteria

## Requirements

### Perl modules

Can be installed from CPAN if unavailable in your OS packages
* Config::Simple
* JSON
* JSON::PP (Required by Mojo but not listed in dependencies)
* Mojo::UserAgent
* IO::Socket::SSL (v2.0.99+)
* REST::Client
* LWP::Protocol::https

## Configuration

### Slack

Set up a slack bot via your slack settings. You want a generic slack bot that is capable of posting to your channel. You can invite it into the channel once you have created it.

### Systems

The systems you want to monitor must be supplied to the script as exact system names.

### Ship groups

Ship monitoring is done per group, rather than per ship (i.e. instead of monitoring for Archons, Chimeras, Nidhoggurs and Thanatos kills, we just check for Carrier type ships)
These are supplied to the script in ID and name pairs, however there is no single way to find group IDs easily.
To find the group ID you need, you need to do two things:
1. Search for any ship in the group by going here: https://esi.evetech.net/dev/search/?categories=inventory_type&strict=1&search=*shipName*
2. Take the ID you get from 1. and search here http://esi.evetech.net/v3/universe/types/*IDHere*, then get the "group_id" from that. Ensure you get the group_id, not the market_group_id

## To-Do

* add pre-ESI get sub to return object if present or get if not to standarise the request process and remove duplication/check requirements
* Simplify ship group to just be by name - no easy ESI entry to do this though

## Notes

The script currently loops inside an infinite while, this is to ensure the websocket will restart if it closes, without losing all the built up objects for systems, ships etc (and preventing extra hits on the ESI APIs)
Auto channel join for slack is not supported for bots, so ensure you have invited the bot to the channel you want it to post in, or this will fail
