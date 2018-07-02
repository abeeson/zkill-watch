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
###Systems
The systems you want to monitor must be supplied to the script in ID and name pairs.
To find the ID of your system, go to this address with your system name at the end (spelt exactly): https://esi.evetech.net/dev/search/?categories=solar_system&strict=1&search=*systemName*
###Ship groups
Ship monitoring is done per group, rather than per ship (i.e. instead of monitoring for Archons, Chimeras, Nidhoggurs and Thanatos kills, we just check for Carrier type ships)
These are supplied to the script in the same way as the systems, in ID and name pairs, however there is no single way to find group IDs easily.
To find the group ID you need, you need to do two things:
1. Search for any ship in the group by going here: https://esi.evetech.net/dev/search/?categories=inventory_type&strict=1&search=*shipName*
2. Take the ID you get from 1. and search here http://esi.evetech.net/v3/universe/types/*IDHere*, then get the "group_id" from that. Ensure you get the group_id, not the market_group_id

##To-Do
Move system and ship group IDs to config file
add pre-ESI get sub to return object if present or get if not to standarise the request process and remove duplication/check requirements
Simplify ship group and system match groups to just be by name
Test slack post without bot being in channel, expect failure. Write channel join if that is the case
